// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Antille
import Foundation

/// Converts bounded projections and live events into displayable conversation lines.
/// This boundary does not read credentials, perform I/O or retain conversation state.
enum T3ConversationParser {
    /// Visible turn items include inherited fork history. `messages` contains
    /// only local records, and may carry text omitted from the visible row.
    static func projectionLines(_ projection: JSONValue?) -> [ConversationLine] {
        let local = lines(projection?["messages"]?.array ?? [])
        let byID = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        let visible = (projection?["visibleTurnItems"]?.array ?? []).compactMap {
            row -> ConversationLine? in
            guard let item = row["item"], let type = item["type"]?.string,
                ["assistant_message", "user_message"].contains(type),
                let id = item["messageId"]?.string
            else { return nil }
            if item["textOmitted"]?.bool == true { return byID[id] }
            guard let text = item["text"]?.string else { return byID[id] }
            return ConversationLine(
                id: id, role: type == "assistant_message" ? "assistant" : "user",
                text: String(text.prefix(24000)), streaming: item["streaming"]?.bool ?? false)
        }
        return visible.isEmpty ? local : Array(visible.suffix(30))
    }
    static func lines(_ values: [JSONValue]) -> [ConversationLine] {
        values.suffix(30).compactMap { value in
            guard let id = value["id"]?.string, let role = value["role"]?.string,
                let text = value["text"]?.string, ["user", "assistant"].contains(role)
            else { return nil }
            return ConversationLine(
                id: id, role: role, text: String(text.prefix(24000)),
                streaming: value["streaming"]?.bool ?? false)
        }
    }
    /// Codex publishes partial assistant text as turn items; message.updated may
    /// only arrive at completion. Both records share the conversation message ID.
    static func eventLine(_ event: JSONValue, threadID: String) -> ConversationLine? {
        guard let payload = event["payload"], payload["textOmitted"]?.bool != true,
            let text = payload["text"]?.string
        else { return nil }
        if let owner = payload["threadId"]?.string ?? event["threadId"]?.string, owner != threadID {
            return nil
        }
        let id: String
        let role: String
        switch event["type"]?.string {
        case "message.updated":
            guard let messageID = payload["id"]?.string, let messageRole = payload["role"]?.string,
                ["user", "assistant"].contains(messageRole)
            else { return nil }
            id = messageID
            role = messageRole
        case "turn-item.updated":
            guard let kind = payload["type"]?.string,
                ["assistant_message", "user_message"].contains(kind),
                let messageID = payload["messageId"]?.string
            else { return nil }
            id = messageID
            role = kind == "assistant_message" ? "assistant" : "user"
        default: return nil
        }
        return ConversationLine(
            id: id, role: role, text: IslandMarkdown.tail(text, maxBytes: 24000),
            streaming: payload["streaming"]?.bool ?? false, containsAccept: text.contains("ACCEPT"))
    }
}
