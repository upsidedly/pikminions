// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Testing

@testable import PikminionsApp

/// Pure parsing tests: no app startup, credentials, filesystem or live sources.
struct T3ConversationParserTests {
    @Test func inheritedHistoryUsesVisibleTurnItems() {
        let projection: JSONValue = .object([
            "messages": .array([]),
            "visibleTurnItems": .array([
                .object([
                    "item": .object([
                        "type": .string("assistant_message"),
                        "messageId": .string("inherited-message"),
                        "text": .string("Output inherited from the parent conversation."),
                    ])
                ])
            ]),
        ])

        let lines = T3ConversationParser.projectionLines(projection)
        #expect(lines.count == 1)
        #expect(lines.first?.id == "inherited-message")
        #expect(lines.first?.role == "assistant")
        #expect(lines.first?.text == "Output inherited from the parent conversation.")
    }

    @Test func omittedVisibleTextUsesTheLocalMessage() {
        let projection: JSONValue = .object([
            "messages": .array([
                .object([
                    "id": .string("message"), "role": .string("assistant"),
                    "text": .string("The full local text."), "streaming": .bool(true),
                ])
            ]),
            "visibleTurnItems": .array([
                .object([
                    "item": .object([
                        "type": .string("assistant_message"),
                        "messageId": .string("message"), "textOmitted": .bool(true),
                    ])
                ])
            ]),
        ])

        let line = T3ConversationParser.projectionLines(projection).first
        #expect(line?.text == "The full local text.")
        #expect(line?.streaming == true)
    }

    @Test func absentVisibleHistoryFallsBackToBoundedLocalHistory() {
        let messages: [JSONValue] = (0..<35).map { index in
            .object([
                "id": .string("message-\(index)"), "role": .string("assistant"),
                "text": .string("Output \(index)"),
            ])
        }
        let lines = T3ConversationParser.projectionLines(.object(["messages": .array(messages)]))
        #expect(lines.count == 30)
        #expect(lines.first?.id == "message-5")
        #expect(lines.last?.id == "message-34")
        #expect(T3ConversationParser.projectionLines(nil).isEmpty)
    }

    @Test func partialAndFinalEventsKeepTheMessageIdentity() {
        let partial = T3ConversationParser.eventLine(
            event(
                "turn-item.updated",
                [
                    "type": .string("assistant_message"), "messageId": .string("message"),
                    "threadId": .string("thread"), "text": .string("Working…"),
                    "streaming": .bool(true),
                ]), threadID: "thread")
        let final = T3ConversationParser.eventLine(
            event(
                "message.updated",
                [
                    "id": .string("message"), "role": .string("assistant"),
                    "threadId": .string("thread"), "text": .string("Done."),
                    "streaming": .bool(false),
                ]), threadID: "thread")

        #expect(partial?.id == "message")
        #expect(partial?.streaming == true)
        #expect(final?.id == partial?.id)
        #expect(final?.text == "Done.")
        #expect(final?.streaming == false)
    }

    @Test func reasoningOtherThreadsAndOmittedTextDoNotBecomeSpeech() {
        let invalidPayloads: [[String: JSONValue]] = [
            [
                "type": .string("reasoning"), "messageId": .string("private"),
                "text": .string("Hidden"),
            ],
            [
                "type": .string("assistant_message"), "messageId": .string("other"),
                "threadId": .string("another-thread"), "text": .string("Other output"),
            ],
            [
                "type": .string("assistant_message"), "messageId": .string("omitted"),
                "textOmitted": .bool(true), "text": .string("Placeholder"),
            ],
        ]
        for payload in invalidPayloads {
            #expect(
                T3ConversationParser.eventLine(
                    event("turn-item.updated", payload), threadID: "thread") == nil)
        }
    }

    @Test func longStreamKeepsTheNewestTailAndCompletionSignal() {
        let text =
            "ACCEPT " + String(repeating: "🌸 Earlier output. ", count: 3000) + "Newest output."
        let line = T3ConversationParser.eventLine(
            event(
                "message.updated",
                [
                    "id": .string("long"), "role": .string("assistant"),
                    "text": .string(text), "streaming": .bool(false),
                ]), threadID: "thread")

        #expect((line?.text.utf8.count ?? Int.max) <= 24000)
        #expect(line?.text.hasSuffix("Newest output.") == true)
        #expect(line?.containsAccept == true)
    }

    private func event(_ type: String, _ payload: [String: JSONValue]) -> JSONValue {
        .object(["type": .string(type), "payload": .object(payload)])
    }
}
