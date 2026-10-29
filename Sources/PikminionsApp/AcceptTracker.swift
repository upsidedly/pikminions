// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Foundation

/// Keep the last accepted message per agent so a large squad cannot evict
/// another agent's marker and replay the same celebration on every poll.
struct AcceptTracker {
    private(set) var latest:[String:String]
    private var seen:[String:[String]]
    init(latest:[String:String]=[:]) {self.latest=latest;seen=latest.mapValues{[$0]}}
    mutating func observe(agentID:String,messageID:String,text:String,streaming:Bool=false,historical:Bool)->Bool {
        guard !streaming,text.contains("ACCEPT"),!messageID.isEmpty else{return false}
        guard seen[agentID]?.contains(messageID) != true else{return false}
        seen[agentID,default:[]].append(messageID)
        if (seen[agentID]?.count ?? 0)>64 {seen[agentID]?.removeFirst()}
        // A slow initial-history read must not replace a newer live marker.
        if !historical || latest[agentID]==nil {latest[agentID]=messageID}
        return !historical
    }
}
