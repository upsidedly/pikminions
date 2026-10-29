// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Foundation
import SwiftUI
import AppKit

@MainActor func runPikminChecks() throws {
    func expect(_ condition:Bool,_ label:String) throws {
        if !condition {throw SourceFailure.message("Check failed: "+label)}
    }
    func thread(_ status:String,_ extra:[String:Any]=[:]) throws -> T3Shell.Thread {
        var payload:[String:Any]=["id":"thread","projectId":"project","title":"Fixture","status":status,"updatedAt":"2026-10-26T12:00:00Z"]
        for (key,value) in extra {payload[key]=value}
        return try JSONDecoder().decode(T3Shell.Thread.self,from:JSONSerialization.data(withJSONObject:payload))
    }
    try expect(mappedT3State(try thread("waiting")) == .working,"generic waiting is not an approval")
    try expect(mappedT3State(try thread("running",["pendingRuntimeRequest":["id":"request","kind":"user_input","blocking":false]])) == .working,"nonblocking input")
    try expect(mappedT3State(try thread("running",["pendingRuntimeRequest":["id":"request","kind":"user_input"]])) == .waitingInput,"blocking input")
    try expect(mappedT3State(try thread("running",["pendingRuntimeRequest":["id":"request","kind":"permission"]])) == .waitingApproval,"approval request")
    try expect(mappedT3State(try thread("completed",["pendingBackgroundTasks":[["kind":"subagent"]]])) == .working,"background child holds completion")
    try expect(mappedT3State(try thread("completed")) == .finished,"completed turn")
    try expect(mappedT3State(try thread("interrupted")) == .interrupted,"interruption isn't success")
    try expect(mappedT3State(try thread("failed")) == .failed,"failure")
    try expect(PikminSpecies.assigned(to:"stable")==PikminSpecies.assigned(to:"stable"),"stable species")
    try expect(PikminSpecies.allCases.count==9,"all nine distinct species")
    try expect(IslandDestination.select(hostAvailable:true,hasAccess:false) == .embedded,"an unpaired host cannot block docking")
    try expect(IslandDestination.select(hostAvailable:false,hasAccess:true) == .embedded,"an unavailable host uses the embedded island")
    try expect(IslandDestination.select(hostAvailable:true,hasAccess:true) == .shared,"a paired available host owns shared presentation")
    var look=PikminLook(name:"Tangerine",species:.glow)
    look.bodyHex="EE9048";look.stemHex="9673C6";look.flowerHex="F7B3D4";look.eyeHex="3761BE";look.leafHex="76BFA9";look.stemLength=1.4;look.stemCurve=0.5;look.growth = .flower
    try expect(look.isValid && (try JSONDecoder().decode(PikminLook.self,from:JSONEncoder().encode(look))) == look,"custom look values and stable identity survive persistence")
    let originalAsset=look.assetKey
    look.name="New label"
    try expect(look.assetKey==originalAsset,"renaming a look does not invalidate rendered assets")
    look.eyeHex="3355AA"
    try expect(look.assetKey != originalAsset,"visual customizations get distinct cached assets")
    for length in [0.65,1.5] {
        for species in PikminSpecies.allCases {
            look.species=species;look.stemLength=length
            try expect(look.top.offset>10 && look.top.canvasHeight<200 && look.top.stemHex==look.stemHex,"custom stems retain bounded joined profiles")
        }
    }
    var invalid=look;invalid.bodyHex="not a color"
    try expect(!invalid.isValid,"malformed saved colors are rejected")
    invalid=look;invalid.stemLength=2
    try expect(!invalid.isValid,"out-of-range custom stems are rejected")
    let near=PikminGaze.toward(CGPoint(x:20,y:30),from:.zero,radius:150)
    let far=PikminGaze.toward(CGPoint(x:250,y:0),from:.zero,radius:150)
    try expect(near.x>0 && near.y<0 && abs(near.x)<=1 && abs(near.y)<=1,"nearby pointer gets bounded eye direction in screen coordinates")
    try expect(far.x==0 && far.y==0,"distant pointer releases the Pikmin's attention")
    let anchor=CGRect(x:100,y:100,width:86,height:116)
    for screen in [CGRect(x:0,y:0,width:1024,height:640),CGRect(x:-1440,y:70,width:1440,height:800)] {
        for size in PikminSize.allCases {
          for x in [screen.minX,screen.midX-size.panelSize.width/2,screen.maxX-size.panelSize.width] {
            for y in [screen.minY,screen.midY-size.panelSize.height/2,screen.maxY-size.panelSize.height] {
                let head=CGRect(origin:CGPoint(x:x,y:y),size:size.panelSize)
                let bubble=ConversationPlacement.frame(anchor:head,screen:screen,preferred:CGSize(width:360,height:460))
                try expect(screen.contains(bubble) && !bubble.intersects(head.insetBy(dx:-6,dy:-6)),"bubble clears the full moving head at screen edges and center positions")
                let resized=size.resizedFrame(from:head.offsetBy(dx:screen.width,dy:screen.height),within:screen)
                try expect(screen.contains(resized),"resizing to every head size clamps it to its current display")
            }
          }
        }
    }
    try expect(PikminSize.medium.panelSize==CGSize(width:86,height:116) && PikminSize.medium.artSize==CGSize(width:74,height:89),"Medium preserves the current panel and artwork dimensions")
    let center=PikminSize.artCenter(in:anchor)
    for size in PikminSize.allCases {
        let expanded=size.resizedFrame(from:anchor,within:CGRect(x:-1000,y:-1000,width:3000,height:3000))
        let next=PikminSize.artCenter(in:expanded)
        try expect(abs(next.x-center.x)<0.001 && abs(next.y-center.y)<0.001,"head size changes preserve the visible head center")
        try expect((try JSONDecoder().decode(PikminSize.self,from:JSONEncoder().encode(size)))==size,"saved sizes preserve their stable identity")
    }
    try expect(PikminGaze.towardBubble(anchor.offsetBy(dx:0,dy:300),from:anchor).y == -1,"eyes look up toward an upper bubble")
    try expect(PikminGaze.towardBubble(anchor.offsetBy(dx:0,dy:-300),from:anchor).y == 1,"eyes look down toward a lower bubble")
    for kind in PikminIdleKind.allCases {
        try expect(PikminIdlePose.make(kind,progress:0) == .rest && PikminIdlePose.make(kind,progress:1) == .rest,"idle gestures join the resting pose at both ends")
        for step in 0...120 {
            let pose=PikminIdlePose.make(kind,progress:Double(step)/120)
            try expect((0.05...1).contains(pose.blink) && abs(pose.tilt)<=3 && abs(pose.leaf)<=6 && (0.95...1.05).contains(pose.scaleX) && (0.95...1.05).contains(pose.scaleY),"idle motion stays bounded and eyes stay inside their silhouettes")
        }
    }
    struct SeededRandom:RandomNumberGenerator {var state:UInt64=42;mutating func next()->UInt64 {state=state &* 6364136223846793005 &+ 1442695040888963407;return state}}
    var random=SeededRandom(),director=PikminIdleDirector()
    let start=Date(timeIntervalSince1970:1000)
    _=director.advance(at:start,eligible:["head"],using:&random)
    try expect(director.active.isEmpty,"idle gestures wait through a quiet gap")
    _=director.advance(at:start.addingTimeInterval(30),eligible:["head"],using:&random)
    let firstIdle=director.active["head"]?.kind
    try expect(firstIdle != nil,"an eligible head receives a randomly selected idle")
    _=director.advance(at:start.addingTimeInterval(60),eligible:["head"],using:&random)
    try expect(director.active["head"]?.kind != firstIdle,"successive idles vary")
    director.suspend("head")
    _=director.advance(at:start.addingTimeInterval(60.1),eligible:["head"],using:&random)
    try expect(director.active.isEmpty,"calling a head to attention cancels its idle and resets the quiet gap")
    _=director.advance(at:start.addingTimeInterval(90),eligible:[],using:&random)
    try expect(director.active.isEmpty,"hidden or ineligible heads never idle")
    var speech=VocalDeliveryTracker()
    try expect(!speech.receive(agentID:"one",eventID:"message:history",historical:true),"finished history does not speak on launch")
    try expect(!speech.receive(agentID:"one",eventID:"message:history",historical:false),"history is not replayed by a later poll")
    try expect(speech.receive(agentID:"one",eventID:"message:live",historical:false),"new incoming output speaks once")
    try expect(!speech.receive(agentID:"one",eventID:"message:live",historical:false),"dismissed speech stays closed through chunks of the same message")
    _=speech.receive(agentID:"one",eventID:"message:late-history",historical:true)
    try expect(!speech.receive(agentID:"one",eventID:"message:live",historical:false),"late history cannot replay speech")
    try expect(speech.receive(agentID:"one",eventID:"question:request",historical:false),"a new question can speak after output was dismissed")
    try expect(!speech.receive(agentID:"one",eventID:"question:request",historical:false),"question loading and metadata cannot speak twice")
    try expect(VocalSpeechTiming.readingInterval("A short line")==10 && VocalSpeechTiming.readingInterval(String(repeating:"word ",count:300))==30,"speech reading interval is bounded")
    let head=CGRect(x:100,y:100,width:40,height:40)
    try expect(SpeechTail.aimed(from:CGRect(x:0,y:160,width:240,height:100),to:head).edge == .bottom,"speech above a head points down")
    try expect(SpeechTail.aimed(from:CGRect(x:0,y:0,width:240,height:80),to:head).edge == .top,"speech below a head points up")
    try expect(SpeechTail.aimed(from:CGRect(x:160,y:90,width:240,height:100),to:head).edge == .left,"speech beside a head points toward it")
    try expect(agentDate("2026-10-26T12:00:00.123Z") != .distantPast,"fractional timestamps")
    var pendulum=HeadPendulum()
    for _ in 0..<30 {_ = pendulum.step(cursorVelocity:1200,anchorX:0.5,dt:1/60)}
    try expect(pendulum.angle>0 && pendulum.angle<0.35,"bounded cursor-driven swing")
    for _ in 0..<240 {_ = pendulum.step(cursorVelocity:0,anchorX:0.5,dt:1/60)}
    try expect(abs(pendulum.angle)<0.001,"held head settles under gravity")
    let agent=AgentRecord(id:"fixture",source:"Fixture",threadID:"fixture",runID:"run",title:"Fixture",project:"Fixture",model:"Fixture",state:.waitingInput,detail:"",updated:.distantPast,openURL:nil)
    let state=ConversationState(agent:agent)
    var dormant=agent;dormant.id="dormant";dormant.projectID="other-project";dormant.state = .finished
    var active=agent;active.projectID="active-project"
    var sibling=dormant;sibling.projectID=active.projectID
    try expect(active.isCompactEligible && !sibling.isCompactEligible && !dormant.isCompactEligible,"a finished sibling cannot inherit a running project's compact slot")
    active.stale=true
    try expect(!active.isCompactEligible,"disconnected work never occupies a compact slot")
    for value in AgentState.allCases {
        var sample=agent;sample.state=value
        try expect(sample.isCompactEligible == value.isActive,"only working/starting/queued or waiting agents qualify for compact slots")
    }
    var pending=dormant;pending.pendingRequestID="still-open";pending.pendingRequestKind="user_input"
    try expect(pending.isCompactEligible,"an unresolved question stays visible even after the provider finishes a turn")
    var older=agent;older.id="older";older.state = .working;older.updated=Date(timeIntervalSince1970:10)
    var newer=older;newer.id="newer";newer.runID="newer-run";newer.updated=Date(timeIntervalSince1970:20)
    var order=ActiveAgentOrder();order.reconcile([older,newer,sibling])
    try expect(order.rank(newer.id)>order.rank(older.id) && order.rank(sibling.id)==0,"newer working runs lead old and completed heads")
    older.updated=Date(timeIntervalSince1970:30);order.reconcile([older,newer,sibling])
    try expect(order.rank(newer.id)>order.rank(older.id),"streaming timestamps do not shuffle existing heads")
    newer.state = .finished;order.reconcile([older,newer,sibling])
    try expect(order.rank(newer.id)==0 && order.priorities(for:[older,newer])[newer.id]==nil,"completion immediately releases compact priority")
    newer.state = .working;newer.runID="restarted-run";order.reconcile([older,newer,sibling])
    try expect(order.rank(newer.id)>order.rank(older.id),"a restarted agent regains priority as a new working run")
    let roster=SquadModel();roster.hidden=[];roster.pinned=[sibling.id];roster.docked=[sibling.id];roster.maxHeads=1
    roster.records=[older,newer,sibling]
    try expect(roster.visibleHeads.map(\.id)==[older.id],"first observation uses active timestamps before pinned/completed heads")
    newer.runID="newest-run";roster.records=[older,newer,sibling]
    try expect(roster.visibleHeads.map(\.id)==[newer.id],"a new running agent wins the actual head cap over an older pinned/docked conversation")
    roster.headSizes[older.id]="xl"
    try expect(roster.size(for:older) == .xl && roster.size(for:newer) == .medium,"head size overrides belong to individual agents and default to Medium")
    roster.headSizes[older.id]="invalid"
    try expect(roster.size(for:older) == .medium,"unknown saved size values recover to Medium")
    let first=state.command(for:"same submission"),retry=state.command(for:"same submission"),changed=state.command(for:"edited submission")
    try expect(first.commandID==retry.commandID && first.messageID==retry.messageID,"uncertain submissions retry with the same IDs")
    try expect(first.commandID != changed.commandID,"edited submissions get a new ID")
    state.question=AgentQuestionDocument(requestId:"exact-request",questions:[AgentQuestion(id:"one",header:"Choice",question:"Which?",options:[],required:true),AgentQuestion(id:"optional",header:"Optional",question:"Anything else?",options:[],required:false)])
    try expect(!state.answersReady,"required answers cannot be empty")
    state.customAnswers["one"]="  sample answer  "
    try expect(state.answersReady && state.answerPayload["one"]==["sample answer"],"trim answers and allow optional questions")
    let answer=AgentCommands.answer(threadID:"fixture",requestID:"exact-request",answers:state.answerPayload,commandID:"answer")
    try expect(answer["requestId"]?.string=="exact-request" && answer["answers"]?["one"] == .array([.string("sample answer")]),"answer exact request with structured arrays")
    let textAnswer=AgentCommands.answer(threadID:"fixture",requestID:"exact-request",answers:state.answerPayload,commandID:"answer",asText:true)
    try expect(textAnswer["answers"]?["one"] == .string("sample answer"),"message-backed async questions use text answers")
    var nonblocking=agent;nonblocking.state = .working;nonblocking.pendingRequestKind="user_input";nonblocking.pendingRequestID="async-request"
    try expect(nonblocking.needsUserInput && nonblocking.attention == .needsAttention && nonblocking.mood == .question && nonblocking.state == .working,"async questions raise attention while preserving active work")
    let forkProjection:JSONValue = .object(["messages":.array([]),"visibleTurnItems":.array([.object(["visibility":.string("inherited"),"item":.object(["type":.string("assistant_message"),"messageId":.string("inherited-message"),"text":.string("Sample inherited output"),"streaming":.bool(false)])])])])
    try expect(AgentSources.projectionLines(forkProjection).first?.text=="Sample inherited output","fork output comes from visible inherited items")
    let dedupedProjection:JSONValue = .object(["messages":.array([.object(["id":.string("local-message"),"role":.string("assistant"),"text":.string("Sample local output")])]),"visibleTurnItems":.array([.object(["item":.object(["type":.string("assistant_message"),"messageId":.string("local-message"),"text":.string(""),"textOmitted":.bool(true)])])])])
    try expect(AgentSources.projectionLines(dedupedProjection).first?.text=="Sample local output","deduplicated row text resolves to local message")
    let queued=AgentCommands.message(threadID:"fixture",text:"hello",commandID:"same",messageID:"message",activeRunID:"run",delivery:.nextTurn)
    let steer=AgentCommands.message(threadID:"fixture",text:"hello",commandID:"same",messageID:"message",activeRunID:"run",delivery:.steer)
    let idle=AgentCommands.message(threadID:"fixture",text:"hello",commandID:"same",messageID:"message",activeRunID:nil,delivery:.nextTurn)
    try expect(queued["dispatchMode"]?["type"]?.string=="queue_after_active" && steer["dispatchMode"]?["targetRunId"]?.string=="run" && idle["dispatchMode"]?["type"]?.string=="start_immediately","queue, steer and idle have distinct delivery semantics")
    let sse="event: message\r\ndata: {\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"ignore\":true}}\r\n\r\nevent: message\r\ndata: {\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"ok\":true}}\r\n\r\n"
    let parsed=try T3MCPClient.parse(Data(sse.utf8),contentType:"text/event-stream",id:2)
    try expect(parsed["result"]?["ok"]?.bool==true,"SSE matches response ID and CRLF boundaries")
    do {_=try T3MCPClient.parse(Data(sse.utf8),contentType:"text/event-stream",id:3);throw SourceFailure.message("Check failed: unmatched SSE acknowledged")} catch let error as SourceFailure {try expect(!error.localizedDescription.hasPrefix("Check failed:"),"incomplete response preserves failure")}
    var accepts=AcceptTracker()
    try expect(!accepts.observe(agentID:"one",messageID:"old",text:"ACCEPT",historical:true),"history never celebrates")
    try expect(!accepts.observe(agentID:"one",messageID:"old",text:"ACCEPT",historical:false),"history stays deduplicated")
    try expect(!accepts.observe(agentID:"one",messageID:"new",text:"ACCEPT",streaming:true,historical:false),"streaming marker waits for message completion")
    try expect(accepts.observe(agentID:"one",messageID:"new",text:"ACCEPT",historical:false),"new completed ACCEPT celebrates")
    try expect(!accepts.observe(agentID:"one",messageID:"new",text:"ACCEPT",historical:false),"poll and stream cannot double celebrate")
    _=accepts.observe(agentID:"one",messageID:"late-history",text:"ACCEPT",historical:true)
    try expect(accepts.latest["one"]=="new","late history cannot overwrite a live success marker")
    try expect(!accepts.observe(agentID:"one",messageID:"new",text:"ACCEPT",historical:false),"late history cannot replay a newer live celebration")
    for index in 0..<1200 {_=accepts.observe(agentID:"agent-\(index)",messageID:"accepted",text:"ACCEPT",historical:false)}
    try expect(!accepts.observe(agentID:"one",messageID:"new",text:"ACCEPT",historical:false),"large squads do not replay evicted markers")
    try expect(!accepts.observe(agentID:"one",messageID:"next",text:"accept",historical:false),"literal uppercase marker")
    print("PASS: active-only compact eligibility and stable new-run priority; four head sizes/anchors/bubble clearance; state mapping, species/custom looks, gaze/idles, vocal deduplication, pendulum settling, exact answers, commands, MCP SSE and ACCEPT deduplication.")
}
@MainActor func exportPikminArt(to directory:URL) throws {
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    let sheet=VStack(spacing:20) {
        HStack(spacing:14) {
            ForEach(PikminSpecies.allCases) {species in
                VStack(spacing:10) {
                    PikminDrawing(species:species,mood:.calm,growth:.reference,time:0).frame(width:100,height:120)
                    Text(species.name).font(.system(size:12,weight:.medium)).foregroundStyle(Color.black.opacity(0.6))
                }
            }
        }
        HStack(spacing:20) {
            ForEach(PikminGrowth.allCases,id:\.self) {growth in
                PikminDrawing(species:.red,mood:.calm,growth:growth,time:0).frame(width:80,height:96)
            }
        }
    }.padding(36).background(Color(white:0.95))
    let renderer=ImageRenderer(content:sheet);renderer.scale=2
    guard let cg=renderer.cgImage,let png=NSBitmapImageRep(cgImage:cg).representation(using:.png,properties:[:]) else {throw SourceFailure.message("Art sheet rendering failed.")}
    try png.write(to:directory.appending(path:"pikmin-heads.png"))
    try exportCustomLookArt(to:directory)
    let iconRenderer=ImageRenderer(content:PikminionsAppIcon());iconRenderer.scale=1
    guard let image=iconRenderer.cgImage,let data=NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:]) else {throw SourceFailure.message("Icon rendering failed.")}
    try data.write(to:directory.appending(path:"icon-1024.png"))
    print(directory.path)
}

@MainActor private func exportCustomLookArt(to directory:URL) throws {
    let sheet=VStack(alignment:.leading,spacing:16) {
        ForEach([PikminGrowth.leaf,.bud,.flower],id:\.self) {growth in
            Text("Custom \(growth.title.lowercased()) · desktop / island").font(.system(size:14,weight:.medium))
            HStack(spacing:14) {
                ForEach(PikminSpecies.allCases) {species in
                    let look=sampleLook(species,growth)
                    HStack(alignment:.bottom,spacing:4) {
                        PikminDrawing(species:species,mood:.calm,growth:.reference,time:0,appearance:look).frame(width:74,height:89)
                        PikminDrawing(species:species,mood:.calm,growth:.reference,time:0,appearance:look).frame(width:28,height:34)
                    }
                }
            }
        }
    }.padding(24).foregroundStyle(.white).background(Color(white:0.13))
    let renderer=ImageRenderer(content:sheet);renderer.scale=2
    guard let cg=renderer.cgImage,let data=NSBitmapImageRep(cgImage:cg).representation(using:.png,properties:[:]) else {throw SourceFailure.message("Custom look rendering failed.")}
    try data.write(to:directory.appending(path:"custom-look-samples.png"))
}
private func sampleLook(_ species:PikminSpecies,_ growth:PikminGrowth)->PikminLook {
    var look=PikminLook(name:"Sample",species:species)
    look.bodyHex="EE9048";look.stemHex="9673C6";look.flowerHex="F7B3D4";look.eyeHex="3761BE";look.leafHex="76BFA9";look.growth=growth
    look.stemLength=growth == .leaf ? 0.65:1.5;look.stemCurve=growth == .bud ? -1:1
    return look
}
