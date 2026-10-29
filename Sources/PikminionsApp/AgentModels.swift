// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Foundation
import Antille

enum AgentState:String,CaseIterable,Codable,Sendable {
    case starting,queued,working,waitingInput,waitingApproval,finished,failed,interrupted,idle,recorded
    var label:String {
        switch self {
        case .starting:"Starting";case .queued:"Queued";case .working:"Working";case .waitingInput:"Needs your answer"
        case .waitingApproval:"Needs approval";case .finished:"Turn finished";case .failed:"Failed"
        case .interrupted:"Interrupted";case .idle:"Idle";case .recorded:"Recorded history"
        }
    }
    var attention:IslandAttention {
        switch self {case .waitingInput,.waitingApproval:.needsAttention;case .failed:.error;case .finished:.information;default:.none}
    }
    var mood:PikminMood {
        switch self {case .working,.starting:.working;case .waitingInput:.question;case .waitingApproval,.failed:.attention
        case .finished:.happy;case .recorded:.disconnected;case .idle,.queued,.interrupted:.calm}
    }
    var presentationRank:Int {
        switch self {case .waitingInput,.waitingApproval:5;case .failed:4;case .working,.starting:3;case .queued:2;case .finished:1;case .idle,.interrupted:0;case .recorded: -1}
    }
    var isActive:Bool { [.starting,.working,.waitingInput,.waitingApproval,.queued].contains(self) }
}
struct AgentRecord:Identifiable,Equatable,Sendable {
    var id:String
    var nativeID:String?
    var source:String
    var threadID:String
    var runID:String
    var title:String
    var project:String
    var model:String
    var state:AgentState
    var detail:String
    var parentID:String?
    var updated:Date
    var openURL:URL?
    var stale:Bool = false
    var silent:Bool = false
    var pendingRequestID:String?
    var pendingRequestKind:String?
    var pendingRequestBlocking:Bool?
    var output:String = ""
    var projectID:String?
    var outputMessageID:String?
    var outputStreaming=false
    var outputHistorical=false
    var outputUnavailable=false
    var needsUserInput:Bool {state == .waitingInput || (pendingRequestKind=="user_input" && pendingRequestID != nil)}
    var attention:IslandAttention {needsUserInput ? .needsAttention:state.attention}
    var mood:PikminMood {needsUserInput ? .question:state.mood}
    var presentationRank:Int {needsUserInput ? 5:state.presentationRank}
    var statusLabel:String {needsUserInput ? (state == .working ? "Working · needs your answer":"Needs your answer"):state.label}
    var isInteractive:Bool {source=="T3" || source=="Fixture"}
    var projectKey:String {source+"::"+(projectID ?? project)}
    var isCompactEligible:Bool {!stale && (state.isActive || needsUserInput)}
}
/// Newly observed runs lead older ones. Message timestamps do not move an
/// already-running head under the pointer; a new run or restart can promote it.
struct ActiveAgentOrder {
    private var runIDs:[String:String]=[:]
    private var ids:[String]=[]
    mutating func reconcile(_ records:[AgentRecord]) {
        let active=records.filter(\.isCompactEligible)
        let current=Dictionary(active.map{($0.id,$0.runID)},uniquingKeysWith:{$1})
        let retained=ids.filter{current[$0] != nil && current[$0]==runIDs[$0]}
        let known=Set(retained)
        let added=active.filter{!known.contains($0.id)}.sorted {
            $0.updated == $1.updated ? $0.id<$1.id:$0.updated>$1.updated
        }
        ids=added.map(\.id)+retained;runIDs=current
    }
    func rank(_ id:String)->Int {ids.firstIndex(of:id).map{ids.count-$0} ?? 0}
    func priorities(for agents:[AgentRecord])->[String:Int] {
        let eligible=Set(agents.filter(\.isCompactEligible).map(\.id))
        let ordered=ids.filter{eligible.contains($0)}
        return Dictionary(ordered.enumerated().map{($0.element,ordered.count-$0.offset)},uniquingKeysWith:{$1})
    }
}
struct SuccessEvent:Identifiable,Equatable,Sendable {var id:String;var started:Date}
enum SourceFailure:LocalizedError,Sendable {
    case message(String)
    var errorDescription:String? { if case .message(let message)=self {message} else {nil} }
}
struct T3Shell:Decodable,Sendable {
    var schemaVersion:Int
    var snapshotSequence:Int
    var projects:[Project]
    var threads:[Thread]
    struct Project:Decodable,Sendable {var id:String;var title:String;var workspaceRoot:String}
    struct Thread:Decodable,Sendable {
        var id:String;var projectId:String;var title:String
        var status:String;var updatedAt:String
        var activeProviderThreadId:String?
        var latestRunId:String?;var activeRunId:String?;var activityRunStatus:String?
        var latestRunCompletedAt:String?;var latestRunSilent:Bool?;var latestRunStopRequested:Bool?
        var archivedAt:String?;var deletedAt:String?
        var lineage:Lineage?
        var pendingRuntimeRequest:Pending?
        var pendingBackgroundTasks:[Background]?
        var modelSelection:Model?
        var latestVisibleMessage:Message?
    }
    struct Lineage:Decodable,Sendable {var parentThreadId:String?;var relationshipToParent:String?}
    struct Pending:Decodable,Sendable {var id:String;var kind:String;var blocking:Bool?}
    struct Background:Decodable,Sendable {var kind:String;var awaited:Bool?}
    struct Model:Decodable,Sendable {var model:String}
    struct Message:Decodable,Sendable {var id:String;var role:String;var text:String;var streaming:Bool?}
}
func agentDate(_ text:String?) -> Date {
    guard let text else { return .distantPast }
    let formatter=ISO8601DateFormatter();formatter.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
    if let date=formatter.date(from:text) { return date }
    formatter.formatOptions=[.withInternetDateTime]
    return formatter.date(from:text) ?? .distantPast
}
func mappedT3State(_ thread:T3Shell.Thread)->AgentState {
    let status=thread.activityRunStatus ?? thread.status
    if let pending=thread.pendingRuntimeRequest {
        if pending.kind=="user_input" && (pending.blocking != false || !["preparing","starting","running"].contains(status)) { return .waitingInput }
        if ["command","file-read","file-change","mcp-elicitation","permission"].contains(pending.kind) { return .waitingApproval }
    }
    switch status {
    case "preparing","starting":return .starting
    case "running","waiting":return .working
    case "queued":return .queued
    case "completed":
        let held=(thread.pendingBackgroundTasks ?? []).contains{$0.awaited==true || ["subagent","background_task"].contains($0.kind)}
        return held ? .working : .finished
    case "failed":return .failed
    case "interrupted","cancelled","rolled_back":return .interrupted
    default:return .idle
    }
}
