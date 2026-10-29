// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import SwiftUI
import Observation

@MainActor @Observable final class ConversationState:Identifiable {
    let id:String
    var agent:AgentRecord
    var lines:[ConversationLine]=[]
    var question:AgentQuestionDocument?
    var selectedAnswers:[String:[String]]=[:]
    var customAnswers:[String:String]=[:]
    var draft=""
    var delivery:MessageDelivery = .nextTurn
    var status="Connecting…"
    var error:String?
    var sending=false
    var loadingQuestion=false
    var editingName=false
    var nameDraft=""
    var partnerID:String?
    var partnerSearch=""
    var choosingPartner=false
    var collaborationDraft=""
    var retryConfirmation=false
    var pinned=false
    var vocalPresentation=false
    var vocalReplying=false
    var vocalHovered=false
    var vocalHeight:CGFloat=140
    var vocalTail=SpeechTail()
    var islandFocused=false
    var lastSequence:Double?
    @ObservationIgnored var streamTask:Task<Void,Never>?
    @ObservationIgnored var streamGeneration:UUID?
    @ObservationIgnored var questionTask:Task<Void,Never>?
    @ObservationIgnored var questionGeneration:UUID?
    @ObservationIgnored var operationTask:Task<Void,Never>?
    @ObservationIgnored var submission:(signature:String,commandID:String,messageID:String)?
    @ObservationIgnored var creation:(kind:String,commandID:String,targetID:String)?
    init(agent:AgentRecord) {id=agent.id;self.agent=agent;if !agent.output.isEmpty {lines=[ConversationLine(id:agent.outputMessageID ?? "recent",role:"assistant",text:agent.output,streaming:agent.outputStreaming)]}}
    var answerPayload:[String:[String]] {
        Dictionary((question?.questions ?? []).map {question in
            let custom=(customAnswers[question.id] ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
            return (question.id,(selectedAnswers[question.id] ?? [])+(custom.isEmpty ? []:[custom]))
        },uniquingKeysWith:{$1})
    }
    var answersReady:Bool {
        guard let question,!question.questions.isEmpty else{return false}
        return question.questions.allSatisfy{$0.required==false || !(answerPayload[$0.id] ?? []).isEmpty}
    }
    func command(for signature:String)->(commandID:String,messageID:String) {
        if let submission,submission.signature==signature {return(submission.commandID,submission.messageID)}
        let ids=(signature,UUID().uuidString,UUID().uuidString);submission=ids
        return(ids.1,ids.2)
    }
    func append(_ line:ConversationLine) {
        if let index=lines.firstIndex(where:{$0.id==line.id}) {lines[index]=line}
        else {lines.append(line)}
        if lines.count>30 {lines=Array(lines.suffix(30))}
    }
    func cancel() {streamTask?.cancel();questionTask?.cancel();operationTask?.cancel();streamTask=nil;questionTask=nil;operationTask=nil;streamGeneration=nil;questionGeneration=nil}
}
