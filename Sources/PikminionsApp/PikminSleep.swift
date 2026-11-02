// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Foundation

struct PikminSleepPose:Equatable,Sendable {
    var sleepiness=0.0
    var tilt=0.0
    var y=0.0
    var scaleX=1.0
    var scaleY=1.0
    var leaf=0.0
    var stemDrop=0.0
    var zOpacity=0.0
    var zRise=0.0
    var yawn=0.0
    static let awake=Self()
    static let asleep=Self(sleepiness:1,tilt:8,y:3,scaleX:1.025,scaleY:0.965,leaf:10,stemDrop:6,zOpacity:0.55)
    static let stretch=Self(sleepiness:0.12,tilt:-3,y:-1,scaleX:0.98,scaleY:1.045,leaf:-5,stemDrop:-2)
    static let drowsy=Self(sleepiness:0.32,tilt:2,y:1,leaf:3,stemDrop:2)
    static func blend(_ from:Self,_ to:Self,_ progress:Double)->Self {
        let p=max(0,min(1,progress))
        func mix(_ a:Double,_ b:Double)->Double {a+(b-a)*p}
        return Self(sleepiness:mix(from.sleepiness,to.sleepiness),tilt:mix(from.tilt,to.tilt),y:mix(from.y,to.y),
                    scaleX:mix(from.scaleX,to.scaleX),scaleY:mix(from.scaleY,to.scaleY),leaf:mix(from.leaf,to.leaf),
                    stemDrop:mix(from.stemDrop,to.stemDrop),zOpacity:mix(from.zOpacity,to.zOpacity),zRise:mix(from.zRise,to.zRise),yawn:mix(from.yawn,to.yawn))
    }
}

struct PikminSleepEvent:Equatable,Sendable {
    enum Kind:Equatable,Sendable {case yawn,sleep,wake}
    static let yawningDuration=2.8
    static let settlingDuration=1.8
    static let wakingDuration=1.35
    var kind:Kind
    var startedAt:Date
    var startPose:PikminSleepPose = .awake
    var isSleeping:Bool {kind == .sleep}
    var label:String {switch kind {case .yawn:"Sleepy";case .sleep:"Sleeping";case .wake:"Waking up"}}
    var reducedMotionPose:PikminSleepPose {switch kind {case .yawn:.drowsy;case .sleep:.asleep;case .wake:.awake}}
    func pose(at date:Date)->PikminSleepPose {
        let elapsed=max(0,date.timeIntervalSince(startedAt))
        func ease(_ value:Double)->Double {let p=max(0,min(1,value));return p*p*p*(p*(p*6-15)+10)}
        if kind == .yawn {
            let p=min(1,elapsed/Self.yawningDuration),stretch=pow(sin(p*Double.pi),2)
            var result=PikminSleepPose.blend(.awake,.drowsy,ease(p))
            result.yawn=stretch;result.sleepiness+=stretch*0.6
            result.tilt-=stretch*4;result.scaleY+=stretch*0.025;result.stemDrop-=stretch*2
            return result
        }
        if kind == .wake {
            let p=elapsed/Self.wakingDuration
            if p>=1 {return .awake}
            return p<0.4 ? .blend(startPose,.stretch,ease(p/0.4)):.blend(.stretch,.awake,ease((p-0.4)/0.6))
        }
        let amount=ease(elapsed/Self.settlingDuration)
        var result=PikminSleepPose.blend(startPose,.asleep,amount)
        let breath=(1-cos(elapsed/4.6*2*Double.pi))*0.5*amount
        result.y+=breath*1.1;result.scaleX+=breath*0.008;result.scaleY-=breath*0.008
        let puff=elapsed.truncatingRemainder(dividingBy:3.6)/3.6
        result.zOpacity=pow(sin(puff*Double.pi),2)*0.72*ease((elapsed-1.2)/0.8)
        result.zRise=puff*13
        return result
    }
}

/// One bounded state store, advanced by the existing idle scheduler. Only
/// completed desktop heads sleep; interaction starts a fresh quiet interval.
struct PikminSleepDirector {
    static let quietInterval:TimeInterval=120
    static let yawnLead:TimeInterval=3
    private struct Period {
        var runID:String
        var completedAt:Date
        var quietSince:Date
    }
    private var periods:[String:Period]=[:]
    private(set) var events:[String:PikminSleepEvent]=[:]
    @discardableResult mutating func wake(_ id:String,at now:Date)->Bool {
        if periods[id] != nil {periods[id]?.quietSince=now}
        guard let event=events[id],event.kind != .wake else{return false}
        events[id]=PikminSleepEvent(kind:.wake,startedAt:now,startPose:event.pose(at:now))
        return true
    }
    @discardableResult mutating func advance(at now:Date,agents:[AgentRecord],blocked:Set<String>=[])->Bool {
        let before=events,ids=Set(agents.map(\.id))
        periods=periods.filter{ids.contains($0.key)}
        events=events.filter{ids.contains($0.key) && ($0.value.kind != .wake || now.timeIntervalSince($0.value.startedAt)<PikminSleepEvent.wakingDuration)}
        for agent in agents {
            let id=agent.id
            guard !agent.stale else {events.removeValue(forKey:id);periods.removeValue(forKey:id);continue}
            guard agent.state == .finished,!agent.needsUserInput else {
                wake(id,at:now);periods.removeValue(forKey:id);continue
            }
            if periods[id]?.runID != agent.runID || (agent.runID.isEmpty && periods[id]?.completedAt != agent.updated) {
                wake(id,at:now)
                let completed=agent.updated == .distantPast ? now:min(now,agent.updated)
                periods[id]=Period(runID:agent.runID,completedAt:agent.updated,quietSince:completed)
            }
            if blocked.contains(id) {wake(id,at:now);periods[id]?.quietSince=now;continue}
            if let quiet=periods[id]?.quietSince {
                let elapsed=now.timeIntervalSince(quiet)
                if elapsed>=Self.quietInterval,events[id]==nil || events[id]?.kind == .yawn {
                    events[id]=PikminSleepEvent(kind:.sleep,startedAt:now,startPose:events[id]?.pose(at:now) ?? .awake)
                } else if elapsed>=Self.quietInterval-Self.yawnLead,events[id]==nil {
                    events[id]=PikminSleepEvent(kind:.yawn,startedAt:now)
                }
            }
        }
        return before != events
    }
}
