// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import SwiftUI
@testable import PikminionsApp

/// The real bubble with synthetic history; no model.start(), sockets or live access.
@MainActor final class BubbleFixtureModel:ObservableObject {
    let model:SquadModel
    let coordinator:ConversationCoordinator
    let state:ConversationState
    private var sequence=24
    private var speechFeed:Task<Void,Never>?
    private var speechSequence=0.0
    private var speechChunk=0
    private let speechParts=["I’m keeping **P**"," as the buy button,"," and adding"," the missing touch controls."]
    @Published var showingPanel=false
    init() {
        let model=SquadModel()
        model.mode = .desktop
        let agent=AgentRecord(id:"t3:fixture-worker",source:"Fixture",threadID:"fixture-worker",runID:"fixture-run-worker",title:"Fixture · Compact chat",project:"Fixture",model:"Sample data",state:.working,detail:"Sample output",updated:.now,openURL:nil)
        let partner=AgentRecord(id:"t3:fixture-partner",source:"Fixture",threadID:"fixture-partner",runID:"fixture-run-partner",title:"Fixture · Collaborator",project:"Fixture",model:"Sample data",state:.working,detail:"Sample collaboration partner",updated:.now,openURL:nil)
        model.records=[agent,partner];model.conversationReady=true;model.speciesOverrides[agent.id]="winged"
        let coordinator=ConversationCoordinator(model:model,observesSources:false,speechReadingInterval:{_ in .seconds(120)})
        model.conversationCoordinator=coordinator
        let state=coordinator.state(for:agent)
        state.lines=(1...24).map{ConversationLine(id:"sample-\($0)",role:"assistant",text:"Sample message \($0). "+String(repeating:"A little update from your agent. ",count:3))}
        state.status="Fixture · sample data"
        self.model=model;self.coordinator=coordinator;self.state=state
    }
    func append() {
        sequence+=1
        state.append(ConversationLine(id:"sample-\(sequence)",role:"assistant",text:"Latest sample message \(sequence). New output should follow only when you are at the end."))
    }
    func extend() {
        guard let index=state.lines.lastIndex(where:{$0.role=="assistant"}) else{return}
        state.lines[index].text+="\n"+String(repeating:"A streamed chunk continues the existing message. ",count:4)
        state.lines[index].streaming=true
    }
    func markdown() {
        state.question=nil;state.agent.state = .working
        state.lines=[ConversationLine(id:"sample-markdown",role:"assistant",text:"""
        # Sample output

        Spelunky uses **P** to buy items. Preserve _that binding_ and use `pause()` in the toolbar.

        - Keep **keyboard controls**.
        - Add a [small disclosure](https://example.invalid).

        ```swift
        let binding = "P"
        """,streaming:true)]
    }
    func completeMarkdown() {
        guard let index=state.lines.firstIndex(where:{$0.id=="sample-markdown"}) else{return}
        state.lines[index].text+="\nlet paused = true\n```\n\n| Input | Action |\n| --- | --- |\n| **P** | Buy |\n| `Esc` | Pause |\n\n**Stream complete.**"
        state.lines[index].streaming=false
    }
    func playSpeech() {
        showingPanel=true
        state.question=nil;state.agent.state = .working
        sequence+=1;speechChunk=1;state.lines=[]
        model.hidden=[];model.docked=[];model.vocal=[state.id]
        emitSpeech(complete:false)
        coordinator.focusSpeech(state)
        speechFeed?.cancel()
    }
    func previewSpeech() {
        coordinator.close(state.id);speechFeed?.cancel()
        model.vocal=[];showingPanel=false;state.question=nil;state.agent.state = .working
        sequence+=1;speechChunk=1;state.lines=[];state.vocalPresentation=true;emitSpeech(complete:false)
    }
    func appendSpeech(poll:Bool=false) {
        speechChunk=min(speechParts.count,speechChunk+1)
        if poll {
            coordinator.receiveOutput(state.agent,line:ConversationLine(id:"speech-\(sequence)",role:"assistant",text:speechParts.prefix(speechChunk).joined(),streaming:true),historical:false)
        } else {emitSpeech(complete:false)}
    }
    func emitSpeech(complete:Bool) {
        speechSequence+=1
        var payload:[String:JSONValue]=["text":.string(speechParts.prefix(speechChunk).joined()),"streaming":.bool(!complete),"threadId":.string(state.agent.threadID)]
        if complete {payload["id"] = .string("speech-\(sequence)");payload["role"] = .string("assistant")}
        else {payload["id"] = .string("item-speech-\(sequence)");payload["messageId"] = .string("speech-\(sequence)");payload["type"] = .string("assistant_message")}
        coordinator.applyStreamItem(.object(["kind":.string("event"),"sequence":.number(speechSequence),"event":.object(["type":.string(complete ? "message.updated":"turn-item.updated"),"payload":.object(payload)])]),to:state)
    }
    func completeSpeech() {
        speechFeed?.cancel();speechChunk=speechParts.count;emitSpeech(complete:true)
    }
    func toggleQuestion() {
        if showingPanel {coordinator.close(state.id);showingPanel=false}
        if state.question != nil {state.question=nil;state.agent.state = .working;return}
        state.question=AgentQuestionDocument(requestId:"fixture-request",questions:[AgentQuestion(id:"fixture-choice",header:"Sample choice",question:"Which sample approach should this Pikmin use?",options:[.init(label:"Keep it small",description:"Use the compact sample layout."),.init(label:"Show more detail",description:"Use the expanded sample layout.")],allowCustomAnswer:true)])
        state.agent.state = .waitingInput
    }
}
@main struct BubbleFixture:App {
    @StateObject private var fixture=BubbleFixtureModel()
    var body:some Scene {
        Window("Pikminions Bubble Fixture",id:"bubble") {
            VStack(spacing:10) {
                if fixture.showingPanel {Text("Interact with the floating sample speech panel.").font(.caption).frame(width:320,height:100)}
                else {
                    ConversationBubble(model:fixture.model,state:fixture.state,coordinator:fixture.coordinator)
                        .frame(width:fixture.coordinator.bubbleSize(fixture.state).width,height:fixture.coordinator.bubbleSize(fixture.state).height)
                }
                HStack {
                    Button("Append output"){fixture.append()}
                    Button("Sample question"){fixture.toggleQuestion()}
                }.controlSize(.small).padding(.bottom,10)
            }.preferredColorScheme(.dark)
        }.defaultSize(width:320,height:366)
            .commands {
                CommandMenu("Fixture") {
                    Button("Extend latest output"){fixture.extend()}
                    Button("Show Markdown sample"){fixture.markdown()}
                    Button("Complete Markdown stream"){fixture.completeMarkdown()}
                    Button("Play speech panel"){fixture.playSpeech()}
                    Button("Preview streamed speech"){fixture.previewSpeech()}
                    Button("Append speech chunk"){fixture.appendSpeech()}.keyboardShortcut("n",modifiers:[.command,.shift])
                    Button("Append speech from poll"){fixture.appendSpeech(poll:true)}.keyboardShortcut("p",modifiers:[.command,.shift])
                    Button("Focus speech panel"){fixture.coordinator.focusSpeech(fixture.state)}
                    Button("Complete speech"){fixture.completeSpeech()}.keyboardShortcut("e",modifiers:[.command,.shift])
                    Toggle("Compact vocal presentation",isOn:Binding(get:{fixture.state.vocalPresentation},set:{fixture.state.vocalPresentation=$0}))
                }
            }
    }
}
