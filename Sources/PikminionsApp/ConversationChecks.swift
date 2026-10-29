// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Foundation

/// Source-boundary check with the existing in-memory fixture. No credentials,
/// network, notifications, live threads, or native windows are involved.
func runFixtureConversationChecks() async throws {
    guard AppRuntime.fixture else {throw SourceFailure.message("Conversation checks require --fixture.")}
    let source=AgentSources()
    try await source.loadSavedAccess()
    guard await source.connected,await source.canOperate else {throw SourceFailure.message("Fixture startup did not prepare conversation access.")}
    try await source.disconnectT3()
    guard await !source.connected,await !source.canOperate else {throw SourceFailure.message("Disconnect did not remove conversation access.")}
    try await source.connectT3()
    guard await source.canOperate,let agent=try await source.t3().first(where:{$0.pendingRequestID != nil}) else {throw SourceFailure.message("Connect did not restore replies and questions automatically.")}
    let document=try await source.questions(for:agent)
    let answers=Dictionary(uniqueKeysWithValues:document.questions.map{($0.id,[$0.options.first?.label ?? "Sample answer"])})
    try await source.answer(agent,requestID:document.requestId,answers:answers,commandID:UUID().uuidString)
    try await source.send(agent,text:"Sample vocal reply",delivery:.nextTurn,commandID:UUID().uuidString,messageID:UUID().uuidString)
    let deadline=Date.now.addingTimeInterval(4)
    var received=false
    while Date.now<deadline {
        let lines=try await source.conversation(for:agent)
        if lines.last?.role=="assistant",lines.last?.streaming==false,lines.last?.text.contains("Sample vocal reply")==true {received=true;break}
        try await Task.sleep(for:.milliseconds(60))
    }
    try await source.disconnectT3()
    guard received else {throw SourceFailure.message("The automatic-access fixture did not complete its reply.")}
    print("PASS: conversation access on startup/reconnect, immediate question answering and replies without an enable step, and revoked access on disconnect.")
}
