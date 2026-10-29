// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Foundation
import Darwin

/// Process and stream completion are synchronized by a lock. Dedicated reader threads
/// drain both pipes; no cooperative Swift executor blocks on waitUntilExit or pipe reads.
final class LocalProcessJob:@unchecked Sendable {
    private let lock=NSLock()
    private let process=Process()
    private let stdout=Pipe(),stderr=Pipe(),stdin=Pipe()
    private var continuation:CheckedContinuation<Data,Error>?
    private var output=Data(),errors=Data(),lineBuffer=Data()
    private var exitStatus:Int32?
    private var outDone=false,errDone=false,finished=false
    private var timeout:Task<Void,Never>?
    private var rpc=false
    private var rpcResult:Data?
    func run(executable:String,arguments:[String],rpc:Bool=false) async throws -> Data {
        try Task.checkCancellation()
        self.rpc=rpc
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                guard !finished else {lock.unlock();continuation.resume(throwing:CancellationError());return}
                self.continuation=continuation;lock.unlock()
                process.executableURL=URL(fileURLWithPath:executable);process.arguments=arguments
                process.standardOutput=stdout;process.standardError=stderr;process.standardInput=stdin
                process.terminationHandler={ [self] task in
                    lock.lock();exitStatus=task.terminationStatus;lock.unlock();completeIfReady()
                }
                do {
                    try process.run()
                    Thread.detachNewThread { [self] in drain(stdout.fileHandleForReading,isOutput:true) }
                    Thread.detachNewThread { [self] in drain(stderr.fileHandleForReading,isOutput:false) }
                    if rpc {
                        try write(["id":1,"method":"initialize","params":["clientInfo":["name":"pikminions","version":"1.0.0"]]])
                    } else { try? stdin.fileHandleForWriting.close() }
                    timeout=Task { [weak self] in
                        do {try await Task.sleep(for:.seconds(20))} catch {return}
                        self?.cancel()
                    }
                } catch { finish(.failure(error)) }
            }
        } onCancel:{ self.cancel() }
    }
    private func write(_ object:[String:Any]) throws {
        var data=try JSONSerialization.data(withJSONObject:object);data.append(10)
        try stdin.fileHandleForWriting.write(contentsOf:data)
    }
    private func drain(_ handle:FileHandle,isOutput:Bool) {
        do {
            while let data=try handle.read(upToCount:8192),!data.isEmpty {
                lock.lock()
                if isOutput {output.append(data)} else {errors.append(data)}
                let tooLarge=output.count>2_097_152 || errors.count>131_072
                lock.unlock()
                if tooLarge {cancel();break}
                if isOutput && rpc { handleRPC(data) }
            }
        } catch {}
        lock.lock();if isOutput {outDone=true} else {errDone=true};lock.unlock()
        completeIfReady()
    }
    private func handleRPC(_ data:Data) {
        lineBuffer.append(data)
        while let end=lineBuffer.firstIndex(of:10) {
            let line=lineBuffer.prefix(upTo:end);lineBuffer.removeSubrange(...end)
            guard let object=try? JSONSerialization.jsonObject(with:line) as? [String:Any],
                  let id=object["id"] as? Int else {continue}
            if id==1 {
                if object["error"] != nil {cancel();return}
                do {
                    try write(["method":"initialized","params":[:]])
                    try write(["id":2,"method":"thread/list","params":["limit":100,"sortKey":"updated_at","sourceKinds":[],"useStateDbOnly":true]])
                } catch {cancel()}
            } else if id==2 {
                if let result=object["result"],let data=try? JSONSerialization.data(withJSONObject:result) {
                    lock.lock();rpcResult=data;lock.unlock()
                }
                try? stdin.fileHandleForWriting.close()
                if process.isRunning {process.terminate()}
            }
        }
    }
    private func completeIfReady() {
        lock.lock()
        guard outDone,errDone,let status=exitStatus else {lock.unlock();return}
        let result:Result<Data,Error>
        if let rpcResult {result = .success(rpcResult)}
        else if status==0 {result = .success(output)}
        else {result = .failure(SourceFailure.message("The local service command did not complete. Make sure its app is running and try again."))}
        lock.unlock();finish(result)
    }
    private func finish(_ result:Result<Data,Error>) {
        lock.lock();guard !finished else {lock.unlock();return}
        finished=true;let continuation=self.continuation;self.continuation=nil
        lock.unlock();timeout?.cancel();continuation?.resume(with:result)
    }
    func cancel() {
        if process.isRunning {
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline:.now()+0.4) { [self] in
                if process.isRunning {kill(process.processIdentifier,SIGKILL)}
            }
        } else {finish(.failure(CancellationError()))}
    }
}
