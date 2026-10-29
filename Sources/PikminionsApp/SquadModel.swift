// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Foundation
import AppKit
import SwiftUI
import Observation
import Antille
import UserNotifications

enum SquadMode:String,CaseIterable {case desktop="Desktop",island="Island",both="Both"}
@MainActor @Observable final class SquadModel {
    var records:[AgentRecord]=[] {didSet {activeOrder.reconcile(records)}}
    private var activeOrder=ActiveAgentOrder()
    var selectedID:String?
    var selectedSpecies:PikminSpecies = .red
    var previewMood:PikminMood = .working
    var growth:PikminGrowth = PikminGrowth(rawValue:UserDefaults.standard.string(forKey:"Pikminions.growth") ?? "") ?? .reference
    var mode:SquadMode = SquadMode(rawValue:UserDefaults.standard.string(forKey:"Pikminions.mode") ?? "") ?? .both
    var showRecorded=false
    var projectFilter="All projects"
    var search=""
    var t3Status="Not connected"
    var codexStatus="Checking local history"
    var islandStatus="Starting island"
    var error:String?
    var connecting=false
    var alertsEnabled=UserDefaults.standard.bool(forKey:"Pikminions.alerts")
    var maxHeads=min(24,max(1,UserDefaults.standard.integer(forKey:"Pikminions.maxHeads")==0 ? 8:UserDefaults.standard.integer(forKey:"Pikminions.maxHeads")))
    var docked:Set<String>=Set(UserDefaults.standard.stringArray(forKey:"Pikminions.docked") ?? [])
    var tossProgress:[String:Double]=[:]
    var grabbed:Set<String>=[]
    var attending:Set<String>=[]
    var contextMenuHeads:Set<String>=[]
    var attentionGazes:[String:PikminGaze]=[:]
    var idleDirector=PikminIdleDirector()
    @ObservationIgnored private var idleTask:Task<Void,Never>?
    var grabAngles:[String:Double]=[:]
    var grabAnchors:[String:UnitPoint]=[:]
    var gravityEnabled=UserDefaults.standard.bool(forKey:"Pikminions.gravity")
    var fixedPositions:Set<String>=Set(UserDefaults.standard.stringArray(forKey:"Pikminions.fixedPositions") ?? [])
    var hidden:Set<String>=Set(UserDefaults.standard.stringArray(forKey:"Pikminions.hidden") ?? [])
    var muted:Set<String>=Set(UserDefaults.standard.stringArray(forKey:"Pikminions.muted") ?? [])
    var vocal:Set<String>=Set(UserDefaults.standard.stringArray(forKey:"Pikminions.vocal") ?? [])
    var pinned:Set<String>=Set(UserDefaults.standard.stringArray(forKey:"Pikminions.pinned") ?? [])
    var speciesOverrides:[String:String]=UserDefaults.standard.dictionary(forKey:"Pikminions.species") as? [String:String] ?? [:]
    var customLooks:[PikminLook]=(UserDefaults.standard.data(forKey:"Pikminions.customLooks").flatMap{try? JSONDecoder().decode([PikminLook].self,from:$0)} ?? []).filter(\.isValid)
    var lookAssignments:[String:String]=UserDefaults.standard.dictionary(forKey:"Pikminions.lookAssignments") as? [String:String] ?? [:]
    var selectedLookID:String?
    var lookEditor:PikminLookEditorRequest?
    let islandStore=IslandStore()
    let chirps=Chirps()
    let sources=AgentSources()
    var conversationReady=false
    var nicknames:[String:String]=UserDefaults.standard.dictionary(forKey:"Pikminions.names") as? [String:String] ?? [:]
    var headSizes:[String:String]=UserDefaults.standard.dictionary(forKey:"Pikminions.headSizes") as? [String:String] ?? [:]
    var collaborationPartners:[String:[String]]=UserDefaults.standard.dictionary(forKey:"Pikminions.partners") as? [String:[String]] ?? [:]
    var liveOutput:[String:String]=[:]
    private var liveOutputIDs:[String:String]=[:]
    var questions:[String:AgentQuestionDocument]=[:]
    private var resolvedQuestions:[String:String]=[:]
    var successes:[String:SuccessEvent]=[:]
    @ObservationIgnored var conversationCoordinator:ConversationCoordinator?
    @ObservationIgnored private var outputPresentationTask:Task<Void,Never>?
    @ObservationIgnored private var successTasks:[String:Task<Void,Never>]=[:]
    private var acceptTracker=AcceptTracker(latest:UserDefaults.standard.dictionary(forKey:"Pikminions.acceptedByAgent") as? [String:String] ?? [:])
    private var formResets:[String:(id:String,fields:[String:String])]=[:]
    private let sprites=SpriteLibrary()
    private var pollTask:Task<Void,Never>?
    private var connectTask:Task<Void,Never>?
    private var hostEventsTask:Task<Void,Never>?
    // Native fixtures attach the same controller to exercise real window lifetimes.
    var desktop:DesktopSquadController?
    private var embedded:IslandController?
    private var hostToken:String?
    private var hostedIDs:Set<String>=[]
    private var hostedActivities:[String:IslandActivity]=[:]
    private var hostedAt:[String:TimeInterval]=[:]
    private var hostHelloAt:TimeInterval=0
    private var handledActions:Set<String>=Set(UserDefaults.standard.stringArray(forKey:"Pikminions.handledActions") ?? [])
    private var generation=UUID().uuidString
    private var previous:[String:AgentRecord]=[:]
    private var primed=false
    private var pollVersion=0
    private var revision=0
    private var presentationVersion=0
    private var lastMagnet:TimeInterval=0
    private var lastMagnetValue=0.0
    private var hostedDropTarget:CGRect?
    private var usingSharedIsland=false
    private var magnetLevels:[String:Double]=[:]
    private var magnetPoints:[String:CGPoint]=[:]
    @ObservationIgnored private var hostActionTasks:[String:Task<Void,Never>]=[:]
    private var activeDrags:Set<String>=[]
    private var dragRevision=0
    private var dragHeartbeat:Task<Void,Never>?
    private var delivered:Set<String>=[]
    private var showWindow:(()->Void)?
    var selected:AgentRecord? {records.first{$0.id==selectedID}}
    var projects:[String] {["All projects"]+Set(records.map(\.project)).sorted()}
    var listed:[AgentRecord] {
        records.filter {item in
            (showRecorded || item.state != .recorded) &&
            (projectFilter=="All projects" || item.project==projectFilter) &&
            (search.isEmpty || item.title.localizedCaseInsensitiveContains(search) || item.project.localizedCaseInsensitiveContains(search))
        }.sorted {
            if $0.presentationRank != $1.presentationRank {return $0.presentationRank>$1.presentationRank}
            if $0.state.isActive != $1.state.isActive {return $0.state.isActive}
            return $0.updated>$1.updated
        }
    }
    var visibleHeads:[AgentRecord] {
        let recent=Date.now.addingTimeInterval(-600)
        return Array(listed.filter { !hidden.contains($0.id) && ($0.isCompactEligible || pinned.contains($0.id) || docked.contains($0.id) || ($0.state == .finished && $0.updated>recent)) }
            .sorted {
                let leftActive=$0.isCompactEligible,rightActive=$1.isCompactEligible
                if leftActive != rightActive {return leftActive}
                if leftActive {
                    if $0.attention.rank != $1.attention.rank {return $0.attention.rank>$1.attention.rank}
                    let leftRank=activeOrder.rank($0.id),rightRank=activeOrder.rank($1.id)
                    if leftRank != rightRank {return leftRank>rightRank}
                }
                if docked.contains($0.id) != docked.contains($1.id) {return docked.contains($0.id)}
                if pinned.contains($0.id) != pinned.contains($1.id) {return pinned.contains($0.id)}
                if $0.presentationRank != $1.presentationRank {return $0.presentationRank>$1.presentationRank}
                return $0.updated == $1.updated ? $0.id<$1.id:$0.updated>$1.updated
            }.prefix(maxHeads))
    }
    func species(for item:AgentRecord)->PikminSpecies {
        look(for:item)?.species ?? speciesOverrides[item.id].flatMap(PikminSpecies.init(rawValue:)) ?? PikminSpecies.assigned(to:item.id)
    }
    func look(for agent:AgentRecord)->PikminLook? {lookAssignments[agent.id].flatMap{id in customLooks.first{$0.id==id}}}
    var previewLook:PikminLook? {if let selected {return look(for:selected)};return selectedLookID.flatMap{id in customLooks.first{$0.id==id}}}
    func chooseLook(_ look:PikminLook,for agent:AgentRecord?) {
        selectedLookID=look.id;selectedSpecies=look.species
        if let agent {lookAssignments[agent.id]=look.id;preferencesChanged()}
    }
    func editLook(_ look:PikminLook?=nil,for agent:AgentRecord?=nil) {
        lookEditor=PikminLookEditorRequest(look:look ?? PikminLook(name:"Custom Pikmin \(customLooks.count+1)",species:agent.map{species(for:$0)} ?? selectedSpecies),agentID:agent?.id)
        showWindow?()
    }
    func saveLook(_ draft:PikminLook,for agentID:String?) {
        var look=draft;look.name=look.name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard look.isValid else{return}
        if let index=customLooks.firstIndex(where:{$0.id==look.id}) {customLooks[index]=look} else {customLooks.append(look)}
        if let agentID {lookAssignments[agentID]=look.id}
        selectedLookID=look.id;selectedSpecies=look.species;lookEditor=nil;preferencesChanged()
    }
    func displayName(_ agent:AgentRecord)->String {nicknames[agent.id].flatMap{$0.isEmpty ? nil:$0} ?? agent.title}
    func size(for agent:AgentRecord)->PikminSize {headSizes[agent.id].flatMap(PikminSize.init(rawValue:)) ?? .medium}
    func setSize(_ size:PikminSize,for agent:AgentRecord) {
        if size == .medium {headSizes.removeValue(forKey:agent.id)} else {headSizes[agent.id]=size.rawValue}
        desktop?.sync()
        conversationCoordinator?.follow(agent.id,anchor:anchor(for:agent))
        preferencesChanged()
    }
    func rename(_ agent:AgentRecord,to name:String) {
        let value=String(name.trimmingCharacters(in:.whitespacesAndNewlines).prefix(100))
        if value.isEmpty || value==agent.title {nicknames.removeValue(forKey:agent.id)} else {nicknames[agent.id]=value}
        conversationCoordinator?.nameChanged(agent)
        preferencesChanged()
    }
    func showConversation(_ agent:AgentRecord) {conversationCoordinator?.show(agent)}
    func hoverHead(_ id:String,inside:Bool) {desktop?.hover(id,inside:inside)}
    func beginContextMenu(_ id:String) {
        contextMenuHeads.insert(id);idleDirector.suspend(id);desktop?.pauseForMenu(id)
    }
    func endContextMenu(_ id:String) {
        contextMenuHeads.remove(id);desktop?.sync();desktop?.resumeAfterMenu()
        if let agent=records.first(where:{$0.id==id}) {conversationCoordinator?.follow(id,anchor:anchor(for:agent))}
    }
    func setAttending(_ id:String,_ value:Bool) {
        let changed=value ? attending.insert(id).inserted:attending.remove(id) != nil
        if value {desktop?.callToAttention(id)}
        if value {idleDirector.suspend(id)}
        else {attentionGazes.removeValue(forKey:id);desktop?.releaseAttention(id)}
        if changed {scheduleOutputPresentation()}
    }
    func lookTowardBubble(_ id:String,bubble:CGRect) {
        guard attending.contains(id),let agent=records.first(where:{$0.id==id}) else{return}
        let gaze=PikminGaze.towardBubble(bubble,from:anchor(for:agent))
        if attentionGazes[id] != gaze {attentionGazes[id]=gaze;scheduleOutputPresentation()}
        desktop?.faceBubble(id,direction:-gaze.y)
    }
    func setVocalMode(_ enabled:Bool,for agent:AgentRecord) {
        guard agent.isInteractive else{return}
        if enabled {vocal.insert(agent.id)} else {vocal.remove(agent.id)}
        preferencesChanged()
        conversationCoordinator?.vocalModeChanged(agent,enabled:enabled)
    }
    func toggleVocalMode(_ agent:AgentRecord) {setVocalMode(!vocal.contains(agent.id),for:agent)}
    func renameHead(_ agent:AgentRecord) {
        conversationCoordinator?.show(agent)
        if let state=conversationCoordinator?.state(for:agent) {state.nameDraft=displayName(agent);state.editingName=true}
    }
    func anchor(for agent:AgentRecord)->CGRect {
        desktop?.anchorFrame(for:agent.id) ?? CGRect(x:islandDropTarget().midX-20,y:islandDropTarget().maxY-56,width:40,height:36)
    }
    func recordCollaboration(_ id:String,partner:String) {
        collaborationPartners[id]=Array(Set((collaborationPartners[id] ?? [])+[partner]))
        collaborationPartners[partner]=Array(Set((collaborationPartners[partner] ?? [])+[id]))
        preferencesChanged()
    }
    func prepareCollaboration(_ from:String,_ to:String) {
        guard let first=records.first(where:{$0.id==from}),let second=records.first(where:{$0.id==to}),first.isInteractive,second.isInteractive else{return}
        conversationCoordinator?.prepareCollaboration(first,second)
    }
    func observeOutput(_ id:String,line:ConversationLine,historical:Bool) {
        guard line.role=="assistant" else{return}
        if let agent=records.first(where:{$0.id==id}) {conversationCoordinator?.receiveOutput(agent,line:line,historical:historical)}
        liveOutput[id]=line.text
        liveOutputIDs[id]=line.id
        observeSuccess(id,messageID:line.id,text:line.containsAccept==true ? "ACCEPT":line.text,streaming:line.streaming,historical:historical)
        scheduleOutputPresentation()
    }
    func questionLoaded(_ id:String,document:AgentQuestionDocument) {questions[id]=document;conversationCoordinator?.questionReady(id);scheduleOutputPresentation()}
    func questionResolved(_ id:String,requestID:String) {
        resolvedQuestions[id]=requestID;questions.removeValue(forKey:id)
        if let index=records.firstIndex(where:{$0.id==id && $0.pendingRequestID==requestID}) {
            records[index].pendingRequestID=nil
            if records[index].state == .waitingInput {records[index].state = .starting;records[index].detail="Answer sent"}
        }
        scheduleOutputPresentation()
    }
    private func scheduleOutputPresentation() {
        presentationVersion+=1
        guard outputPresentationTask==nil else{return}
        outputPresentationTask=Task { [weak self] in
            do {try await Task.sleep(for:.milliseconds(160))} catch{return}
            guard let self else{return};outputPresentationTask=nil;await present()
        }
    }
    private func observeSuccess(_ id:String,messageID:String,text:String,streaming:Bool=false,historical:Bool) {
        let before=acceptTracker.latest[id]
        let shouldCelebrate=acceptTracker.observe(agentID:id,messageID:messageID,text:text,streaming:streaming,historical:historical)
        if before != acceptTracker.latest[id] {UserDefaults.standard.set(acceptTracker.latest,forKey:"Pikminions.acceptedByAgent")}
        guard shouldCelebrate else{return}
        successes[id]=SuccessEvent(id:messageID,started:.now)
        desktop?.celebrate(id)
        successTasks.removeValue(forKey:id)?.cancel()
        embedded?.pulse()
        if usingSharedIsland,let token=hostToken {Task {_=try? await sendHost(IslandRequest(operation:"pulse",producerID:"dev.upsided.pikminions",token:token))}}
        successTasks[id]=Task { [weak self] in
            do {try await Task.sleep(for:.milliseconds(1500))} catch{return}
            guard let self else{return};successes.removeValue(forKey:id);successTasks.removeValue(forKey:id);await present()
        }
        scheduleOutputPresentation()
    }
    func start(showWindow:@escaping ()->Void) {
        guard pollTask==nil else{return}
        self.showWindow=showWindow
        if !UserDefaults.standard.bool(forKey:"Pikminions.topProfilesV5") {
            growth = .reference
            UserDefaults.standard.set(growth.rawValue,forKey:"Pikminions.growth")
            UserDefaults.standard.set(true,forKey:"Pikminions.topProfilesV5")
        }
        var profile=IslandProfile(name:"Pikminions");profile.fillHex="000000";profile.wingWidth=76;profile.expandedWidth=390;profile.expandedHeight=520;profile.compactLimit=6
        profile.openOnHover=false
        islandStore.profile=profile
        if AppRuntime.fixture {
            pinned.formUnion(["t3:fixture-question","t3:fixture-worker","t3:fixture-partner","t3:fixture-idle"])
            speciesOverrides=["t3:fixture-question":"yellow","t3:fixture-worker":"glow","t3:fixture-partner":"winged","t3:fixture-idle":"red"]
        }
        islandStore.actionHandler={ [weak self] activity,action in
            guard let self,let agent=records.first(where:{$0.id==activity.activityID}) else{return}
            if action.id=="open" {open(agent)}
            else if action.id=="mute" {toggleMute(agent)}
            else if action.id=="detach" {undock(agent,at:action.position);embedded?.completeExtraction(activityID:activity.id)}
            else {Task {await self.performIslandAction(agent,actionID:action.id,fields:action.fields ?? [:],eventID:UUID().uuidString)}}
        }
        embedded=IslandController(store:islandStore,compact:{ [weak self] activity in
            guard let self,let agent=records.first(where:{$0.id==activity.activityID}) else {return AnyView(IslandActivityIcon(activity))}
            return AnyView(PikminHead(species:species(for:agent),mood:agent.stale ? .disconnected : agent.mood,growth:growth,animated:!attending.contains(agent.id),phase:Double(abs(agent.id.hashValue%20)),focusGaze:attentionGazes[agent.id],idleEvent:idleDirector.active[agent.id],appearance:look(for:agent)).modifier(IslandSuccessEffect(trigger:activity.celebrationID)))
        })
        desktop=DesktopSquadController(model:self)
        conversationCoordinator=ConversationCoordinator(model:self)
        idleTask=Task { [weak self] in
            var random=SystemRandomNumberGenerator()
            while !Task.isCancelled {
                guard let self else{return}
                let pointer=NSEvent.mouseLocation
                let eligible=NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? Set<String>():Set(visibleHeads.filter {agent in
                    let center=anchor(for:agent)
                    return !agent.stale && [.calm,.working,.happy].contains(agent.mood) && !attending.contains(agent.id) && !contextMenuHeads.contains(agent.id) && !grabbed.contains(agent.id) && tossProgress[agent.id]==nil && successes[agent.id]==nil && hypot(pointer.x-center.midX,pointer.y-center.midY)>110
                }.map(\.id))
                if idleDirector.advance(at:.now,eligible:eligible,using:&random) {scheduleOutputPresentation()}
                do {try await Task.sleep(for:.milliseconds(500))} catch{return}
            }
        }
        hostEventsTask=Task { [weak self] in
            guard let self else{return}
            while !Task.isCancelled {
                guard let token=hostToken,mode != .desktop else {
                    do {try await Task.sleep(for:.milliseconds(800))} catch{return};continue
                }
                do {
                    let ignored=Array(handledActions.union(Set(hostActionTasks.keys)).prefix(256))
                    let response=try await sendHost(IslandRequest(operation:"actions.wait",producerID:"dev.upsided.pikminions",token:token,excludingActionIDs:ignored))
                    guard response.ok else {throw SourceFailure.message(response.message ?? "Antille access needs attention.")}
                    await handleHostActions(response.actions ?? [],token:token)
                } catch {
                    do {try await Task.sleep(for:.seconds(1))} catch{return}
                }
            }
        }
        pollTask=Task { [weak self] in
            guard let self else{return}
            if !AppRuntime.fixture {do {try await chirps.prepare()} catch {self.error=error.localizedDescription}}
            do {try await sources.loadSavedAccess()} catch {self.error=error.localizedDescription}
            hostToken=await Task.detached(priority:.utility) {IslandCredential.read("dev.upsided.pikminions")}.value
            conversationReady=await sources.canOperate
            while !Task.isCancelled {
                await poll()
                do {try await Task.sleep(for:.seconds(4))} catch {return}
            }
        }
    }
    func stop() {idleTask?.cancel();pollTask?.cancel();connectTask?.cancel();hostEventsTask?.cancel();dragHeartbeat?.cancel();outputPresentationTask?.cancel();for task in successTasks.values {task.cancel()};for task in hostActionTasks.values {task.cancel()};sprites.cancel();conversationCoordinator?.closeAll();desktop?.close();embedded?.close()}
    func connect() {
        guard !connecting else{return}
        connecting=true;error=nil
        connectTask=Task { [weak self] in
            guard let self else{return}
            defer{connecting=false}
            do {try await sources.connectT3();conversationReady=await sources.canOperate;await poll()}
            catch {self.error=error.localizedDescription;t3Status="Connection failed"}
        }
    }
    func disconnect() {
        pollVersion+=1
        connectTask=Task {
            do {try await sources.disconnectT3();conversationReady=false;records.removeAll{$0.isInteractive};conversationCoordinator?.refresh(records);t3Status="Not connected";await present()}
            catch {self.error="Could not revoke T3 access: "+error.localizedDescription}
        }
    }
    private func poll() async {
        pollVersion+=1;let version=pollVersion
        var incoming:[AgentRecord]=[]
        conversationReady=await sources.canOperate
        if await sources.connected {
            do {incoming=try await sources.t3();t3Status=AppRuntime.fixture ? "Fixture · no live connections":"Connected · \(incoming.count) conversations"}
            catch {
                t3Status="Disconnected";self.error=error.localizedDescription
                incoming=records.filter{$0.source=="T3"}.map {var item=$0;item.stale=true;return item}
            }
        }
        do {
            let codex=try await sources.codex()
            let known=Set(incoming.compactMap(\.nativeID))
            incoming+=codex.records.filter{!known.contains($0.nativeID ?? "")}
            codexStatus=codex.live ? "Live shared server" : "Recorded only · no live server"
        } catch {codexStatus="Local history unavailable"}
        guard version==pollVersion,!Task.isCancelled else{return}
        incoming=incoming.map(applyingResolvedQuestion)
        let prior=Dictionary(records.map{($0.id,$0)},uniquingKeysWith:{$1})
        let stateChanged=records.count != incoming.count || incoming.contains {agent in
            guard let old=prior[agent.id] else{return true}
            return old.state != agent.state || old.stale != agent.stale || old.needsUserInput != agent.needsUserInput || old.runID != agent.runID
        }
        records=incoming;desktop?.sync()
        // Retire finished compact heads before potentially slow output/history
        // enrichment. Normal polling continues to refresh every four seconds.
        if stateChanged {await present();guard version==pollVersion,!Task.isCancelled else{return}}
        let output=await sources.recentOutputs(for:visibleHeads)
        guard version==pollVersion,!Task.isCancelled else{return}
        let byID=Dictionary(output.map{($0.id,$0)},uniquingKeysWith:{$1})
        incoming=incoming.map{byID[$0.id] ?? $0}
        incoming=incoming.map(applyingResolvedQuestion)
        let signals=incoming.filter { item in
            guard primed,let old=previous[item.id] else{return false}
            return (old.state != item.state || old.runID != item.runID || old.pendingRequestID != item.pendingRequestID) && !item.silent && !item.stale &&
                !muted.contains(item.id) && item.attention != .none
        }
        notify(signals)
        for agent in incoming where !agent.stale && agent.output.contains("ACCEPT") {
            if let messageID=agent.outputMessageID {
                observeSuccess(agent.id,messageID:messageID,text:agent.output,streaming:agent.outputStreaming,historical:agent.outputHistorical || !primed || previous[agent.id]==nil)
            }
        }
        for agent in incoming where !agent.stale {
            if let messageID=agent.outputMessageID,!agent.output.isEmpty {
                conversationCoordinator?.receiveOutput(agent,line:ConversationLine(id:messageID,role:"assistant",text:agent.output,streaming:agent.outputStreaming),historical:agent.outputHistorical || !primed || previous[agent.id]==nil)
            }
            if agent.needsUserInput {conversationCoordinator?.receiveQuestion(agent)}
        }
        previous=Dictionary(incoming.map{($0.id,$0)},uniquingKeysWith:{$1});primed=true
        records=incoming;revision+=1
        conversationCoordinator?.refresh(incoming)
        await present()
    }
    private func applyingResolvedQuestion(_ agent:AgentRecord)->AgentRecord {
        guard let resolved=resolvedQuestions[agent.id],resolved==agent.pendingRequestID else{return agent}
        var result=agent;result.pendingRequestID=nil
        if result.state == .waitingInput {result.state = .starting;result.detail="Answer sent"}
        return result
    }
    func preferencesChanged() {
        presentationVersion+=1
        UserDefaults.standard.set(mode.rawValue,forKey:"Pikminions.mode")
        UserDefaults.standard.set(gravityEnabled,forKey:"Pikminions.gravity")
        UserDefaults.standard.set(Array(fixedPositions),forKey:"Pikminions.fixedPositions")
        UserDefaults.standard.set(nicknames,forKey:"Pikminions.names")
        UserDefaults.standard.set(headSizes,forKey:"Pikminions.headSizes")
        UserDefaults.standard.set(collaborationPartners,forKey:"Pikminions.partners")
        UserDefaults.standard.set(growth.rawValue,forKey:"Pikminions.growth")
        UserDefaults.standard.set(Array(docked),forKey:"Pikminions.docked")
        UserDefaults.standard.set(maxHeads,forKey:"Pikminions.maxHeads")
        UserDefaults.standard.set(Array(hidden),forKey:"Pikminions.hidden")
        UserDefaults.standard.set(Array(muted),forKey:"Pikminions.muted")
        UserDefaults.standard.set(Array(vocal),forKey:"Pikminions.vocal")
        UserDefaults.standard.set(Array(pinned),forKey:"Pikminions.pinned")
        UserDefaults.standard.set(speciesOverrides,forKey:"Pikminions.species")
        UserDefaults.standard.set(lookAssignments,forKey:"Pikminions.lookAssignments")
        if let data=try? JSONEncoder().encode(customLooks) {UserDefaults.standard.set(data,forKey:"Pikminions.customLooks")}
        conversationCoordinator?.refresh(records)
        Task {await present()}
    }
    func setSpecies(_ value:PikminSpecies,for agent:AgentRecord?) {
        selectedSpecies=value
        selectedLookID=nil
        if let agent {lookAssignments.removeValue(forKey:agent.id);speciesOverrides[agent.id]=value.rawValue;preferencesChanged()}
    }
    func islandDropTarget()->CGRect {
        if usingSharedIsland,let hostedDropTarget {return hostedDropTarget}
        if let embedded {return embedded.dropTarget}
        let screen=NSScreen.main?.frame ?? CGRect(x:0,y:0,width:1440,height:900)
        return CGRect(x:screen.midX-150,y:screen.maxY-105,width:300,height:125)
    }
    func landingPoint(for agent:AgentRecord) async ->CGPoint {
        let candidate=IslandActivity(producerID:"dev.upsided.pikminions",activityID:agent.id,generation:generation,revision:revision,
            title:String(displayName(agent).prefix(400)),attention:agent.stale || agent.state == .finished ? .none:agent.attention,priority:20,updatedAt:agent.updated,allowsNotifications:false)
        if usingSharedIsland,let token=hostToken,
           let response=try? await sendHost(IslandRequest(operation:"landing",producerID:candidate.producerID,token:token,activity:candidate)),response.ok,let position=response.position {return position.cgPoint}
        return embedded?.reserveLanding(candidate) ?? CGPoint(x:islandDropTarget().midX,y:islandDropTarget().maxY-38)
    }
    func beginDrag(_ id:String) {
        activeDrags.insert(id);sendDrag(id,active:true)
        if dragHeartbeat==nil {
            dragHeartbeat=Task { [weak self] in
                guard let self else{return}
                while !Task.isCancelled,!activeDrags.isEmpty {
                    do {try await Task.sleep(for:.milliseconds(800))} catch{return}
                    for id in activeDrags {sendDrag(id,active:true)}
                }
                dragHeartbeat=nil
            }
        }
    }
    func endDrag(_ id:String) {
        activeDrags.remove(id);sendDrag(id,active:false);magnet(0,for:id)
        if activeDrags.isEmpty {dragHeartbeat?.cancel();dragHeartbeat=nil}
    }
    private func sendDrag(_ id:String,active:Bool) {
        dragRevision+=1
        let revision=dragRevision
        embedded?.setDropInteraction(sessionID:id,active:active,revision:revision)
        if usingSharedIsland,let token=hostToken {Task {_ = try? await sendHost(IslandRequest(operation:"drop-session",producerID:"dev.upsided.pikminions",token:token,activityID:id,value:active ? 1:0,revision:revision))}}
    }
    func magnet(_ amount:Double,for id:String="pointer",at point:CGPoint?=nil) {
        if amount<=0 {magnetLevels.removeValue(forKey:id);magnetPoints.removeValue(forKey:id)} else {magnetLevels[id]=amount;if let point {magnetPoints[id]=point}}
        let strongest=magnetLevels.max(by:{$0.value<$1.value})
        let level=strongest?.value ?? 0
        let focus=strongest.flatMap{magnetPoints[$0.key]}
        embedded?.setMagnet(level,at:focus)
        let now=ProcessInfo.processInfo.systemUptime
        guard now-lastMagnet>0.06 || (level==0 && lastMagnetValue>0) else{return}
        guard abs(lastMagnetValue-level)>0.015 || now-lastMagnet>0.4 else{return}
        lastMagnet=now;lastMagnetValue=level
        if usingSharedIsland,let token=hostToken {
            Task {_ = try? await sendHost(IslandRequest(operation:"magnet",producerID:"dev.upsided.pikminions",token:token,value:level,position:focus.map(IslandPoint.init)))}
        }
    }
    func dock(_ agent:AgentRecord) {
        conversationCoordinator?.dismissHead(agent.id)
        guard !docked.contains(agent.id) else{return}
        docked.insert(agent.id);desktop?.sync();tossProgress.removeValue(forKey:agent.id)
        if mode == .desktop {mode = .both}
        pinned.insert(agent.id)
        if !AppRuntime.fixture {chirps.pop();NSHapticFeedbackManager.defaultPerformer.perform(.alignment,performanceTime:.now)}
        embedded?.pulse()
        if usingSharedIsland,let token=hostToken {
            Task {_ = try? await sendHost(IslandRequest(operation:"pulse",producerID:"dev.upsided.pikminions",token:token))}
        }
        preferencesChanged()
    }
    func dismiss(_ agent:AgentRecord) {
        conversationCoordinator?.dismissHead(agent.id)
        if desktop?.jump(agent.id) != true {dock(agent)}
    }
    func undock(_ agent:AgentRecord,at position:IslandPoint?=nil) {
        docked.remove(agent.id)
        if mode == .island {mode = .both}
        if let position,position.x.isFinite,position.y.isFinite {
            let preview=CGRect(origin:CGPoint(x:position.x,y:position.y),size:PikminSize.medium.panelSize)
            let screen=NSScreen.screens.first(where:{$0.visibleFrame.intersects(preview)})?.visibleFrame ?? NSScreen.main?.visibleFrame ?? preview
            let frame=size(for:agent).resizedFrame(from:preview,within:screen)
            UserDefaults.standard.set([frame.minX,frame.minY],forKey:"Pikminions.position."+agent.id)
        }
        desktop?.sync()
        conversationCoordinator?.follow(agent.id,anchor:anchor(for:agent))
        preferencesChanged()
    }
    func toggleMute(_ agent:AgentRecord) {
        if muted.contains(agent.id) {muted.remove(agent.id)} else {muted.insert(agent.id)}
        preferencesChanged()
    }
    func togglePin(_ agent:AgentRecord) {
        if pinned.contains(agent.id) {pinned.remove(agent.id)} else {pinned.insert(agent.id)}
        preferencesChanged()
    }
    func toggleFixedPosition(_ agent:AgentRecord) {
        if fixedPositions.contains(agent.id) {fixedPositions.remove(agent.id)} else {fixedPositions.insert(agent.id)}
        preferencesChanged()
    }
    func hide(_ agent:AgentRecord) {conversationCoordinator?.dismissHead(agent.id);hidden.insert(agent.id);preferencesChanged()}
    func revealAll() {hidden=[];preferencesChanged()}
    func open(_ agent:AgentRecord) {
        if AppRuntime.fixture {showConversation(agent);return}
        if let url=agent.openURL {NSWorkspace.shared.open(url)}
        else {
            selectedID=agent.id;showWindow?()
            error="Codex does not expose a verified direct conversation link here. Open this conversation in Codex using its title."
        }
    }
    func select(_ agent:AgentRecord) {selectedID=agent.id;showWindow?()}
    func pairHost() {
        Task {
            do {
                let producer="dev.upsided.pikminions"
                let nonce=IslandCredential.read("pending::"+producer) ?? UUID().uuidString
                try IslandCredential.save(nonce,producer:"pending::"+producer)
                let response=try await Task.detached {try IslandLocalClient.send(IslandRequest(operation:"pair",producerID:producer,requestID:nonce))}.value
                if let token=response.token {
                    try IslandCredential.save(token,producer:producer);IslandCredential.delete("pending::"+producer)
                    hostToken=token;generation=UUID().uuidString
                    hostedActivities=[:];hostedAt=[:];hostHelloAt=0
                    _=try await sendHost(IslandRequest(operation:"hello",producerID:producer,generation:generation,token:token))
                    error=nil;await present()
                } else {error=response.message}
            } catch {self.error=error.localizedDescription}
        }
    }
    private func sendHost(_ request:IslandRequest) async throws -> IslandResponse {
        let response=try await Task.detached(priority:.utility) {try IslandLocalClient.send(request)}.value
        if let target=response.target {hostedDropTarget=target.cgRect}
        return response
    }
    private func present() async {
        presentationVersion+=1
        let version=presentationVersion
        revision+=1
        desktop?.sync()
        guard mode != .desktop else {
            usingSharedIsland=false
            embedded?.hide()
            if hostToken != nil {await clearHosted()}
            islandStatus="Desktop mode";return
        }
        let hostRunning=(try? await sendHost(IslandRequest(operation:"ping")))?.ok==true
        guard version==presentationVersion,!Task.isCancelled else{return}
        let agents=mode == .both ? visibleHeads.filter{docked.contains($0.id)}:visibleHeads
        let compactPriorities=activeOrder.priorities(for:agents)
        let activities=agents.map {agent in
            IslandActivity(producerID:"dev.upsided.pikminions",activityID:agent.id,generation:generation,revision:revision*2,
                title:String(displayName(agent).prefix(400)),detail:"",state:agent.statusLabel,
                attention:agent.stale || agent.state == .finished ? .none:agent.attention,
                priority:compactPriorities[agent.id] ?? 0,symbol:"leaf",accentHex:look(for:agent)?.bodyHex ?? species(for:agent).hex,
                actions:islandActions(agent),
                content:islandContent(agent),updatedAt:agent.updated,stale:agent.stale,allowsNotifications:false,focusActionID:"focus",blurActionID:"blur",celebrationID:attending.contains(agent.id) ? nil:successes[agent.id]?.id,formResetID:formResets[agent.id]?.id,formResetFields:formResets[agent.id]?.fields,actionsInMenu:true,requiresClickToExpand:true,preferredExpandedHeight:520,showsInCompact:agent.isCompactEligible)
        }
        if IslandDestination.select(hostAvailable:hostRunning,hasAccess:hostToken != nil) == .shared,let token=hostToken {
            do {
                let now=ProcessInfo.processInfo.systemUptime
                if now-hostHelloAt>15 {
                    let hello=try await sendHost(IslandRequest(operation:"hello",producerID:"dev.upsided.pikminions",generation:generation,token:token))
                    guard hello.ok else {throw SourceFailure.message(hello.message ?? "Pair with Antille again.")}
                    hostHelloAt=now
                }
                var pending:[(AgentRecord,IslandActivity,PikminIdleEvent?)]=[]
                func animated(_ activity:IslandActivity,_ frames:[String],_ agent:AgentRecord,_ idle:PikminIdleEvent?=nil)->IslandActivity {
                    var result=activity
                    let offset=frames.isEmpty || idle != nil ? 0:abs(agent.id.hashValue%frames.count)
                    result.spriteFrames=Array(frames.dropFirst(offset))+Array(frames.prefix(offset))
                    result.framesPerSecond=max(1,Double(frames.count)/(idle?.kind.duration ?? 4.8))
                    result.spriteStartedAt=idle?.startedAt.timeIntervalSince1970;result.spriteRepeats=idle == nil
                    result.revision+=1
                    return result
                }
                // Publish the entire docked squad before rendering any new animation.
                // Cached animations never get replaced by posters during routine polls.
                for var activity in activities {
                    guard let agent=agents.first(where:{$0.id==activity.activityID}) else{continue}
                    let mood=agent.stale ? PikminMood.disconnected:agent.mood
                    let idle=idleDirector.active[agent.id]
                    if attending.contains(agent.id) {activity.imagePath=try await sprites.poster(species:species(for:agent),mood:mood,growth:growth,gaze:attentionGazes[agent.id] ?? .zero,appearance:look(for:agent))}
                    else if let frames=sprites.cachedFrames(species:species(for:agent),mood:mood,growth:growth,idle:idle?.kind,appearance:look(for:agent)) {activity=animated(activity,frames,agent,idle)}
                    else {
                        if idle != nil,let base=sprites.cachedFrames(species:species(for:agent),mood:mood,growth:growth,appearance:look(for:agent)) {activity=animated(activity,base,agent)}
                        else {activity.imagePath=try await sprites.poster(species:species(for:agent),mood:mood,growth:growth,appearance:look(for:agent))}
                        pending.append((agent,activity,idle))
                    }
                    guard version==presentationVersion,!Task.isCancelled else{return}
                    try await publishIfChanged(activity,token:token)
                    hostedIDs.insert(activity.activityID)
                }
                guard version==presentationVersion,!Task.isCancelled else{return}
                embedded?.hide();usingSharedIsland=true;islandStatus="Shared Antille island"
                let ids=Set(activities.map(\.activityID))
                for id in hostedIDs.subtracting(ids) {
                    guard version==presentationVersion,!Task.isCancelled else{return}
                    _=try await sendHost(IslandRequest(operation:"remove",producerID:"dev.upsided.pikminions",token:token,activityID:id,revision:revision*2+1))
                    hostedActivities.removeValue(forKey:id);hostedAt.removeValue(forKey:id)
                }
                guard version==presentationVersion,!Task.isCancelled else{return}
                hostedIDs=ids
                for (agent,activity,idle) in pending {
                    let frames=try await sprites.frames(species:species(for:agent),mood:agent.stale ? .disconnected:agent.mood,growth:growth,idle:idle?.kind,appearance:look(for:agent))
                    guard version==presentationVersion,!Task.isCancelled else{return}
                    let update=animated(activity,frames,agent,idle)
                    try await publishIfChanged(update,token:token)
                }
            } catch {
                guard version==presentationVersion,!Task.isCancelled else{return}
                hostHelloAt=0
                presentEmbedded(activities,status:"Embedded island · pair Antille to restore sharing")
            }
        } else {
            presentEmbedded(activities,status:hostRunning ? "Embedded island · pair Antille to share":"Embedded Antille island")
        }
    }
    private func presentEmbedded(_ activities:[IslandActivity],status:String) {
        usingSharedIsland=false;islandStatus=status
        do {try islandStore.replace(producerID:"dev.upsided.pikminions",with:activities);embedded?.show()}
        catch {self.error=error.localizedDescription}
    }
    private func publishIfChanged(_ activity:IslandActivity,token:String) async throws {
        var content=activity;content.revision=0
        let now=ProcessInfo.processInfo.systemUptime
        guard hostedActivities[activity.activityID] != content || now-(hostedAt[activity.activityID] ?? 0)>20 else{return}
        let result=try await sendHost(IslandRequest(operation:"upsert",producerID:activity.producerID,generation:generation,token:token,activity:activity))
        guard result.ok else {throw SourceFailure.message(result.message ?? "Antille rejected the activity.")}
        hostedActivities[activity.activityID]=content;hostedAt[activity.activityID]=now
    }
    private func handleHostActions(_ events:[IslandActionEvent],token:String) async {
        for event in events {
            guard hostActionTasks[event.id]==nil else {continue}
            hostActionTasks[event.id]=Task { [weak self] in
                guard let self else{return}
                await processHostAction(event,token:token)
                hostActionTasks.removeValue(forKey:event.id)
            }
        }
    }
    private func processHostAction(_ event:IslandActionEvent,token:String) async {
            var result="Handled"
            if !handledActions.contains(event.id),let agent=records.first(where:{$0.id==event.activityID}) {
                handledActions.insert(event.id)
                if handledActions.count>200 {handledActions=Set([event.id])}
                UserDefaults.standard.set(Array(handledActions),forKey:"Pikminions.handledActions")
                if event.actionID=="open" {open(agent)}
                if event.actionID=="mute" {toggleMute(agent)}
                if event.actionID=="detach" {undock(agent,at:event.position)}
                if !["open","mute","detach"].contains(event.actionID) {result=await performIslandAction(agent,actionID:event.actionID,fields:event.fields ?? [:],eventID:event.id)}
            }
            _=try? await sendHost(IslandRequest(operation:"ack",producerID:"dev.upsided.pikminions",token:token,actionID:event.id,result:result,revision:event.actionID=="detach" ? revision*2+1:nil))
    }
    private func islandActions(_ agent:AgentRecord)->[IslandAction] {
        var actions=[IslandAction(id:"talk",title:"Open conversation bubble"),IslandAction(id:"vocal",title:vocal.contains(agent.id) ? "Disable vocal mode":"Enable vocal mode"),IslandAction(id:"detach",title:"To desktop"),IslandAction(id:"collaborate",title:"Collaborate…"),IslandAction(id:"open",title:"Open in T3"),IslandAction(id:"mute",title:muted.contains(agent.id) ? "Unmute":"Mute")]
        if agent.state.isActive {actions.append(IslandAction(id:"steer",title:"Steer this reply now"))}
        return actions
    }
    private func islandContent(_ agent:AgentRecord)->[IslandBlock] {
        var content:[IslandBlock]=[]
        let output=liveOutput[agent.id] ?? agent.output
        if !output.isEmpty && !agent.needsUserInput {content.append(IslandBlock(id:"output",kind:.text,text:IslandMarkdown.tail(output),lineLimit:9,markdown:true,textIdentity:liveOutputIDs[agent.id] ?? agent.outputMessageID))}
        if let document=questions[agent.id],document.requestId==agent.pendingRequestID {
            for question in document.questions {
                content.append(IslandBlock(id:"question."+question.id,kind:.text,text:String(question.question.prefix(850))))
                if !question.options.isEmpty {
                    content.append(IslandBlock(id:"answer."+question.id,kind:.choices,options:question.options.map{IslandChoice(label:$0.label,value:$0.value ?? $0.label,detail:String($0.description.prefix(180)))},multiple:question.multiSelect))
                }
                if question.options.isEmpty || question.allowCustomAnswer != false {content.append(IslandBlock(id:"custom."+question.id,kind:.textInput,text:question.options.isEmpty ? "Your answer":"Or write an answer"))}
            }
            content.append(IslandBlock(id:"answer-submit",kind:.button,text:"Send answer",actionID:"answer::"+document.requestId,disabled:!conversationReady))
        } else if agent.needsUserInput {
            content.append(IslandBlock(id:"question-open",kind:.button,text:"Answer question",actionID:"talk"))
        } else if agent.isInteractive {
            content.append(IslandBlock(id:"reply",kind:.hstack,children:[IslandBlock(id:"message",kind:.textInput,text:"Reply…"),IslandBlock(id:"send",kind:.button,text:agent.state.isActive ? "Queue":"Send",actionID:"send",disabled:!conversationReady)]))
        }
        if !conversationReady,agent.isInteractive {content.append(IslandBlock(id:"reconnect",kind:.button,text:"Reconnect T3",actionID:"reconnect"))}
        return content
    }
    @discardableResult private func performIslandAction(_ agent:AgentRecord,actionID:String,fields:[String:String],eventID:String) async ->String {
        guard let coordinator=conversationCoordinator else{return "Error: Pikminions is starting."}
        if actionID=="focus" {coordinator.focusIsland(agent);return "Focused"}
        if actionID=="blur" {coordinator.blurIsland(agent.id);return "Hidden"}
        if actionID=="talk" {coordinator.show(agent);return "Opened bubble"}
        if actionID=="collaborate" {coordinator.prepareCollaboration(agent);return "Choose a collaborator"}
        if actionID=="vocal" {toggleVocalMode(agent);return vocal.contains(agent.id) ? "Vocal mode on":"Vocal mode off"}
        if actionID=="reconnect" {connect();return "Reconnecting T3"}
        let state=coordinator.state(for:agent)
        guard !state.sending else{return "Error: Wait for this Pikmin’s current submission."}
        if ["send","steer"].contains(actionID) {
            guard let message=fields["message"],!message.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{return "Error: Write a message first."}
            state.draft=message;state.delivery=actionID=="steer" ? .steer:.nextTurn;coordinator.send(state)
        } else if actionID.hasPrefix("answer::") {
            let requestID=String(actionID.dropFirst(8))
            do {
                if state.question?.requestId != requestID {state.question=try await sources.questions(for:agent)}
                guard let document=state.question,document.requestId==requestID else{return "Error: This question is no longer current."}
                for question in document.questions {
                    let raw=fields["answer."+question.id] ?? "[]"
                    state.selectedAnswers[question.id]=raw.data(using:.utf8).flatMap{try? JSONDecoder().decode([String].self,from:$0)} ?? []
                    state.customAnswers[question.id]=fields["custom."+question.id] ?? ""
                    if question.multiSelect != true,!((state.customAnswers[question.id] ?? "").trimmingCharacters(in:.whitespacesAndNewlines).isEmpty) {state.selectedAnswers[question.id]=[]}
                }
                guard state.answersReady else{return "Error: Choose or write an answer for each question."}
                coordinator.answer(state)
            } catch {return "Error: "+error.localizedDescription}
        } else {return "Error: This action is unavailable."}
        await state.operationTask?.value
        if let error=state.error {return "Error: "+error}
        formResets[agent.id]=(eventID,fields)
        if actionID.hasPrefix("answer::") {questions.removeValue(forKey:agent.id)}
        await present()
        return state.status
    }
    private func clearHosted() async {
        guard let token=hostToken else{return}
        for id in hostedIDs {
            _=try? await sendHost(IslandRequest(operation:"remove",producerID:"dev.upsided.pikminions",token:token,activityID:id,revision:revision*2+1))
        }
        hostedIDs=[];hostedActivities=[:];hostedAt=[:]
    }
    func enableAlerts() async {
        guard !AppRuntime.fixture else {error="System alerts are disabled in the fixture app.";return}
        do {
            alertsEnabled=try await UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.sound])
            UserDefaults.standard.set(alertsEnabled,forKey:"Pikminions.alerts")
            if !alertsEnabled {error="Alerts are disabled in macOS. The heads still show requests visually."}
        } catch {self.error=error.localizedDescription}
    }
    private func notify(_ agents:[AgentRecord]) {
        guard !AppRuntime.fixture,alertsEnabled,!agents.isEmpty else{return}
        var fresh:[AgentRecord]=[]
        for agent in agents {
            let key=agent.id+"::"+agent.runID+"::"+agent.state.rawValue+"::"+(agent.pendingRequestID ?? "")
            if delivered.insert(key).inserted {fresh.append(agent)}
        }
        guard !fresh.isEmpty else{return}
        if delivered.count>1000 {delivered=[]}
        let sorted=fresh.sorted{$0.attention.rank>$1.attention.rank}
        let agent=sorted[0]
        let key="squad::"+UUID().uuidString
        let content=UNMutableNotificationContent()
        content.title=fresh.count==1 ? (agent.state == .finished ? "Your Pikmin finished a turn":agent.statusLabel) :
            "\(fresh.count) Pikmin have an update"
        content.body=fresh.prefix(3).map(\.title).joined(separator:"\n")
        content.sound=UNNotificationSound(named:UNNotificationSoundName(chirps.filename(agent.state)))
        content.userInfo=["agentID":agent.id]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier:key,content:content,trigger:nil)) {error in
            if let error {Task { @MainActor [weak self] in self?.error=error.localizedDescription}}
        }
    }
}
