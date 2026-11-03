// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import CSQLite
import Foundation

struct SQLiteMetadata {
    static func rows(path: String, sql: String) throws -> [[String: String]] {
        var db: OpaquePointer?
        guard
            sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
                == SQLITE_OK, let db
        else {
            if let db { sqlite3_close(db) }
            throw SourceFailure.message("Recorded metadata is unavailable.")
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 150)
        sqlite3_exec(db, "PRAGMA query_only=ON", nil, nil, nil)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SourceFailure.message("This metadata version is not supported.")
        }
        defer { sqlite3_finalize(statement) }
        var result: [[String: String]] = []
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            var row: [String: String] = [:]
            for i in 0..<sqlite3_column_count(statement) {
                guard let name = sqlite3_column_name(statement, i),
                    let text = sqlite3_column_text(statement, i)
                else { continue }
                row[String(cString: name)] = String(cString: text)
            }
            result.append(row)
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else {
            throw SourceFailure.message("Recorded metadata could not be read completely.")
        }
        return result
    }
    static func codexAliases() -> [String: String] {
        let path = FileManager.default.homeDirectoryForCurrentUser.appending(
            path: ".t3/userdata/statev2.sqlite"
        ).path
        let sql =
            "SELECT provider_thread_id,json_extract(payload_json,'$.nativeThreadRef.nativeId') AS native_id FROM orchestration_v2_projection_provider_threads WHERE driver='codex' AND json_extract(payload_json,'$.nativeThreadRef.strength')='strong'"
        let rows = (try? rows(path: path, sql: sql)) ?? []
        return Dictionary(
            rows.compactMap { row -> (String, String)? in
                guard let id = row["provider_thread_id"], let native = row["native_id"],
                    !native.isEmpty
                else { return nil }
                return (id, native)
            }, uniquingKeysWith: { $1 })
    }
    static func recordedCodex() throws -> [AgentRecord] {
        let home = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex")
        let threads = try rows(
            path: home.appending(path: "state_5.sqlite").path,
            sql:
                "SELECT id,title,name,cwd,COALESCE(updated_at_ms,updated_at*1000) AS updated FROM threads WHERE archived=0 ORDER BY updated DESC LIMIT 60"
        )
        let history =
            (try? rows(
                path: home.appending(path: "thread_history_1.sqlite").path,
                sql:
                    "SELECT thread_id,turn_id,status,completed_at FROM thread_turns t WHERE rollout_ordinal=(SELECT MAX(rollout_ordinal) FROM thread_turns x WHERE x.thread_id=t.thread_id)"
            )) ?? []
        let byID = Dictionary(
            history.compactMap { row -> (String, [String: String])? in
                row["thread_id"].map { ($0, row) }
            }, uniquingKeysWith: { $1 })
        let edges =
            (try? rows(
                path: home.appending(path: "state_5.sqlite").path,
                sql: "SELECT parent_thread_id,child_thread_id FROM thread_spawn_edges")) ?? []
        let parents = Dictionary(
            edges.compactMap { row -> (String, String)? in
                guard let c = row["child_thread_id"], let p = row["parent_thread_id"] else {
                    return nil
                }
                return (c, p)
            }, uniquingKeysWith: { $1 })
        return threads.compactMap { row in
            guard let id = row["id"] else { return nil }
            let turn = byID[id]
            return AgentRecord(
                id: "codex:" + id, nativeID: id, source: "Codex", threadID: id,
                runID: turn?["turn_id"] ?? "",
                title: row["name"].flatMap { $0.isEmpty ? nil : $0 } ?? row["title"]
                    ?? "Codex conversation",
                project: URL(fileURLWithPath: row["cwd"] ?? "").lastPathComponent, model: "Codex",
                state: .recorded,
                detail: "Last recorded: \(turn?["status"] ?? "unknown"). Live server unavailable.",
                parentID: parents[id].map { "codex:" + $0 },
                updated: Date(timeIntervalSince1970: (Double(row["updated"] ?? "") ?? 0) / 1000),
                openURL: nil, stale: true, silent: true)
        }
    }
}
