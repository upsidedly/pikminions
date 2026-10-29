// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Foundation

/// A deliberately labeled, entirely in-memory source for unattended native tests.
/// It has no file, credential, HTTP, subprocess, or external-navigation capability.
actor FixtureAgentSource {
    private var agents:[AgentRecord]
    private var messages:[String:[ConversationLine]]=[:]
    private var requests:[String:AgentQuestionDocument]=[:]
    private var subscribers:[String:[UUID:AsyncThrowingStream<JSONValue,Error>.Continuation]]=[:]
    private var replies:[String:Task<Void,Never>]=[:]
    private var commands:Set<String>=[]
    private var sequence=1.0
    init() {
        agents=[
            AgentRecord(id:"t3:fixture-question",source:"Fixture",threadID:"fixture-question",runID:"fixture-run-question",title:"Fixture · Question",project:"Fixture",model:"Sample data",state:.waitingInput,detail:"Sample question, no live thread.",updated:.now,openURL:nil,pendingRequestID:"fixture-request"),
            AgentRecord(id:"t3:fixture-worker",source:"Fixture",threadID:"fixture-worker",runID:"fixture-run-worker",title:"Fixture · Worker",project:"Fixture",model:"Sample data",state:.working,detail:"Sample output, no live thread.",updated:.now,openURL:nil),
            AgentRecord(id:"t3:fixture-partner",source:"Fixture",threadID:"fixture-partner",runID:"fixture-run-partner",title:"Fixture · Collaborator",project:"Fixture",model:"Sample data",state:.working,detail:"Sample collaboration partner.",updated:.now,openURL:nil),
            AgentRecord(id:"t3:fixture-idle",source:"Fixture",threadID:"fixture-idle",runID:"",title:"Fixture · Ready",project:"Fixture",model:"Sample data",state:.idle,detail:"Sample idle conversation.",updated:.now,openURL:nil)
        ]
        for agent in agents {messages[agent.threadID]=[ConversationLine(id:"sample-"+agent.threadID,role:"assistant",text:"Fixture output. These are sample conversations; no live account or credential is connected.")]}
        requests["fixture-question"]=AgentQuestionDocument(requestId:"fixture-request",questions:[AgentQuestion(id:"fixture-choice",header:"Sample choice",question:"Which sample approach should this Pikmin use?",options:[.init(label:"Keep it small",description:"Use the compact sample layout."),.init(label:"Show more detail",description:"Use the expanded sample layout.")],allowCustomAnswer:true)])
    }
    func snapshot()->[AgentRecord] {
        agents.map {agent in
            var result=agent
            if let last=messages[agent.threadID]?.last,last.role=="assistant" {result.output=last.text;result.outputMessageID=last.id;result.outputStreaming=last.streaming}
            return result
        }
    }
    func history(_ threadID:String)->[ConversationLine] {messages[threadID] ?? []}
    func question(_ threadID:String)->AgentQuestionDocument? {requests[threadID]}
    func projection(_ threadID:String)->JSONValue {
        let agent=agents.first{$0.threadID==threadID}
        return .object(["projection":.object([
            "messages":.array((messages[threadID] ?? []).map(Self.messageValue)),
            "thread":.object(["projectId":.string("fixture-project"),"modelSelection":.object(["model":.string("fixture")]),"runtimeMode":.string("approval-required"),"interactionMode":.string("default"),"title":.string(agent?.title ?? "Fixture")])
        ])])
    }
    func stream(_ threadID:String)->AsyncThrowingStream<JSONValue,Error> {
        let id=UUID(),snapshot=projection(threadID)
        return AsyncThrowingStream(bufferingPolicy:.bufferingNewest(64)) { continuation in
            subscribers[threadID,default:[:]][id]=continuation
            continuation.yield(.object(["kind":.string("snapshot"),"snapshotSequence":.number(sequence),"projection":snapshot["projection"] ?? .object([:])]))
            continuation.onTermination={ [weak self] _ in Task {await self?.removeSubscriber(id,threadID:threadID)}}
        }
    }
    private func removeSubscriber(_ id:UUID,threadID:String) {subscribers[threadID]?.removeValue(forKey:id)}
    private static func messageValue(_ message:ConversationLine)->JSONValue {
        .object(["id":.string(message.id),"role":.string(message.role),"text":.string(message.text),"streaming":.bool(message.streaming)])
    }
    private func emit(_ threadID:String,type:String,payload:JSONValue) {
        sequence+=1
        let event=JSONValue.object(["kind":.string("event"),"sequence":.number(sequence),"event":.object(["type":.string(type),"payload":payload])])
        for continuation in subscribers[threadID]?.values ?? Dictionary<UUID,AsyncThrowingStream<JSONValue,Error>.Continuation>().values {continuation.yield(event)}
    }
    private func message(_ threadID:String,_ line:ConversationLine) {
        if let index=messages[threadID]?.firstIndex(where:{$0.id==line.id}) {messages[threadID]?[index]=line}
        else {messages[threadID,default:[]].append(line)}
        if line.role=="assistant",line.streaming {
            emit(threadID,type:"turn-item.updated",payload:.object(["id":.string("item:"+line.id),"messageId":.string(line.id),"threadId":.string(threadID),"type":.string("assistant_message"),"text":.string(line.text),"streaming":.bool(true)]))
        } else {emit(threadID,type:"message.updated",payload:Self.messageValue(line))}
    }
    func dispatch(_ command:JSONValue) throws {
        guard let id=command["commandId"]?.string,let type=command["type"]?.string else {throw SourceFailure.message("Fixture command is incomplete.")}
        if commands.contains(id) {return}
        let thread=command["threadId"]?.string ?? command["sourceThreadId"]?.string ?? ""
        switch type {
        case "message.dispatch":
            guard let text=command["text"]?.string,let index=agents.firstIndex(where:{$0.threadID==thread}) else {throw SourceFailure.message("Fixture thread was not found.")}
            message(thread,ConversationLine(id:command["messageId"]?.string ?? id,role:"user",text:text))
            agents[index].state = .working;agents[index].runID=id
            scheduleReply(thread,commandID:id,text:text)
        case "runtime-request.respond":
            guard let document=requests[thread],document.requestId==command["requestId"]?.string,
                  case .object(let answers)=command["answers"],answers.values.contains(where:{!($0.array ?? []).isEmpty}) else {throw SourceFailure.message("This fixture question is no longer pending or has no answer.")}
            requests.removeValue(forKey:thread)
            if let index=agents.firstIndex(where:{$0.threadID==thread}) {agents[index].pendingRequestID=nil;agents[index].state = .working}
            emit(thread,type:"runtime-request.updated",payload:.object(["id":.string(document.requestId),"kind":.string("user_input"),"status":.string("resolved")]))
            message(thread,ConversationLine(id:"answer-"+id,role:"user",text:"Fixture answer submitted."))
            scheduleReply(thread,commandID:id,text:"Your sample answer was received.")
        case "thread.stop":
            replies.removeValue(forKey:thread)?.cancel()
            if let index=agents.firstIndex(where:{$0.threadID==thread}) {agents[index].state = .interrupted}
        case "thread.fork","thread.create":
            let target=command["targetThreadId"]?.string ?? command["threadId"]?.string ?? ""
            guard !target.isEmpty else {throw SourceFailure.message("Fixture target is missing.")}
            agents.append(AgentRecord(id:"t3:"+target,source:"Fixture",threadID:target,runID:"",title:command["title"]?.string ?? "Fixture · New",project:"Fixture",model:"Sample data",state:.idle,detail:"Sample conversation.",updated:.now,openURL:nil))
            messages[target]=type=="thread.fork" ? messages[thread]:[]
        default:throw SourceFailure.message("This fixture command is unsupported.")
        }
        commands.insert(id)
    }
    private func scheduleReply(_ threadID:String,commandID:String,text:String) {
        replies.removeValue(forKey:threadID)?.cancel()
        replies[threadID]=Task { [weak self] in
            let output="ACCEPT — Fixture turn finished.\n\n"+String(text.prefix(2400))
            for index in 1...40 {
                do {try await Task.sleep(for:.milliseconds(45));try Task.checkCancellation()} catch{return}
                await self?.replyFrame(threadID,id:"fixture-reply-"+commandID,text:String(output.prefix(output.count*index/40)),final:index==40)
            }
        }
    }
    private func replyFrame(_ threadID:String,id:String,text:String,final:Bool) {
        message(threadID,ConversationLine(id:id,role:"assistant",text:text,streaming:!final))
        if final,let index=agents.firstIndex(where:{$0.threadID==threadID}) {agents[index].state = .finished;agents[index].updated = .now;replies.removeValue(forKey:threadID)}
    }
    func shutdown() {
        for task in replies.values {task.cancel()};replies=[:]
        for group in subscribers.values {for continuation in group.values {continuation.finish()}};subscribers=[:]
    }
}
