// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import SwiftUI
import Antille

struct SpeechTail:Equatable,Sendable {
    enum Edge:Equatable,Sendable {case top,bottom,left,right}
    var edge:Edge = .bottom
    var position:CGFloat=0.5
    static func aimed(from frame:CGRect,to head:CGRect)->Self {
        if frame.minY>=head.maxY {return Self(edge:.bottom,position:(head.midX-frame.minX)/frame.width)}
        if frame.maxY<=head.minY {return Self(edge:.top,position:(head.midX-frame.minX)/frame.width)}
        return Self(edge:frame.minX>=head.maxX ? .left:.right,position:(frame.maxY-head.midY)/frame.height)
    }
}

enum VocalSpeechTiming {
    static func readingInterval(_ text:String)->Double {min(30,max(10,Double(text.split(whereSeparator:{$0.isWhitespace}).count)/3+4))}
}

/// Automatic dialogue is separate from the full conversation window.
struct VocalSpeechBubble:View {
    @Bindable var model:SquadModel
    @Bindable var state:ConversationState
    let coordinator:ConversationCoordinator
    @State private var outputHeight:CGFloat=48
    @FocusState private var replying:Bool
    private var line:ConversationLine? {state.lines.last(where:{$0.role=="assistant"})}
    private var needsInput:Bool {state.question != nil || state.agent.needsUserInput}
    private var needsReview:Bool {state.agent.state == .waitingApproval}
    private var canWrite:Bool {model.conversationReady && state.agent.isInteractive && !state.agent.stale && !state.sending}
    private var lifetime:SpeechLifetime {SpeechLifetime(line:line,needsInput:needsInput || needsReview,replying:state.vocalReplying,hovered:state.vocalHovered,sending:state.sending,draft:state.draft,error:state.error)}
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            HStack(spacing:8) {
                Text(model.displayName(state.agent)).font(.system(size:10,weight:.medium)).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength:0)
                Button {coordinator.show(state.agent)} label:{Image(systemName:"bubble.left.and.bubble.right").frame(width:20,height:20)}
                    .accessibilityLabel("Open conversation").help("Open conversation")
                Button {coordinator.close(state.id)} label:{Image(systemName:"xmark").frame(width:20,height:20)}
                    .accessibilityLabel("Close speech").help("Close speech")
            }.buttonStyle(.plain).font(.system(size:10))
            FollowingScrollView(revision:SpeechRevision(line:line,question:state.question?.requestId,loading:state.loadingQuestion)) {
                VStack(alignment:.leading,spacing:8) {
                    if state.question != nil {
                        ConversationQuestionForm(model:model,state:state,coordinator:coordinator,compact:true)
                    } else if needsInput {
                        if state.loadingQuestion {ProgressView("Loading question…").controlSize(.small).font(.system(size:11))}
                        else {Text("Open the conversation to answer this request.").font(.system(size:12))}
                    } else if let line {
                        IslandMarkdownText(line.text).id(line.id).font(.system(size:12))
                    }
                }.frame(maxWidth:.infinity,alignment:.leading).fixedSize(horizontal:false,vertical:true)
                    .background(GeometryReader {geometry in Color.clear.preference(key:SpeechOutputHeight.self,value:geometry.size.height)})
            }.frame(height:min(needsInput ? 310:156,max(24,outputHeight))+18)
                .onPreferenceChange(SpeechOutputHeight.self) {height in if abs(outputHeight-height)>1 {outputHeight=height}}
            if let error=state.error {
                Text(error).font(.system(size:11)).foregroundStyle(.orange).textSelection(.enabled)
                Button("Open conversation") {coordinator.show(state.agent)}.controlSize(.small)
            }
            if needsReview {
                Button("Review permission in T3") {model.open(state.agent)}.controlSize(.small)
            } else if !needsInput {
                if state.vocalReplying {
                    TextField("Reply…",text:$state.draft,axis:.vertical).lineLimit(1...3).font(.system(size:12))
                        .textFieldStyle(.roundedBorder).focused($replying)
                        .accessibilityLabel("Reply to "+model.displayName(state.agent))
                        .onSubmit {if canWrite {coordinator.send(state)}}
                    HStack {
                        if state.agent.state.isActive {
                            Picker("Delivery",selection:$state.delivery) {ForEach(MessageDelivery.allCases) {Text($0.rawValue).tag($0)}}.labelsHidden().frame(width:112)
                        }
                        Spacer()
                        Button(state.sending ? "Sending…":"Send") {coordinator.send(state)}
                            .disabled(!canWrite || state.draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                            .keyboardShortcut(.return,modifiers:.command)
                    }.controlSize(.small)
                } else if line?.streaming==true {
                    HStack(spacing:5) {ProgressView().controlSize(.mini);Text("Speaking…").font(.system(size:10)).foregroundStyle(.secondary)}
                } else if line != nil {
                    Button {coordinator.beginSpeechReply(state)} label:{Label("Reply",systemImage:"arrowshape.turn.up.left")}
                        .buttonStyle(.plain).font(.system(size:11)).disabled(!canWrite)
                }
            }
        }.padding(12)
            .padding(.top,state.vocalTail.edge == .top ? 8:0)
            .padding(.bottom,state.vocalTail.edge == .bottom ? 8:0)
            .padding(.leading,state.vocalTail.edge == .left ? 8:0)
            .padding(.trailing,state.vocalTail.edge == .right ? 8:0)
            .background(SpeechBalloon(tail:state.vocalTail).fill(Color(nsColor:.windowBackgroundColor)))
            .padding(4).fixedSize(horizontal:false,vertical:true)
            .background(GeometryReader {geometry in Color.clear.preference(key:SpeechHeight.self,value:geometry.size.height)})
            .onPreferenceChange(SpeechHeight.self) {coordinator.resizeSpeech(state,height:$0)}
            .onHover {state.vocalHovered=$0}
            .onTapGesture {coordinator.focusSpeech(state)}
            .task(id:state.vocalReplying) {
                await Task.yield()
                guard !Task.isCancelled else{return};replying=state.vocalReplying
            }
            .task(id:lifetime) {
                guard let line,canDismiss else{return}
                do {try await Task.sleep(for:coordinator.readingInterval(for:line.text))} catch{return}
                guard !Task.isCancelled,canDismiss else{return}
                coordinator.expireSpeech(state,messageID:line.id)
            }
    }
    private var canDismiss:Bool {!needsInput && !needsReview && line?.streaming==false && !state.vocalReplying && !state.vocalHovered && !state.sending && state.draft.isEmpty && state.error==nil}
}

private struct SpeechRevision:Equatable {var line:ConversationLine?;var question:String?;var loading:Bool}
private struct SpeechLifetime:Equatable {var line:ConversationLine?;var needsInput:Bool;var replying:Bool;var hovered:Bool;var sending:Bool;var draft:String;var error:String?}
private struct SpeechOutputHeight:PreferenceKey {static let defaultValue:CGFloat=0;static func reduce(value:inout CGFloat,nextValue:()->CGFloat) {value=max(value,nextValue())}}
private struct SpeechHeight:PreferenceKey {static let defaultValue:CGFloat=0;static func reduce(value:inout CGFloat,nextValue:()->CGFloat) {value=max(value,nextValue())}}

private struct SpeechBalloon:Shape {
    var tail:SpeechTail
    func path(in rect:CGRect)->Path {
        var body=rect
        switch tail.edge {
        case .top:body.origin.y+=8;body.size.height-=8
        case .bottom:body.size.height-=8
        case .left:body.origin.x+=8;body.size.width-=8
        case .right:body.size.width-=8
        }
        var path=Path(roundedRect:body,cornerRadius:14)
        let x=max(body.minX+20,min(body.maxX-20,rect.width*tail.position))
        let y=max(body.minY+20,min(body.maxY-20,rect.height*tail.position))
        switch tail.edge {
        case .bottom:path.move(to:CGPoint(x:x-7,y:body.maxY-1));path.addLine(to:CGPoint(x:x,y:rect.maxY));path.addLine(to:CGPoint(x:x+7,y:body.maxY-1))
        case .top:path.move(to:CGPoint(x:x-7,y:body.minY+1));path.addLine(to:CGPoint(x:x,y:rect.minY));path.addLine(to:CGPoint(x:x+7,y:body.minY+1))
        case .left:path.move(to:CGPoint(x:body.minX+1,y:y-7));path.addLine(to:CGPoint(x:rect.minX,y:y));path.addLine(to:CGPoint(x:body.minX+1,y:y+7))
        case .right:path.move(to:CGPoint(x:body.maxX-1,y:y-7));path.addLine(to:CGPoint(x:rect.maxX,y:y));path.addLine(to:CGPoint(x:body.maxX-1,y:y+7))
        }
        path.closeSubpath();return path
    }
}
