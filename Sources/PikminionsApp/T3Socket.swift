// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Foundation

/// Version-2 T3 RPC over an authenticated loopback WebSocket. A command keeps its
/// caller-supplied commandId; transport errors never silently resubmit a write.
enum T3Socket {
    private static func socket(origin:URL,token:String) throws ->URLSessionWebSocketTask {
        guard var parts=URLComponents(url:origin,resolvingAgainstBaseURL:false) else {throw SourceFailure.message("The T3 address is unavailable.")}
        parts.scheme="ws";parts.path="/ws";parts.queryItems=[URLQueryItem(name:"orchestrationProtocol",value:"2")]
        guard let url=parts.url else {throw SourceFailure.message("The T3 address is unavailable.")}
        var request=URLRequest(url:url);request.timeoutInterval=12
        request.setValue("Bearer "+token,forHTTPHeaderField:"Authorization")
        let socket=URLSession.shared.webSocketTask(with:request);socket.maximumMessageSize=10_485_760
        return socket
    }
    private static func request(_ socket:URLSessionWebSocketTask,method:String,payload:JSONValue) async throws {
        let frame=JSONValue.object(["_tag":.string("Request"),"id":.string("1"),"tag":.string(method),"payload":payload,"headers":.array([])])
        try await socket.send(.data(JSONEncoder().encode(frame)))
    }
    private static func receive(_ socket:URLSessionWebSocketTask) async throws ->[JSONValue] {
        let message=try await socket.receive(),data:Data
        switch message {case .data(let bytes):data=bytes;case .string(let text):data=Data(text.utf8);@unknown default:throw SourceFailure.message("T3 sent an unsupported frame.")}
        guard data.count<=10_485_760 else {throw SourceFailure.message("T3 sent too much data for this view.")}
        let value=try JSONDecoder().decode(JSONValue.self,from:data)
        return value.array ?? [value]
    }
    static func call(origin:URL,token:String,method:String,payload:JSONValue) async throws ->JSONValue {
        let socket=try socket(origin:origin,token:token);socket.resume()
        let timeout=Task {do {try await Task.sleep(for:.seconds(12))} catch{return};socket.cancel(with:.goingAway,reason:nil)}
        defer {timeout.cancel();socket.cancel(with:.normalClosure,reason:nil)}
        return try await withTaskCancellationHandler {
            try await request(socket,method:method,payload:payload)
            for _ in 0..<32 {
                for frame in try await receive(socket) {
                    if frame["_tag"]?.string=="Ping" {try await socket.send(.string("{\"_tag\":\"Pong\"}"));continue}
                    if frame["_tag"]?.string=="Exit",let exit=frame["exit"] {
                        guard exit["_tag"]?.string=="Success" else {throw SourceFailure.message(errorMessage(exit))}
                        return exit["value"] ?? .null
                    }
                    if frame["_tag"]?.string=="Defect" {throw SourceFailure.message(errorMessage(frame))}
                }
            }
            throw SourceFailure.message("T3 did not acknowledge this action. Your draft is preserved.")
        } onCancel: {socket.cancel(with:.goingAway,reason:nil)}
    }
    static func stream(origin:URL,token:String,threadID:String,afterSequence:Double?=nil) throws ->AsyncThrowingStream<JSONValue,Error> {
        let socket=try socket(origin:origin,token:token)
        return AsyncThrowingStream(bufferingPolicy:.bufferingNewest(64)) { continuation in
            let task=Task {
                socket.resume()
                defer {socket.cancel(with:.normalClosure,reason:nil)}
                do {
                    var fields:[String:JSONValue]=["threadId":.string(threadID),"acceptBoundedSnapshot":.bool(true),"requestCompletionMarker":.bool(true)]
                    if let afterSequence {fields["afterSequence"] = .number(afterSequence)}
                    try await request(socket,method:"orchestration.subscribeThread",payload:.object(fields))
                    while !Task.isCancelled {
                        for frame in try await receive(socket) {
                            switch frame["_tag"]?.string {
                            case "Ping":try await socket.send(.string("{\"_tag\":\"Pong\"}"))
                            case "Chunk":
                                for value in frame["values"]?.array ?? [] {continuation.yield(value)}
                                try await socket.send(.string("{\"_tag\":\"Ack\",\"requestId\":\"1\"}"))
                            case "Exit":
                                if frame["exit"]?["_tag"]?.string=="Failure" {throw SourceFailure.message(errorMessage(frame))}
                                continuation.finish();return
                            case "Defect":throw SourceFailure.message(errorMessage(frame))
                            default:break
                            }
                        }
                    }
                    continuation.finish()
                } catch {continuation.finish(throwing:error)}
            }
            continuation.onTermination={_ in task.cancel();socket.cancel(with:.goingAway,reason:nil)}
        }
    }
    static func errorMessage(_ value:JSONValue)->String {
        if let message=value["message"]?.string {return String(message.prefix(800))}
        switch value {
        case .object(let values):
            for key in ["error","cause","defect","exit"] {if let nested=values[key] {let text=errorMessage(nested);if text != fallback {return text}}}
        case .array(let values):for nested in values {let text=errorMessage(nested);if text != fallback {return text}}
        default:break
        }
        return fallback
    }
    private static let fallback="T3 could not complete this action. Your draft is preserved."
}
