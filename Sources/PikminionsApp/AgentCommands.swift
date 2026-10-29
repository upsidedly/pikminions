// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Foundation

enum MessageDelivery:String,CaseIterable,Identifiable {case nextTurn="Next turn",steer="Steer now";var id:String {rawValue}}
enum AgentCommands {
    static func message(threadID:String,text:String,commandID:String,messageID:String,activeRunID:String?,delivery:MessageDelivery)->JSONValue {
        let dispatch:JSONValue
        if let activeRunID,!activeRunID.isEmpty {
            dispatch=delivery == .steer ? .object(["type":.string("steer_active"),"targetRunId":.string(activeRunID)]):.object(["type":.string("queue_after_active")])
        } else {dispatch = .object(["type":.string("start_immediately")])}
        return .object([
            "type":.string("message.dispatch"),"commandId":.string(commandID),"threadId":.string(threadID),
            "createdBy":.string("user"),"creationSource":.string("web"),"messageId":.string(messageID),
            "text":.string(text),"attachments":.array([]),"dispatchMode":dispatch,
            "deliveryIntent":.string(delivery == .steer ? "steer":"auto")
        ])
    }
    static func answer(threadID:String,requestID:String,answers:[String:[String]],commandID:String,asText:Bool=false)->JSONValue {
        .object(["type":.string("runtime-request.respond"),"commandId":.string(commandID),"threadId":.string(threadID),"requestId":.string(requestID),"answers":.object(answers.mapValues{asText ? .string($0.joined(separator:", ")):.array($0.map(JSONValue.string))})])
    }
    static func fork(threadID:String,targetID:String,title:String,commandID:String)->JSONValue {
        .object(["type":.string("thread.fork"),"commandId":.string(commandID),"sourceThreadId":.string(threadID),"targetThreadId":.string(targetID),"sourcePoint":.object(["type":.string("latest_stable")]),"title":.string(title),"createdBy":.string("user"),"creationSource":.string("web")])
    }
    static func stop(threadID:String,commandID:String)->JSONValue {
        .object(["type":.string("thread.stop"),"commandId":.string(commandID),"threadId":.string(threadID),"reason":.string("Stopped from Pikminions")])
    }
    static func collaboration(instruction:String,partner:AgentRecord)->String {
        let link=partner.openURL?.absoluteString ?? "t3-thread://v1/"+partner.threadID
        return """
        Collaborate with the existing T3 thread \(link) on this task:

        \(instruction)

        Read that thread's relevant current context with t3_thread_read. Coordinate with the existing thread using t3_thread_send when needed. Agree on ownership before changing shared files, preserve each other's edits, and report what was actually exchanged and completed. Use the existing thread; keep unrelated private context out of the exchange.
        """
    }
}
