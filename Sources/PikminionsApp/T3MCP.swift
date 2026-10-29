// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Foundation

enum JSONValue:Codable,Equatable,Sendable {
    case null,bool(Bool),number(Double),string(String),array([JSONValue]),object([String:JSONValue])
    init(from decoder:Decoder) throws {
        let value=try decoder.singleValueContainer()
        if value.decodeNil() {self = .null}
        else if let v=try? value.decode(Bool.self) {self = .bool(v)}
        else if let v=try? value.decode(Double.self) {self = .number(v)}
        else if let v=try? value.decode(String.self) {self = .string(v)}
        else if let v=try? value.decode([JSONValue].self) {self = .array(v)}
        else {self = .object(try value.decode([String:JSONValue].self))}
    }
    func encode(to encoder:Encoder) throws {
        var value=encoder.singleValueContainer()
        switch self {
        case .null:try value.encodeNil()
        case .bool(let v):try value.encode(v)
        case .number(let v):try value.encode(v)
        case .string(let v):try value.encode(v)
        case .array(let v):try value.encode(v)
        case .object(let v):try value.encode(v)
        }
    }
    subscript(_ key:String)->JSONValue? {if case .object(let value)=self {value[key]} else {nil}}
    var string:String? {if case .string(let value)=self {value} else {nil}}
    var array:[JSONValue]? {if case .array(let value)=self {value} else {nil}}
    var bool:Bool? {if case .bool(let value)=self {value} else {nil}}
    func decoded<T:Decodable>(_ type:T.Type) throws ->T {try JSONDecoder().decode(type,from:JSONEncoder().encode(self))}
}

/// One MCP session per scoped credential. Tool names are chosen by app commands.
/// JSON and SSE carry the same response envelope; no tool output is logged.
actor T3MCPClient {
    private let endpoint:URL
    private let token:String
    private var sessionID:String?
    private var counter=0
    private var connected=false
    private var connecting:Task<Void,Error>?
    init(origin:URL,token:String) {endpoint=origin.appending(path:"mcp");self.token=token}
    func tool(_ name:String,arguments:[String:JSONValue]) async throws ->JSONValue {
        try await connect()
        let result=try await request("tools/call",params:.object(["name":.string(name),"arguments":.object(arguments)]))
        if result["isError"]?.bool==true {
            let text=result["content"]?.array?.compactMap{$0["text"]?.string}.joined(separator:"\n") ?? "T3 could not complete this action."
            if let data=text.data(using:.utf8),let error=try? JSONDecoder().decode(JSONValue.self,from:data),let message=error["message"]?.string {throw SourceFailure.message(String(message.prefix(800)))}
            throw SourceFailure.message(String(text.prefix(800)))
        }
        if let structured=result["structuredContent"] {return structured}
        for block in result["content"]?.array ?? [] {
            if let text=block["text"]?.string,let data=text.data(using:.utf8),let value=try? JSONDecoder().decode(JSONValue.self,from:data) {return value}
        }
        throw SourceFailure.message("T3 returned an unsupported result. Update the connection.")
    }
    private func connect() async throws {
        if connected {return}
        if let connecting {try await connecting.value;return}
        let task=Task {try await self.initialize()}
        connecting=task
        defer {connecting=nil}
        try await task.value
        connected=true
    }
    private func initialize() async throws {
        _=try await request("initialize",params:.object([
            "protocolVersion":.string("2025-06-18"),"capabilities":.object([:]),
            "clientInfo":.object(["name":.string("Pikminions"),"version":.string("1.0")])
        ]))
        _=try await request("notifications/initialized",params:.object([:]),notification:true)
    }
    private func request(_ method:String,params:JSONValue,notification:Bool=false) async throws ->JSONValue {
        counter+=1
        let id=Double(counter)
        var envelope:[String:JSONValue]=["jsonrpc":.string("2.0"),"method":.string(method),"params":params]
        if !notification {envelope["id"] = .number(id)}
        var request=URLRequest(url:endpoint);request.httpMethod="POST";request.timeoutInterval=15
        request.setValue("Bearer "+token,forHTTPHeaderField:"Authorization")
        request.setValue("application/json, text/event-stream",forHTTPHeaderField:"Accept")
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        request.setValue("2025-06-18",forHTTPHeaderField:"mcp-protocol-version")
        if let sessionID {request.setValue(sessionID,forHTTPHeaderField:"mcp-session-id")}
        request.httpBody=try JSONEncoder().encode(JSONValue.object(envelope))
        let (data,response)=try await URLSession.shared.data(for:request)
        try Task.checkCancellation()
        guard let http=response as? HTTPURLResponse,(200...299).contains(http.statusCode) else {
            let code=(response as? HTTPURLResponse)?.statusCode ?? 0
            throw SourceFailure.message(code==401 ? "T3 access expired. Reconnect to enable this action.":"T3 could not complete the request (HTTP \(code)). Your draft is preserved.")
        }
        if let next=http.value(forHTTPHeaderField:"mcp-session-id") {sessionID=next}
        guard data.count<10_485_760 else {throw SourceFailure.message("T3 returned too much data for this bubble.")}
        if notification && data.isEmpty {return .null}
        let value=try Self.parse(data,contentType:http.value(forHTTPHeaderField:"Content-Type") ?? "",id:id)
        if let message=value["error"]?["message"]?.string {throw SourceFailure.message(String(message.prefix(800)))}
        guard let result=value["result"] else {throw SourceFailure.message("T3 returned an incomplete response. Your draft is preserved.")}
        return result
    }
    static func parse(_ data:Data,contentType:String,id:Double) throws ->JSONValue {
        if !contentType.contains("text/event-stream") {return try JSONDecoder().decode(JSONValue.self,from:data)}
        let text=String(decoding:data,as:UTF8.self).replacingOccurrences(of:"\r\n",with:"\n")
        for event in text.components(separatedBy:"\n\n") {
            let payload=event.components(separatedBy:"\n").filter{$0.hasPrefix("data:")}.map{String($0.dropFirst(5)).trimmingCharacters(in:.whitespaces)}.joined(separator:"\n")
            if let bytes=payload.data(using:.utf8),let value=try? JSONDecoder().decode(JSONValue.self,from:bytes),value["id"] == .number(id) {return value}
        }
        throw SourceFailure.message("T3 closed the response before acknowledging it. Your draft is preserved.")
    }
}

struct AgentQuestion:Codable,Identifiable,Equatable,Sendable {
    var id:String
    var header:String
    var question:String
    var options:[Option]
    var multiSelect:Bool?
    var allowCustomAnswer:Bool?
    var initialAnswer:String?
    var required:Bool?
    struct Option:Codable,Equatable,Sendable {var label:String;var description:String;var value:String?}
}
struct AgentQuestionDocument:Codable,Equatable,Sendable {var requestId:String;var questions:[AgentQuestion]}
struct ConversationLine:Identifiable,Equatable,Sendable {var id:String;var role:String;var text:String;var streaming:Bool=false;var containsAccept:Bool?=nil}
