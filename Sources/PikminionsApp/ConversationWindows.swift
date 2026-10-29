// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import AppKit
import SwiftUI

private final class SpeechPanel:NSPanel,NSWindowDelegate {
    var onEscape:(()->Void)?
    var onResize:(()->Void)?
    var preferredSize=CGSize(width:320,height:320)
    var userSized=false
    var resizing=false
    var resizeStart:CGRect?
    override var canBecomeKey:Bool {true}
    override var canBecomeMain:Bool {false}
    override func cancelOperation(_ sender:Any?) {onEscape?()}
    func windowWillStartLiveResize(_ notification:Notification) {resizing=true}
    func windowDidEndLiveResize(_ notification:Notification) {resizing=false;userSized=true;preferredSize=frame.size;onResize?()}
}
@MainActor final class ConversationCoordinator {
    private weak var model:SquadModel?
    private var states:[String:ConversationState]=[:]
    private var panels:[String:SpeechPanel]=[:]
    private var order:[String]=[]
    private var islandID:String?
    private var outsideLocalMonitor:Any?
    private var outsideGlobalMonitor:Any?
    private var deactivationObserver:Any?
    private var vocalDelivery=VocalDeliveryTracker()
    private let observesSources:Bool
    private let speechReadingInterval:(String)->Duration
    init(model:SquadModel,observesSources:Bool=true,speechReadingInterval:@escaping (String)->Duration={.seconds(VocalSpeechTiming.readingInterval($0))}) {
        self.model=model;self.observesSources=observesSources;self.speechReadingInterval=speechReadingInterval
    }
    func readingInterval(for text:String)->Duration {speechReadingInterval(text)}
    func state(for agent:AgentRecord)->ConversationState {
        if let state=states[agent.id] {state.agent=agent;return state}
        let state=ConversationState(agent:agent);states[agent.id]=state;return state
    }
    func show(_ agent:AgentRecord,automatic:Bool=false) {
        guard let model else{return}
        let state=state(for:agent)
        if !automatic {model.setAttending(agent.id,true)}
        if let panel=panels[agent.id] {
            if !automatic {
                state.vocalPresentation=false
                panel.styleMask.insert(.resizable);panel.minSize=CGSize(width:280,height:240)
                if !panel.userSized {panel.preferredSize=bubbleSize(state)}
                follow(agent.id,anchor:model.anchor(for:agent))
                panel.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
            }
            loadQuestion(state);resizeForContent(state);return
        }
        while panels.count>=3 {
            let oldest=order.first {id in
                guard let other=states[id],!other.pinned else{return false}
                return !automatic || (other.vocalPresentation && other.draft.isEmpty && !other.sending && !other.editingName)
            }
            guard let oldest else {if automatic {return};break}
            close(oldest)
        }
        state.vocalPresentation=automatic
        if automatic {state.pinned=false;state.vocalHovered=false;state.vocalReplying = !state.draft.isEmpty}
        let size=bubbleSize(state)
        let style:NSWindow.StyleMask=automatic ? [.borderless,.nonactivatingPanel]:[.borderless,.nonactivatingPanel,.resizable]
        let panel=SpeechPanel(contentRect:CGRect(origin:.zero,size:size),styleMask:style,backing:.buffered,defer:false)
        panel.preferredSize=size;panel.delegate=panel
        panel.title=model.displayName(agent)+" · Pikminions";panel.minSize=CGSize(width:240,height:80);panel.maxSize=CGSize(width:520,height:760)
        if !automatic {panel.minSize=CGSize(width:280,height:240)}
        panel.backgroundColor = .clear;panel.isOpaque=false;panel.hasShadow=true;panel.isFloatingPanel=true;panel.hidesOnDeactivate=false
        panel.level = .floating;panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.stationary,.ignoresCycle]
        let content=NSHostingView(rootView:ConversationBubble(model:model,state:state,coordinator:self))
        content.sizingOptions=[];content.autoresizingMask=[.width,.height]
        panel.contentView=content
        panel.onEscape={ [weak self] in self?.close(agent.id) }
        panel.onResize={ [weak self] in guard let self,let model=self.model else{return};self.follow(agent.id,anchor:model.anchor(for:agent)) }
        panels[agent.id]=panel;order.append(agent.id)
        watchOutsideClicks()
        follow(agent.id,anchor:model.anchor(for:agent))
        if automatic {panel.orderFrontRegardless()}
        else {panel.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)}
        startStream(state);loadQuestion(state)
    }
    private func vocalEligible(_ agent:AgentRecord)->Bool {
        guard let model else{return false}
        return model.vocal.contains(agent.id) && agent.isInteractive && !agent.stale && model.tossProgress[agent.id]==nil && !model.grabbed.contains(agent.id) && model.visibleHeads.contains(where:{$0.id==agent.id})
    }
    private func keepsStream(_ state:ConversationState)->Bool {panels[state.id] != nil || state.islandFocused || vocalEligible(state.agent)}
    func receiveOutput(_ agent:AgentRecord,line:ConversationLine,historical:Bool) {
        guard vocalEligible(agent),line.role=="assistant",!line.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{return}
        let shouldOpen=vocalDelivery.receive(agentID:agent.id,eventID:"message:"+line.id,historical:historical && !line.streaming)
        // Delivery deduplication controls opening, not updates. A polled partial
        // may extend the already-speaking message without reopening a dismissal
        // or replacing newer streamed text with a stale shorter snapshot.
        if let state=states[agent.id],let previous=state.lines.last(where:{$0.role=="assistant"}),previous.id==line.id,previous.streaming,line.text.hasPrefix(previous.text) {
            if previous != line {state.append(line)}
        }
        guard shouldOpen else{return}
        let current=states[agent.id]?.agent ?? agent
        let state=state(for:current);state.append(line)
        show(current,automatic:true)
    }
    func receiveQuestion(_ agent:AgentRecord) {
        guard vocalEligible(agent),agent.needsUserInput,let id=agent.pendingRequestID else{return}
        guard vocalDelivery.receive(agentID:agent.id,eventID:"question:"+id,historical:false) else{return}
        show(agent,automatic:true)
    }
    func questionReady(_ id:String) {if let state=states[id] {receiveQuestion(state.agent);resizeForContent(state)}}
    func vocalModeChanged(_ agent:AgentRecord,enabled:Bool) {
        if enabled {
            let state=state(for:agent)
            if let line=state.lines.last(where:{$0.role=="assistant"}),!line.streaming {_=vocalDelivery.receive(agentID:agent.id,eventID:"message:"+line.id,historical:true)}
            if let id=agent.outputMessageID,!agent.outputStreaming {_=vocalDelivery.receive(agentID:agent.id,eventID:"message:"+id,historical:true)}
            if let id=agent.pendingRequestID {_=vocalDelivery.receive(agentID:agent.id,eventID:"question:"+id,historical:true)}
            if agent.needsUserInput {show(agent,automatic:true)}
            startStream(state)
        } else if let state=states[agent.id],state.vocalPresentation {close(agent.id)}
        if let model {refresh(model.records)}
    }
    func bubbleSize(_ state:ConversationState)->CGSize {
        if state.vocalPresentation {return CGSize(width:280,height:state.vocalHeight)}
        let question=state.question != nil || state.agent.needsUserInput
        var height:Double=question ? 400:320
        if state.partnerID != nil {height=max(height,400)}
        if state.choosingPartner {height=max(height,460)}
        return CGSize(width:320,height:height)
    }
    func resizeSpeech(_ state:ConversationState,height:CGFloat) {
        guard state.vocalPresentation else{return}
        let height=max(80,min(500,ceil(height)))
        guard abs(state.vocalHeight-height)>1 else{return}
        state.vocalHeight=height;resizeForContent(state)
    }
    func beginSpeechReply(_ state:ConversationState) {
        state.vocalReplying=true;focusSpeech(state)
    }
    func focusSpeech(_ state:ConversationState) {
        model?.setAttending(state.id,true)
        panels[state.id]?.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
    func expireSpeech(_ state:ConversationState,messageID:String) {
        guard state.vocalPresentation,state.lines.last(where:{$0.role=="assistant"})?.id==messageID,
              state.lines.last(where:{$0.role=="assistant"})?.streaming==false,
              state.question==nil,!state.agent.needsUserInput,state.agent.state != .waitingApproval,!state.vocalHovered,!state.vocalReplying,
              state.draft.isEmpty,!state.sending,state.error==nil else{return}
        close(state.id)
    }
    func resizeConversation(_ state:ConversationState,translation:CGSize) {
        guard !state.vocalPresentation,let panel=panels[state.id] else{return}
        if panel.resizeStart==nil {panel.resizeStart=panel.frame;panel.resizing=true}
        guard let start=panel.resizeStart else{return}
        let size=CGSize(width:max(panel.minSize.width,min(panel.maxSize.width,start.width+translation.width)),height:max(panel.minSize.height,min(panel.maxSize.height,start.height+translation.height)))
        panel.setFrame(CGRect(x:start.minX,y:start.maxY-size.height,width:size.width,height:size.height),display:true)
    }
    func finishConversationResize(_ state:ConversationState) {
        guard let panel=panels[state.id],panel.resizeStart != nil else{return}
        panel.resizeStart=nil;panel.resizing=false;panel.userSized=true;panel.preferredSize=panel.frame.size
        if let model {follow(state.id,anchor:model.anchor(for:state.agent))}
    }
    func growConversation(_ state:ConversationState) {
        resizeConversation(state,translation:CGSize(width:40,height:60));finishConversationResize(state)
    }
    func resizeForContent(_ state:ConversationState) {
        guard let panel=panels[state.id],!panel.userSized,let model else{return}
        let height=bubbleSize(state).height
        if !state.vocalPresentation,height<panel.preferredSize.height && (!state.draft.isEmpty || state.editingName) {return}
        if abs(panel.preferredSize.height-height)>1 {panel.preferredSize.height=height;follow(state.id,anchor:model.anchor(for:state.agent))}
    }
    func toggle(_ agent:AgentRecord) {if panels[agent.id] != nil,states[agent.id]?.vocalPresentation != true {close(agent.id)} else {show(agent)}}
    func dismissHead(_ id:String) {if islandID==id {focusIsland(nil)};close(id)}
    func nameChanged(_ agent:AgentRecord) {if let model {panels[agent.id]?.title=model.displayName(agent)+" · Pikminions"}}
    func close(_ id:String) {
        if let state=states[id] {
            if let line=state.lines.last(where:{$0.role=="assistant"}) {_=vocalDelivery.receive(agentID:id,eventID:"message:"+line.id,historical:true)}
            if let request=state.agent.pendingRequestID {_=vocalDelivery.receive(agentID:id,eventID:"question:"+request,historical:true)}
        }
        panels.removeValue(forKey:id)?.close();order.removeAll{$0==id}
        if let state=states[id] {state.vocalPresentation=false;state.vocalHovered=false}
        if states[id]?.islandFocused != true {model?.setAttending(id,false)}
        if panels.isEmpty {stopWatchingOutsideClicks()}
        if let state=states[id],!keepsStream(state) {state.streamTask?.cancel();state.streamTask=nil;state.streamGeneration=nil;state.questionTask?.cancel();state.questionTask=nil;state.questionGeneration=nil;state.loadingQuestion=false;state.lines=Array(state.lines.suffix(4))}
    }
    private func watchOutsideClicks() {
        guard outsideLocalMonitor==nil else{return}
        let clicks:NSEvent.EventTypeMask=[.leftMouseDown,.rightMouseDown,.otherMouseDown]
        outsideLocalMonitor=NSEvent.addLocalMonitorForEvents(matching:clicks) { [weak self] event in
            // Native menus and sheets are part of the bubble interaction.
            if let window=event.window,window.level.rawValue>=NSWindow.Level.popUpMenu.rawValue {return event}
            self?.dismissUnpinned(outside:event.window,point:NSEvent.mouseLocation)
            return event
        }
        outsideGlobalMonitor=NSEvent.addGlobalMonitorForEvents(matching:clicks) { [weak self] _ in
            self?.dismissUnpinned(outside:nil,point:nil)
        }
        deactivationObserver=NotificationCenter.default.addObserver(forName:NSApplication.didResignActiveNotification,object:NSApp,queue:.main) { [weak self] _ in
            MainActor.assumeIsolated {self?.dismissUnpinned(outside:nil,point:nil)}
        }
    }
    private func dismissUnpinned(outside window:NSWindow?,point:CGPoint?) {
        for (id,panel) in panels {
            var related=window
            while let candidate=related {
                if candidate===panel {model?.setAttending(id,true);model?.lookTowardBubble(id,bubble:panel.frame);break}
                related=candidate.sheetParent ?? candidate.parent
            }
        }
        let ids=panels.keys.filter {id in
            guard states[id]?.pinned != true,let panel=panels[id] else{return false}
            if panel.resizing {return false}
            var related=window
            while let candidate=related {
                if candidate===panel {return false}
                related=candidate.sheetParent ?? candidate.parent
            }
            if panel.attachedSheet != nil {return false}
            // WindowServer resize edges can deliver a local click without a window.
            if window==nil,let point,panel.frame.insetBy(dx:-6,dy:-6).contains(point) {return false}
            // A click/drag on its own head keeps the existing toggle/drag behavior.
            if let point,let state=states[id],let model,model.anchor(for:state.agent).insetBy(dx:-8,dy:-8).contains(point) {return false}
            return true
        }
        for id in ids {close(id)}
    }
    private func stopWatchingOutsideClicks() {
        if let outsideLocalMonitor {NSEvent.removeMonitor(outsideLocalMonitor)}
        if let outsideGlobalMonitor {NSEvent.removeMonitor(outsideGlobalMonitor)}
        if let deactivationObserver {NotificationCenter.default.removeObserver(deactivationObserver)}
        outsideLocalMonitor=nil;outsideGlobalMonitor=nil;deactivationObserver=nil
    }
    func follow(_ id:String,anchor:CGRect) {
        guard let panel=panels[id],!panel.resizing else{return}
        let screen=NSScreen.screens.first(where:{$0.frame.contains(CGPoint(x:anchor.midX,y:anchor.midY))}) ?? NSScreen.main
        let frame=screen?.visibleFrame ?? CGRect(x:0,y:0,width:1440,height:900)
        let placement=ConversationPlacement.frame(anchor:anchor,screen:frame,preferred:panel.preferredSize)
        if let state=states[id],state.vocalPresentation {let tail=SpeechTail.aimed(from:placement,to:anchor);if tail != state.vocalTail {state.vocalTail=tail}}
        panel.setFrame(placement,display:true)
        model?.lookTowardBubble(id,bubble:panel.frame)
    }
    func focusIsland(_ agent:AgentRecord?) {
        if islandID==agent?.id {return}
        if let old=islandID,let state=states[old] {state.islandFocused=false;if panels[old]==nil {model?.setAttending(old,false)};if !keepsStream(state) {state.streamTask?.cancel();state.streamTask=nil;state.streamGeneration=nil}}
        islandID=agent?.id
        if let agent {
            let state=state(for:agent);state.islandFocused=true;model?.setAttending(agent.id,true)
            if let model {let anchor=model.anchor(for:agent);model.lookTowardBubble(agent.id,bubble:anchor.offsetBy(dx:0,dy:-100))}
            startStream(state);loadQuestion(state)
        }
    }
    func blurIsland(_ id:String) {if islandID==id {focusIsland(nil)}}
    func refresh(_ records:[AgentRecord]) {
        for agent in records where vocalEligible(agent) && states[agent.id]==nil {_=state(for:agent)}
        for state in Array(states.values) {
            guard let agent=records.first(where:{$0.id==state.id}) else {
                state.agent.stale=true;state.status="Conversation unavailable"
                state.streamTask?.cancel();state.streamTask=nil;state.streamGeneration=nil;state.questionTask?.cancel();state.questionTask=nil;state.questionGeneration=nil;state.loadingQuestion=false
                if state.vocalPresentation,!state.pinned {close(state.id)}
                continue
            }
            let wasStale=state.agent.stale,previous=state.agent.pendingRequestID;state.agent=agent
            if state.vocalPresentation,!state.pinned,!vocalEligible(agent) {close(state.id)}
            if !agent.stale,keepsStream(state) {if wasStale || state.streamTask==nil {startStream(state)}}
            else {state.streamTask?.cancel();state.streamTask=nil;state.streamGeneration=nil}
            if previous != agent.pendingRequestID {
                state.question=nil
                if keepsStream(state) {loadQuestion(state)}
                resizeForContent(state)
            }
        }
    }
    func prepareCollaboration(_ from:AgentRecord,_ partner:AgentRecord?=nil) {
        show(from)
        let state=state(for:from);state.partnerID=partner?.id;state.choosingPartner=partner==nil
    }
    func reconnect(_ state:ConversationState) {state.streamTask?.cancel();state.streamTask=nil;state.streamGeneration=nil;startStream(state);loadQuestion(state)}
    private func startStream(_ state:ConversationState) {
        guard observesSources else{return}
        guard state.streamTask==nil,let model else{return}
        guard state.agent.isInteractive,!state.agent.stale else {state.status=state.agent.stale ? "Source disconnected":"Live controls unavailable";return}
        let generation=UUID();state.streamGeneration=generation
        state.streamTask=Task { @MainActor [weak self] in
            guard let self else{return}
            defer {if state.streamGeneration==generation {state.streamTask=nil;state.streamGeneration=nil}}
            for attempt in 0..<3 {
                do {
                    state.status=attempt==0 ? "Connecting…":"Reconnecting…"
                    let stream=try await model.sources.conversationStream(for:state.agent,afterSequence:state.lastSequence)
                    for try await item in stream {
                        try Task.checkCancellation();state.status=AppRuntime.fixture ? "Fixture stream":"Live"
                        self.applyStreamItem(item,to:state)
                    }
                    if Task.isCancelled {return}
                    throw SourceFailure.message("T3 ended the output stream.")
                } catch {
                    if Task.isCancelled {return}
                    if attempt==2 {state.status="Disconnected";state.error=error.localizedDescription;return}
                    do {try await Task.sleep(for:.milliseconds(300*(attempt+1)))} catch{return}
                }
            }
        }
    }
    func applyStreamItem(_ item:JSONValue,to state:ConversationState) {
        guard let model else{return}
        if case .number(let sequence)=item["sequence"] {
            if let previous=state.lastSequence,sequence<=previous {return}
            state.lastSequence=sequence
        }
        if item["kind"]?.string=="snapshot" {
            if case .number(let sequence)=item["snapshotSequence"] {state.lastSequence=sequence}
            state.lines=AgentSources.projectionLines(item["projection"])
            if let line=state.lines.last(where:{$0.role=="assistant"}) {model.observeOutput(state.id,line:line,historical:true)}
        } else if item["kind"]?.string=="event",let event=item["event"],let payload=event["payload"] {
            if let line=AgentSources.eventLine(event,threadID:state.agent.threadID) {
                state.append(line)
                if line.role=="assistant" {model.observeOutput(state.id,line:line,historical:false)}
            }
            if event["type"]?.string=="runtime-request.updated",payload["kind"]?.string=="user_input",let id=payload["id"]?.string {
                if payload["status"]?.string=="pending" {state.agent.pendingRequestID=id;state.agent.pendingRequestKind="user_input";receiveQuestion(state.agent);loadQuestion(state)}
                else if state.question?.requestId==id || state.agent.pendingRequestID==id {
                    state.question=nil;state.agent.pendingRequestID=nil
                    state.status=payload["status"]?.string=="resolved" ? "Answered":"Question closed"
                    if payload["status"]?.string=="resolved" {
                        model.questionResolved(state.id,requestID:id)
                        if state.agent.state == .waitingInput {state.agent.state = .starting}
                        resizeForContent(state)
                    }
                }
            }
        }
    }
    func loadQuestion(_ state:ConversationState) {
        guard observesSources else{return}
        guard state.agent.needsUserInput else{return}
        guard state.question?.requestId != state.agent.pendingRequestID,let model else{return}
        state.questionTask?.cancel();state.loadingQuestion=true
        let requestID=state.agent.pendingRequestID
        let generation=UUID();state.questionGeneration=generation
        state.questionTask=Task { @MainActor in
            defer {if state.questionGeneration==generation {state.loadingQuestion=false;state.questionTask=nil;state.questionGeneration=nil}}
            do {
                let document=try await model.sources.questions(for:state.agent)
                guard !Task.isCancelled,state.agent.pendingRequestID==requestID else{return}
                state.question=document;state.error=nil
                for question in document.questions where state.customAnswers[question.id]==nil {if let initial=question.initialAnswer {state.customAnswers[question.id]=initial}}
                model.questionLoaded(state.id,document:document)
            } catch {if !Task.isCancelled {state.error=error.localizedDescription}}
        }
    }
    private func perform(_ state:ConversationState,_ operation:@escaping @MainActor () async throws ->Void) {
        guard !state.sending else{return}
        state.sending=true;state.error=nil
        state.operationTask=Task { @MainActor in
            defer {state.sending=false;state.operationTask=nil}
            do {try await operation()} catch {state.error=error.localizedDescription}
        }
    }
    func send(_ state:ConversationState) {
        guard let model else{return}
        let text=state.draft.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !text.isEmpty,!state.agent.stale else{return}
        let ids=state.command(for:"message::"+state.delivery.rawValue+"::"+text)
        let spokenMessage=state.lines.last(where:{$0.role=="assistant"})?.id
        perform(state) {
            try await model.sources.send(state.agent,text:text,delivery:state.delivery,commandID:ids.commandID,messageID:ids.messageID)
            state.append(ConversationLine(id:ids.messageID,role:"user",text:text))
            if state.draft.trimmingCharacters(in:.whitespacesAndNewlines)==text {state.draft=""}
            state.submission=nil;state.status=state.agent.state.isActive && state.delivery == .nextTurn ? "Queued for next turn":"Sent"
            if state.vocalPresentation,state.draft.isEmpty,state.lines.last(where:{$0.role=="assistant"})?.id==spokenMessage {self.close(state.id)}
        }
    }
    func answer(_ state:ConversationState) {
        guard let model,let document=state.question,state.answersReady else{return}
        let answers=state.answerPayload
        let signature=answers.keys.sorted().map{$0+":"+(answers[$0] ?? []).joined(separator:"\u{1f}")}.joined(separator:"\u{1e}")
        let ids=state.command(for:"answer::"+document.requestId+"::"+signature)
        let spokenMessage=state.lines.last(where:{$0.role=="assistant"})?.id
        perform(state) {
            try await model.sources.answer(state.agent,requestID:document.requestId,answers:answers,commandID:ids.commandID)
            model.questionResolved(state.id,requestID:document.requestId)
            if state.agent.state == .waitingInput {state.agent.state = .starting}
            state.question=nil;state.agent.pendingRequestID=nil;state.selectedAnswers=[:];state.customAnswers=[:];state.submission=nil;state.status="Answer sent"
            if state.vocalPresentation,state.lines.last(where:{$0.role=="assistant"})?.id==spokenMessage {self.close(state.id)}
        }
    }
    func retry(_ state:ConversationState) {
        guard let model,!state.agent.state.isActive else{return}
        perform(state) {
            if state.lines.last(where:{$0.role=="user"})==nil {state.lines=try await model.sources.conversation(for:state.agent)}
            guard let text=state.lines.last(where:{$0.role=="user"})?.text else {throw SourceFailure.message("The last instruction is unavailable. Open the conversation to retry it.")}
            let ids=state.command(for:"retry::"+text)
            try await model.sources.send(state.agent,text:text,delivery:.nextTurn,commandID:ids.commandID,messageID:ids.messageID)
            state.submission=nil;state.status="Retry accepted"
        }
    }
    func create(_ state:ConversationState,fork:Bool) {
        guard let model else{return}
        let kind=fork ? "fork":"fresh"
        if state.creation?.kind != kind {state.creation=(kind,UUID().uuidString,UUID().uuidString)}
        guard let creation=state.creation else{return}
        let title=model.displayName(state.agent)+(fork ? " fork":" new conversation")
        perform(state) {
            if fork {try await model.sources.fork(state.agent,targetID:creation.targetID,title:title,commandID:creation.commandID)}
            else {try await model.sources.fresh(state.agent,targetID:creation.targetID,title:title,commandID:creation.commandID)}
            var agent=state.agent;agent.id="t3:"+creation.targetID;agent.threadID=creation.targetID;agent.nativeID=nil;agent.runID="";agent.title=title;agent.state = .idle;agent.output="";agent.pendingRequestID=nil
            agent.openURL=state.agent.openURL?.deletingLastPathComponent().appending(path:creation.targetID)
            model.records.append(agent);model.pinned.insert(agent.id);model.preferencesChanged()
            state.creation=nil;state.status=fork ? "Fork created":"Conversation created";self.show(agent)
        }
    }
    func stop(_ state:ConversationState) {
        guard let model else{return}
        let ids=state.command(for:"stop::"+state.agent.runID)
        perform(state) {try await model.sources.stop(state.agent,commandID:ids.commandID);state.submission=nil;state.status="Stop requested"}
    }
    func collaborate(_ state:ConversationState) {
        guard let model,let id=state.partnerID,let partner=model.records.first(where:{$0.id==id}),partner.id != state.id else{return}
        let instruction=state.collaborationDraft.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !instruction.isEmpty else{return}
        let text=AgentCommands.collaboration(instruction:instruction,partner:partner)
        let ids=state.command(for:"collaboration::"+partner.id+"::"+text)
        perform(state) {
            try await model.sources.send(state.agent,text:text,delivery:state.delivery,commandID:ids.commandID,messageID:ids.messageID)
            model.recordCollaboration(state.id,partner:partner.id)
            state.collaborationDraft="";state.partnerID=nil;state.submission=nil
            state.status=state.agent.state.isActive && state.delivery == .nextTurn ? "Collaboration instruction queued":"Collaboration instruction sent"
        }
    }
    func closeAll() {stopWatchingOutsideClicks();for state in states.values {state.cancel()};for panel in panels.values {panel.close()};panels=[:];order=[];model?.attending=[];model?.attentionGazes=[:]}
}
