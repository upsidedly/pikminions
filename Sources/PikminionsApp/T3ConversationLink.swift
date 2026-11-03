// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Foundation

enum T3ConversationLink {
    /// T3's desktop route includes both the environment and conversation ID.
    /// An HTTP route opens the browser; t3-thread links identify agent context
    /// but are not registered as a macOS application protocol by T3.
    static func desktopURL(environmentID: String, threadID: String) -> URL? {
        let invalid = CharacterSet.whitespacesAndNewlines.union(.controlCharacters).union(
            CharacterSet(charactersIn: "/\\"))
        guard
            [environmentID, threadID].allSatisfy({
                !$0.isEmpty && $0 != "." && $0 != ".." && $0.rangeOfCharacter(from: invalid) == nil
            })
        else { return nil }
        var target = URLComponents()
        target.scheme = "t3code"
        target.host = "threads"
        target.path = "/" + environmentID + "/" + threadID
        return target.url
    }
}
