// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import SwiftUI
import AppKit
import Antille

struct ConversationBubble:View {
    @Bindable var model:SquadModel
    @Bindable var state:ConversationState
    let coordinator:ConversationCoordinator
    @FocusState private var editingName:Bool
    @GestureState private var resizing=false
    private var agent:AgentRecord {state.agent}
    private var canWrite:Bool {model.conversationReady && agent.isInteractive && !agent.stale && !state.sending}
    private var displayedLines:[ConversationLine] {state.lines}
    var body:some View {
        if state.vocalPresentation {VocalSpeechBubble(model:model,state:state,coordinator:coordinator)}
        else {conversation}
    }
    private var conversation:some View {
        VStack(spacing:0) {
            header
            if state.editingName {
                HStack {
                    TextField("Pikmin name",text:$state.nameDraft).textFieldStyle(.roundedBorder).focused($editingName)
                        .onSubmit(saveName)
                    Button("Save",action:saveName).keyboardShortcut(.return,modifiers:[])
                }.padding(.horizontal,14).padding(.bottom,10)
                .onAppear {editingName=true}
            }
            if state.choosingPartner {partnerPicker}
            if let partner=partner {collaboration(partner)}
            FollowingScrollView(revision:TranscriptRevision(lines:displayedLines,questionID:state.question?.requestId,loadingQuestion:state.loadingQuestion)) {
                    VStack(alignment:.leading,spacing:12) {
                        if state.lines.isEmpty && state.question==nil {
                            Text(agent.isInteractive ? "Waiting for this agent’s output…":"Live output is unavailable from this connection.")
                                .font(.system(size:12)).foregroundStyle(.secondary).padding(.vertical,16)
                        }
                        ForEach(displayedLines) {line in
                            VStack(alignment:.leading,spacing:4) {
                                if line.role=="user" {Text("You").font(.system(size:10,weight:.semibold)).foregroundStyle(.secondary)}
                                IslandMarkdownText(line.text,fadesChanges:line.role=="assistant").font(.system(size:12)).frame(maxWidth:.infinity,alignment:.leading)
                                if line.streaming {HStack(spacing:5) {ProgressView().controlSize(.mini);Text("Writing").font(.system(size:10)).foregroundStyle(.secondary)}}
                            }.padding(line.role=="user" ? 10:0)
                                .background(line.role=="user" ? Color.primary.opacity(0.045):.clear,in:RoundedRectangle(cornerRadius:10))
                                .id(line.id)
                        }
                        if state.loadingQuestion {ProgressView("Loading question…").font(.system(size:11))}
                        if state.question != nil {ConversationQuestionForm(model:model,state:state,coordinator:coordinator)}
                        if agent.state == .waitingApproval {
                            Label("This agent needs permission in T3.",systemImage:"hand.raised").font(.system(size:11))
                            Button("Review in T3") {model.open(agent)}.controlSize(.small)
                        }
                    }.padding(12)
            }
            if let error=state.error {
                HStack(alignment:.top) {Image(systemName:"exclamationmark.circle");Text(error).textSelection(.enabled);Spacer(minLength:0);Button {state.error=nil} label:{Image(systemName:"xmark")}.buttonStyle(.plain).help("Dismiss message")}
                    .font(.system(size:11)).foregroundStyle(.orange).padding(.horizontal,14).padding(.vertical,8)
            }
            if agent.isInteractive && !model.conversationReady {
                HStack {
                    Text(model.connecting ? "Connecting to T3…":"Reconnect T3 to reply.").font(.system(size:11)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Reconnect T3") {model.connect()}.disabled(model.connecting)
                }.padding(14).frame(maxWidth:.infinity,alignment:.leading)
            }
            if state.question==nil && partner==nil {composer}
            footer
        }
        .background(Color(nsColor:.windowBackgroundColor),in:RoundedRectangle(cornerRadius:18))
        .overlay(RoundedRectangle(cornerRadius:18).strokeBorder(.primary.opacity(0.08),lineWidth:0.5))
        .padding(4)
        .task(id:[state.question != nil || agent.needsUserInput,state.choosingPartner,state.partnerID != nil,state.draft.isEmpty,state.editingName]) {
            await Task.yield()
            guard !Task.isCancelled else{return}
            coordinator.resizeForContent(state)
        }
        .confirmationDialog("Retry the last instruction?",isPresented:$state.retryConfirmation,titleVisibility:.visible) {
            Button("Retry as a new turn") {coordinator.retry(state)}
            Button("Cancel",role:.cancel) {}
        } message:{Text("The existing conversation stays intact.")}
        .onChange(of:resizing) {_,active in if !active {coordinator.finishConversationResize(state)}}
    }
    private var header:some View {
        HStack(spacing:9) {
            PikminHead(species:model.species(for:agent),mood:agent.mood,growth:model.growth,animated:agent.needsUserInput && !model.attending.contains(agent.id),focusGaze:model.attentionGazes[agent.id],appearance:model.look(for:agent)).frame(width:29,height:35)
            VStack(alignment:.leading,spacing:3) {
                Button {state.nameDraft=model.displayName(agent);state.editingName.toggle()} label:{Text(model.displayName(agent)).font(.system(size:12,weight:.semibold)).lineLimit(2).frame(maxWidth:.infinity,alignment:.leading)}.buttonStyle(.plain).help("Rename Pikmin")
                Text(agent.stale ? "Source disconnected":agent.statusLabel).font(.system(size:10)).foregroundStyle(.secondary)
            }
            Menu {
                Button("Rename Pikmin…") {state.nameDraft=model.displayName(agent);state.editingName=true}
                Button("Collaborate…") {state.choosingPartner=true}.disabled(!agent.isInteractive)
                Toggle("Vocal mode",isOn:Binding(get:{model.vocal.contains(agent.id)},set:{model.setVocalMode($0,for:agent)})).disabled(!agent.isInteractive)
                Divider()
                Button("Retry last instruction…") {state.retryConfirmation=true}.disabled(!canWrite || agent.state.isActive)
                Button("Fork conversation") {coordinator.create(state,fork:true)}.disabled(!canWrite)
                Button("New conversation") {coordinator.create(state,fork:false)}.disabled(!canWrite)
                Button("Stop agent") {coordinator.stop(state)}.disabled(!canWrite || !agent.state.isActive)
                Divider()
                Button(model.docked.contains(agent.id) ? "To desktop":"Dismiss to island") {model.docked.contains(agent.id) ? model.undock(agent):model.dismiss(agent)}
                Button("Open full conversation") {model.open(agent)}
            } label:{Image(systemName:"ellipsis").frame(width:24,height:24)}.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Conversation actions").help("Conversation actions")
            Button {state.pinned.toggle()} label:{Image(systemName:state.pinned ? "pin.fill":"pin").frame(width:24,height:24)}.buttonStyle(.plain).accessibilityLabel(state.pinned ? "Unpin bubble":"Keep bubble open").help(state.pinned ? "Unpin bubble":"Keep bubble open")
            Button {coordinator.close(state.id)} label:{Image(systemName:"xmark").frame(width:24,height:24)}.buttonStyle(.plain).accessibilityLabel("Close bubble").help("Close bubble")
        }.padding(.horizontal,12).padding(.top,10).padding(.bottom,8)
    }
    private var composer:some View {
        VStack(alignment:.leading,spacing:6) {
                TextField("Reply…",text:$state.draft,axis:.vertical).font(.system(size:12)).lineLimit(1...3).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Message to "+model.displayName(agent))
                    .onSubmit {if canWrite {coordinator.send(state)}}
            HStack {
                if agent.state.isActive {Picker("Delivery",selection:$state.delivery) {ForEach(MessageDelivery.allCases) {Text($0.rawValue).tag($0)}}.labelsHidden().frame(width:130)}
                Spacer()
                Button(agent.state.isActive && state.delivery == .nextTurn ? "Queue":"Send") {coordinator.send(state)}
                    .keyboardShortcut(.return,modifiers:.command)
                    .disabled(!canWrite || state.draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
            }.controlSize(.small)
        }.padding(.horizontal,12).padding(.bottom,8)
    }
    private var partner:AgentRecord? {state.partnerID.flatMap{id in model.records.first{$0.id==id}}}
    private var partnerPicker:some View {
        VStack(alignment:.leading,spacing:8) {
            HStack {Text("Choose a collaborator").font(.system(size:12,weight:.semibold));Spacer();Button {state.choosingPartner=false} label:{Image(systemName:"xmark")}.buttonStyle(.plain).help("Close collaborator picker")}
            TextField("Find a Pikmin",text:$state.partnerSearch).textFieldStyle(.roundedBorder)
            ScrollView {
                VStack(spacing:4) {
                    ForEach(Array(model.listed.filter{$0.id != agent.id && $0.isInteractive && (state.partnerSearch.isEmpty || model.displayName($0).localizedCaseInsensitiveContains(state.partnerSearch))}.prefix(20))) {other in
                        Button {state.partnerID=other.id;state.choosingPartner=false} label:{HStack {PikminHead(species:model.species(for:other),mood:other.mood,growth:model.growth,animated:false,appearance:model.look(for:other)).frame(width:24,height:29);Text(model.displayName(other)).lineLimit(2);Spacer()}}.buttonStyle(.plain).font(.system(size:11)).padding(.vertical,3)
                    }
                }
            }.frame(maxHeight:160)
        }.padding(14)
    }
    private func collaboration(_ partner:AgentRecord)->some View {
        VStack(alignment:.leading,spacing:9) {
            HStack {
                Image(systemName:"link").foregroundStyle(.secondary)
                Text("Work with "+model.displayName(partner)).font(.system(size:12,weight:.semibold)).lineLimit(2)
                Spacer();Button {state.partnerID=nil} label:{Image(systemName:"xmark")}.buttonStyle(.plain).help("Cancel collaboration")
            }
            TextField("What should they work on together?",text:$state.collaborationDraft,axis:.vertical).textFieldStyle(.roundedBorder).lineLimit(2...6)
            HStack {
                if agent.state.isActive {Picker("Delivery",selection:$state.delivery) {ForEach(MessageDelivery.allCases) {Text($0.rawValue).tag($0)}}.labelsHidden().frame(width:130)}
                Spacer()
                Button(agent.state.isActive && state.delivery == .nextTurn ? "Queue collaboration":"Collaborate") {coordinator.collaborate(state)}.disabled(!canWrite || state.collaborationDraft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
            }.controlSize(.small)
        }.padding(12).background(.primary.opacity(0.045),in:RoundedRectangle(cornerRadius:12)).padding(.horizontal,14).padding(.bottom,8)
    }
    private var footer:some View {
        HStack(spacing:7) {
            Text(state.status).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(1)
            if state.sending {ProgressView().controlSize(.mini)}
            Spacer()
            if state.status=="Disconnected" {Button("Reconnect") {coordinator.reconnect(state)}.controlSize(.mini)}
            Button {model.open(agent)} label:{Image(systemName:"arrow.up.forward.app")}.buttonStyle(.plain).accessibilityLabel("Open in T3").help("Open in T3")
            Button {coordinator.growConversation(state)} label:{Image(systemName:"arrow.up.left.and.arrow.down.right").frame(width:20,height:20)}
                .buttonStyle(.plain).accessibilityLabel("Resize conversation").help("Drag to resize; click to make larger")
                .highPriorityGesture(DragGesture(minimumDistance:2,coordinateSpace:.global)
                    .updating($resizing) {_,active,_ in active=true}
                    .onChanged {coordinator.resizeConversation(state,translation:$0.translation)}
                    .onEnded {_ in coordinator.finishConversationResize(state)})
        }.padding(.horizontal,12).padding(.bottom,8)
    }
    private func saveName() {model.rename(agent,to:state.nameDraft);state.editingName=false}
}

private struct TranscriptRevision:Equatable {
    let lines:[ConversationLine]
    let questionID:String?
    let loadingQuestion:Bool
}
