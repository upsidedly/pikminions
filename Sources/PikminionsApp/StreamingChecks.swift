// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Foundation

/// Actual subscription-to-conversation path, with synthetic server frames.
/// No model.start(), native windows, credentials or live requests.
@MainActor func runStreamingChecks() throws {
    func expect(_ value:Bool,_ message:String) throws {if !value {throw SourceFailure.message(message)}}
    let model=SquadModel()
    let agent=AgentRecord(id:"t3:stream-check",source:"Fixture",threadID:"stream-check",runID:"sample-run",title:"Sample streaming",project:"Fixture",model:"Sample",state:.working,detail:"",updated:.now,openURL:nil)
    model.records=[agent];model.vocal=[]
    let coordinator=ConversationCoordinator(model:model,observesSources:false)
    model.conversationCoordinator=coordinator
    let state=coordinator.state(for:agent);state.vocalPresentation=true
    func frame(_ sequence:Double,_ type:String,_ fields:[String:JSONValue])->JSONValue {
        .object(["kind":.string("event"),"sequence":.number(sequence),"event":.object(["type":.string(type),"payload":.object(fields)])])
    }
    var partial:[String:JSONValue]=["id":.string("turn-item-1"),"threadId":.string(agent.threadID),"type":.string("assistant_message"),"messageId":.string("message-1"),"text":.string("I’m keeping **P**"),"streaming":.bool(true)]
    coordinator.applyStreamItem(frame(1,"turn-item.updated",partial),to:state)
    try expect(state.lines.last?.text=="I’m keeping **P**" && state.lines.last?.streaming==true,"Codex partial text must reach the talk state before message completion.")
    model.vocal=[agent.id];coordinator.close(state.id)
    coordinator.receiveOutput(agent,line:ConversationLine(id:"message-1",role:"assistant",text:"I’m keeping **P** as the buy button,",streaming:true),historical:false)
    try expect(state.lines.last?.text.hasSuffix("buy button,")==true && !state.vocalPresentation,"Repeated same-message updates must extend the speech state while a dismissed panel stays closed.")
    coordinator.receiveOutput(agent,line:ConversationLine(id:"message-1",role:"assistant",text:"I’m keeping **P**",streaming:true),historical:false)
    try expect(state.lines.last?.text.hasSuffix("buy button,")==true,"A stale shorter poll must not roll speech text back.")
    model.vocal=[]
    partial["text"] = .string("I’m keeping **P** and adding touch controls.")
    coordinator.applyStreamItem(frame(2,"turn-item.updated",partial),to:state)
    try expect(state.lines.count==1 && state.lines.last?.text.contains("touch controls")==true,"The same talk message must grow in place on the next partial frame.")
    partial["text"] = .string("stale partial")
    coordinator.applyStreamItem(frame(1,"turn-item.updated",partial),to:state)
    try expect(state.lines.last?.text.contains("touch controls")==true,"Late frames cannot replace newer text.")
    coordinator.applyStreamItem(frame(3,"message.updated",["id":.string("message-1"),"role":.string("assistant"),"text":.string("I’m keeping **P** and adding touch controls. Done."),"streaming":.bool(false)]),to:state)
    try expect(state.lines.count==1 && state.lines.last?.streaming==false && state.lines.last?.text.hasSuffix("Done.")==true,"Final message must finish the same speech identity and enable Reply.")
    partial["type"] = .string("reasoning");partial["text"] = .string("Sample private reasoning")
    coordinator.applyStreamItem(frame(4,"turn-item.updated",partial),to:state)
    try expect(state.lines.count==1 && !state.lines.contains{$0.text.contains("private reasoning")},"Reasoning must not be treated as speech.")
    partial["type"] = .string("assistant_message");partial["threadId"] = .string("another-thread")
    coordinator.applyStreamItem(frame(5,"turn-item.updated",partial),to:state)
    try expect(state.lines.last?.text.hasSuffix("Done.")==true,"A frame from a different thread must not enter this talk box.")
    partial["threadId"] = .string(agent.threadID);partial["text"] = .string(String(repeating:"Earlier 🌸 text. ",count:3000)+"Newest streamed words.");partial["streaming"] = .bool(true)
    coordinator.applyStreamItem(frame(6,"turn-item.updated",partial),to:state)
    try expect(state.lines.last?.text.hasSuffix("Newest streamed words.")==true && (state.lines.last?.text.utf8.count ?? 24001)<=24000,"Long talk output must keep streaming the newest bounded tail, rather than freezing at the prefix limit.")
    let accepted=AgentSources.eventLine(.object(["type":.string("message.updated"),"payload":.object(["id":.string("long-complete"),"role":.string("assistant"),"text":.string("ACCEPT "+String(repeating:"Earlier output. ",count:3000)+"Last words."),"streaming":.bool(false)])]),threadID:agent.threadID)
    try expect(accepted?.containsAccept==true && accepted?.text.hasSuffix("Last words.")==true,"The bounded display tail must preserve the whole message's ACCEPT completion signal.")
    print("PASS: actual subscription application renders successive Codex partial frames, keeps message identity through completion, rejects old frames, and excludes reasoning/other threads.")
}
