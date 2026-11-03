// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Foundation

/// Reads the shared Codex server when present, otherwise explicitly recorded metadata.
enum CodexSource {
    static func snapshot() async throws -> (records: [AgentRecord], live: Bool) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let socket = home.appending(path: ".codex/app-server-control/app-server-control.sock")
        if FileManager.default.fileExists(atPath: socket.path) {
            do {
                let data = try await LocalProcessJob().run(
                    executable: "/opt/homebrew/bin/codex", arguments: ["app-server", "proxy"],
                    rpc: true)
                struct Page: Decodable { var data: [Thread] }
                struct Thread: Decodable {
                    var id: String
                    var name: String?
                    var cwd: String?
                    var status: Status
                    struct Status: Decodable {
                        var type: String
                        var activeFlags: [String]?
                    }
                }
                let page = try JSONDecoder().decode(Page.self, from: data)
                let records = page.data.map { thread -> AgentRecord in
                    let flags = thread.status.activeFlags ?? []
                    let state: AgentState =
                        flags.contains("waitingOnApproval")
                        ? .waitingApproval
                        : flags.contains("waitingOnUserInput")
                            ? .waitingInput
                            : thread.status.type == "active"
                                ? .working : thread.status.type == "systemError" ? .failed : .idle
                    return AgentRecord(
                        id: "codex:" + thread.id, nativeID: thread.id, source: "Codex",
                        threadID: thread.id, runID: thread.id,
                        title: thread.name ?? "Codex conversation",
                        project: URL(fileURLWithPath: thread.cwd ?? "").lastPathComponent,
                        model: "Codex", state: state, detail: "", parentID: nil, updated: .now,
                        openURL: nil, stale: thread.status.type == "notLoaded")
                }
                return (records, true)
            } catch {
                // A failed shared-server read falls back to explicitly recorded history.
            }
        }
        return (try SQLiteMetadata.recordedCodex(), false)
    }
}
