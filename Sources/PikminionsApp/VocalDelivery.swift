// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Foundation

/// Identity-only memory: a dismissed speech bubble stays dismissed for all
/// subsequent chunks/polls of the same message. No message text is retained.
struct VocalDeliveryTracker {
    private var seen:[String:[String]]=[:]
    mutating func receive(agentID:String,eventID:String,historical:Bool)->Bool {
        var values=seen[agentID] ?? []
        guard !values.contains(eventID) else{return false}
        values.append(eventID)
        seen[agentID]=Array(values.suffix(64))
        return !historical
    }
}
