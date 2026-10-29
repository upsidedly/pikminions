// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Foundation

enum PikminIdleKind:String,CaseIterable,Sendable {
    case lookAround,doubleBlink,stretch,leafWiggle,sleepyNod
    var duration:Double {2.4}
}
struct PikminIdleEvent:Equatable,Sendable {
    var kind:PikminIdleKind
    var startedAt:Date
    func pose(at date:Date)->PikminIdlePose {PikminIdlePose.make(kind,progress:date.timeIntervalSince(startedAt)/kind.duration)}
}
struct PikminIdlePose:Equatable,Sendable {
    var tilt=0.0
    var y=0.0
    var scaleX=1.0
    var scaleY=1.0
    var leaf=0.0
    var blink=1.0
    var lookX=0.0
    var lookY=0.0
    static let rest=PikminIdlePose()
    static func make(_ kind:PikminIdleKind,progress:Double)->Self {
        guard progress>0,progress<1 else{return .rest}
        let envelope=pow(sin(progress*Double.pi),2)
        var pose=Self.rest
        switch kind {
        case .lookAround:pose.lookX=sin(progress*2*Double.pi)*envelope;pose.tilt=pose.lookX*3
        case .doubleBlink:
            let first=max(0,1-abs(progress-0.34)/0.075),second=max(0,1-abs(progress-0.60)/0.075)
            pose.blink=1-0.94*max(first,second)
        case .stretch:pose.scaleX=1+0.035*envelope;pose.scaleY=1-0.025*envelope
        case .leafWiggle:pose.leaf=sin(progress*6*Double.pi)*envelope*6
        case .sleepyNod:pose.y=2.4*envelope;pose.tilt=3*envelope;pose.blink=1-0.58*envelope;pose.lookY=0.7*envelope
        }
        return pose
    }
}

/// One scheduler for actual visible agents. Losing eligibility removes a queued
/// gesture and starts a fresh quiet interval when the head is available again.
struct PikminIdleDirector {
    private(set) var active:[String:PikminIdleEvent]=[:]
    private var next:[String:Date]=[:]
    private var last:[String:PikminIdleKind]=[:]
    mutating func suspend(_ id:String) {active.removeValue(forKey:id);next.removeValue(forKey:id)}
    mutating func advance<R:RandomNumberGenerator>(at now:Date,eligible:Set<String>,using random:inout R)->Bool {
        let before=active
        active=active.filter{eligible.contains($0.key) && (0..<$0.value.kind.duration).contains(now.timeIntervalSince($0.value.startedAt))}
        next=next.filter{eligible.contains($0.key)};last=last.filter{eligible.contains($0.key)}
        for id in eligible.sorted() {
            if next[id]==nil || (next[id]?.timeIntervalSince(now) ?? 0)>30 {next[id]=now.addingTimeInterval(Double.random(in:8...18,using:&random))}
            guard let due=next[id],due<=now,active[id]==nil else{continue}
            let choices=PikminIdleKind.allCases.filter{$0 != last[id]}
            guard let kind=choices.randomElement(using:&random) else{continue}
            active[id]=PikminIdleEvent(kind:kind,startedAt:now);last[id]=kind
            next[id]=now.addingTimeInterval(kind.duration+Double.random(in:8...20,using:&random))
        }
        return before != active
    }
}
