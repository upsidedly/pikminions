// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Foundation

/// Explicitly invoked integration canary. It requires an allowlisted manifest,
/// short-lived RAM credentials, labeled test threads, and bounded waits. No
/// credential or unrelated conversation content is written to its report.
enum LiveCanary {
    struct Manifest:Codable {
        var inputID:String
        var partnerID:String
        var forkID:String
        var freshID:String
        var checks:[String]=[]
    }
    static func run(arguments:[String]) async throws {
        guard !AppRuntime.fixture,let index=arguments.firstIndex(of:"--live-canary"),arguments.count>index+1 else {
            throw SourceFailure.message("Supply a live-canary manifest to the normal executable.")
        }
        let url=URL(fileURLWithPath:arguments[index+1])
        var manifest=try JSONDecoder().decode(Manifest.self,from:Data(contentsOf:url))
        manifest.checks=manifest.checks.reduce(into:[]){if !$0.contains($1) {$0.append($1)}}
        guard Set([manifest.inputID,manifest.partnerID,manifest.forkID,manifest.freshID]).count==4 else {throw SourceFailure.message("The four canary identities must be distinct.")}
        let source=AgentSources(ephemeralCredentials:true)
        func record(_ label:String) throws {
            if !manifest.checks.contains(label) {manifest.checks.append(label)}
            let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
            try encoder.encode(manifest).write(to:url,options:.atomic)
            print("PASS: "+label);fflush(stdout)
        }
        func agent(_ id:String) async throws ->AgentRecord {
            guard let value=try await source.t3().first(where:{$0.threadID==id}),value.title.hasPrefix("Pikminions TEST - ") else {
                throw SourceFailure.message("A canary identity is missing or does not have the required test label.")
            }
            return await source.recentOutputs(for:[value]).first ?? value
        }
        func wait(_ id:String,seconds:Double=75,_ condition:(AgentRecord)->Bool) async throws ->AgentRecord {
            let deadline=Date.now.addingTimeInterval(seconds)
            while Date.now<deadline {
                try Task.checkCancellation()
                let value=try await agent(id)
                if condition(value) {return value}
                if value.state == .failed {throw SourceFailure.message("A labeled canary run failed.")}
                try await Task.sleep(for:.seconds(1))
            }
            throw SourceFailure.message("A labeled canary did not reach its expected state within the bounded wait.")
        }
        do {
            try await source.connectT3()
            if arguments.contains("--inspect-canary") {
                for id in [manifest.inputID,manifest.partnerID] {
                    let value=try await agent(id)
                    let diagnostics=try await source.canaryDiagnostics(value)
                    let lines=try await source.conversation(for:value)
                    print(value.title+": state="+value.state.rawValue+", outputChars="+String(value.output.count)+", messages="+String(lines.count))
                    print(String(decoding:try JSONEncoder().encode(diagnostics),as:UTF8.self))
                }
                try await source.disconnectT3();return
            }
            var input=try await agent(manifest.inputID)
            var partner=try await agent(manifest.partnerID)
            try record("read and command sessions connected with RAM-only 10-minute credentials")

            if !manifest.checks.contains("actual message dispatch, completed output, and duplicate-command suppression") {
            let initial="This is an isolated Pikminions integration test. Do not edit files, browse, launch agents or threads, or request credentials. Reply exactly: ACCEPT pikminions-partner-ready. For later sample ping messages, reply exactly ACCEPT pikminions-partner-pong."
            let previousPartnerMessage=partner.outputMessageID
            let commandID=UUID().uuidString,messageID=UUID().uuidString
            try await source.send(partner,text:initial,delivery:.nextTurn,commandID:commandID,messageID:messageID)
            try await source.send(partner,text:initial,delivery:.nextTurn,commandID:commandID,messageID:messageID)
            partner=try await wait(manifest.partnerID) {$0.outputMessageID != previousPartnerMessage && $0.output.contains("ACCEPT pikminions-partner-ready") && !$0.outputStreaming && !$0.state.isActive}
            let lines=try await source.conversation(for:partner)
            guard lines.filter({$0.id==messageID}).count==1 else {throw SourceFailure.message("A repeated command produced duplicate user messages.")}
            try record("actual message dispatch, completed output, and duplicate-command suppression")

            }

            if !manifest.checks.contains("actual pending-question read and exact-request answer") {
            let question="This is an isolated Pikminions integration test. Do not edit files, browse, launch agents or threads, or request credentials. Use request_user_input or request_user_input_async to ask exactly one multiple-choice sample question: Which sample layout? Options: Compact and Detailed. After the answer, reply exactly ACCEPT pikminions-answer-received. The sample question is the purpose of this authorized test; do not answer it yourself."
            if input.pendingRequestID==nil {try await source.send(input,text:question,delivery:.nextTurn,commandID:UUID().uuidString,messageID:UUID().uuidString)}
            input=try await wait(manifest.inputID) {$0.needsUserInput && $0.pendingRequestID != nil}
            let document=try await source.questions(for:input)
            guard document.requestId==input.pendingRequestID,!document.questions.isEmpty else {throw SourceFailure.message("The pending-question identity did not match.")}
            let answers=Dictionary(uniqueKeysWithValues:document.questions.map {item in (item.id,[item.options.first?.value ?? item.options.first?.label ?? "Compact"])})
            try await source.answer(input,requestID:document.requestId,answers:answers,commandID:UUID().uuidString)
            input=try await wait(manifest.inputID) {$0.output.contains("ACCEPT pikminions-answer-received") && !$0.outputStreaming && !$0.state.isActive}
            try record("actual pending-question read and exact-request answer")
            }

            if !manifest.checks.contains("actual crosstalk instruction and partner response") {
            let collaboration=AgentCommands.collaboration(instruction:"This is a sample-only integration check. Read the partner thread, send it exactly 'Pikminions SAMPLE ping', then report exactly ACCEPT pikminions-collaboration-sent. Do not edit files, browse, create threads, or share any context beyond these two labeled test threads.",partner:partner)
            try await source.send(input,text:collaboration,delivery:.nextTurn,commandID:UUID().uuidString,messageID:UUID().uuidString)
            input=try await wait(manifest.inputID,seconds:90) {$0.output.contains("ACCEPT pikminions-collaboration-sent") && !$0.outputStreaming && !$0.state.isActive}
            _=try await wait(manifest.partnerID,seconds:90) {$0.output.contains("ACCEPT pikminions-partner-pong") && !$0.outputStreaming && !$0.state.isActive}
            try record("actual crosstalk instruction and partner response")
            }

            if try await !source.t3().contains(where:{$0.threadID==manifest.forkID}) {
                try await source.fork(input,targetID:manifest.forkID,title:"Pikminions TEST - Fork",commandID:UUID().uuidString)
            }
            let fork=try await agent(manifest.forkID)
            guard !(try await source.conversation(for:fork)).isEmpty else {throw SourceFailure.message("The fork did not retain conversation history.")}
            try record("actual fork with retained history")
            let streamedHistory=try await withThrowingTaskGroup(of:Bool.self) {group in
                group.addTask {
                    let stream=try await source.conversationStream(for:fork)
                    for try await item in stream {
                        if item["kind"]?.string=="snapshot" {return !AgentSources.projectionLines(item["projection"]).isEmpty}
                    }
                    return false
                }
                group.addTask {try await Task.sleep(for:.seconds(12));throw SourceFailure.message("The canary stream snapshot timed out.")}
                defer {group.cancelAll()}
                return try await group.next() ?? false
            }
            guard streamedHistory else {throw SourceFailure.message("The stream snapshot omitted visible fork history.")}
            try record("actual WebSocket snapshot with inherited fork history")
            if try await !source.t3().contains(where:{$0.threadID==manifest.freshID}) {
                try await source.fresh(input,targetID:manifest.freshID,title:"Pikminions TEST - Fresh",commandID:UUID().uuidString)
            }
            let fresh=try await agent(manifest.freshID)
            guard try await source.conversation(for:fresh).isEmpty else {throw SourceFailure.message("The fresh conversation contains inherited messages.")}
            try record("actual fresh conversation without inherited messages")
            try await source.disconnectT3()
            try record("all temporary canary credential sessions revoked")
        } catch {
            do {try await source.disconnectT3()} catch {print("Cleanup needs attention: temporary session revocation failed.");fflush(stdout)}
            throw error
        }
    }
}
