// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import SwiftUI

struct ConversationQuestionForm:View {
    @Bindable var model:SquadModel
    @Bindable var state:ConversationState
    let coordinator:ConversationCoordinator
    var compact=false
    private var canWrite:Bool {model.conversationReady && state.agent.isInteractive && !state.agent.stale && !state.sending}
    var body:some View {
        if let document=state.question {
            VStack(alignment:.leading,spacing:compact ? 10:14) {
                if !compact {Label("Your Pikmin has a question",systemImage:"questionmark.bubble").font(.system(size:12,weight:.semibold))}
                ForEach(document.questions) {question in
                    VStack(alignment:.leading,spacing:8) {
                        Text(question.question).font(.system(size:12)).textSelection(.enabled)
                        if question.multiSelect==true {
                            ForEach(Array(question.options.enumerated()),id:\.offset) {_,option in
                                let value=option.value ?? option.label
                                Toggle(isOn:Binding(get:{state.selectedAnswers[question.id]?.contains(value)==true},set:{selected in
                                    var values=state.selectedAnswers[question.id] ?? [];values.removeAll{$0==value};if selected {values.append(value)};state.selectedAnswers[question.id]=values
                                })) {optionLabel(option)}.toggleStyle(.checkbox)
                            }
                        } else if !question.options.isEmpty {
                            Picker(question.header,selection:Binding(get:{state.selectedAnswers[question.id]?.first ?? ""},set:{state.selectedAnswers[question.id]=[$0];state.customAnswers[question.id]=""})) {
                                ForEach(Array(question.options.enumerated()),id:\.offset) {_,option in optionLabel(option).tag(option.value ?? option.label)}
                            }.pickerStyle(.radioGroup).labelsHidden()
                        }
                        if question.options.isEmpty || question.allowCustomAnswer != false {
                            TextField(question.options.isEmpty ? "Your answer":"Or write an answer",text:Binding(get:{state.customAnswers[question.id] ?? ""},set:{state.customAnswers[question.id]=$0;if question.multiSelect != true {state.selectedAnswers[question.id]=[]}}),axis:.vertical)
                                .textFieldStyle(.roundedBorder).lineLimit(1...5)
                        }
                    }
                }
                Button(state.sending ? "Sending…":"Send answer") {coordinator.answer(state)}.disabled(!canWrite || !state.answersReady).controlSize(.small)
            }.padding(compact ? 0:12).background(compact ? Color.clear:Color.primary.opacity(0.045),in:RoundedRectangle(cornerRadius:12))
        }
    }
    private func optionLabel(_ option:AgentQuestion.Option)->some View {
        VStack(alignment:.leading,spacing:2) {Text(option.label).font(.system(size:11,weight:.medium));if !option.description.isEmpty {Text(option.description).font(.system(size:10)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)}}
    }
}
