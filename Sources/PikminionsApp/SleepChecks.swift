// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Foundation

@MainActor func runPikminSleepChecks() throws {
    func expect(_ value: Bool, _ message: String) throws {
        if !value { throw SourceFailure.message("Sleep check failed: " + message) }
    }
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    var agent = AgentRecord(
        id: "sleep-check", source: "Fixture", threadID: "sleep-check", runID: "run-one",
        title: "Sleep check", project: "Fixture", model: "Sample", state: .finished, detail: "",
        updated: start, openURL: nil)
    var director = PikminSleepDirector()
    director.advance(at: start.addingTimeInterval(116.99), agents: [agent])
    try expect(
        director.events.isEmpty, "a newly completed task remains awake before its drowsy interval")
    director.advance(at: start.addingTimeInterval(117), agents: [agent])
    try expect(director.events[agent.id]?.kind == .yawn, "a head yawns just before it falls asleep")
    let bedtime = start.addingTimeInterval(120)
    let drowsyPose = director.events[agent.id]?.pose(at: bedtime)
    director.advance(at: bedtime, agents: [agent])
    guard let sleeping = director.events[agent.id] else {
        throw SourceFailure.message("Sleep check failed: completed head never fell asleep")
    }
    try expect(
        sleeping.isSleeping && sleeping.pose(at: bedtime) == drowsyPose,
        "sleep continues the exact end of the yawn")
    try expect(
        sleeping.pose(at: bedtime.addingTimeInterval(2)).sleepiness == 1,
        "eyes close after settling")
    var refreshed = agent
    refreshed.updated = bedtime.addingTimeInterval(3)
    director.advance(at: bedtime.addingTimeInterval(3), agents: [refreshed])
    try expect(
        director.events[agent.id] == sleeping,
        "snapshot timestamps cannot replay an existing run's sleep entrance")
    let wakeTime = bedtime.addingTimeInterval(4)
    let captured = sleeping.pose(at: bedtime.addingTimeInterval(4))
    try expect(director.wake(agent.id, at: wakeTime), "clicking a sleeping head starts waking")
    let waking = director.events[agent.id]
    try expect(
        waking?.isSleeping == false && waking?.pose(at: wakeTime) == captured,
        "waking continues the exact rendered sleeping pose")
    director.wake(agent.id, at: wakeTime.addingTimeInterval(0.05))
    try expect(
        director.events[agent.id] == waking, "repeated clicks do not restart the wake animation")
    director.advance(at: wakeTime.addingTimeInterval(2), agents: [agent])
    try expect(director.events.isEmpty, "waking ends in a normal awake head")
    director.advance(at: wakeTime.addingTimeInterval(119), agents: [agent])
    try expect(
        director.events[agent.id]?.isSleeping != true,
        "old completion timestamps cannot put a clicked head straight back to sleep")
    director.advance(at: wakeTime.addingTimeInterval(125), agents: [agent], blocked: [agent.id])
    director.advance(at: wakeTime.addingTimeInterval(240), agents: [agent])
    try expect(
        director.events.isEmpty,
        "a grab, menu, question or celebration holds attention and refreshes the quiet interval")
    director.advance(at: wakeTime.addingTimeInterval(246), agents: [agent])
    try expect(
        director.events[agent.id]?.isSleeping == true,
        "a head can sleep again after another full quiet interval")
    var working = agent
    working.state = .working
    working.runID = "run-two"
    director.advance(at: wakeTime.addingTimeInterval(247), agents: [working])
    try expect(director.events[agent.id]?.kind == .wake, "new work wakes automatically")
    agent.runID = "run-two"
    agent.updated = wakeTime.addingTimeInterval(250)
    director.advance(at: agent.updated, agents: [agent])
    try expect(director.events.isEmpty, "a newly finished run gets its own quiet interval")
    director.advance(at: agent.updated.addingTimeInterval(121), agents: [agent])
    var question = agent
    question.pendingRequestID = "question"
    question.pendingRequestKind = "user_input"
    director.advance(at: agent.updated.addingTimeInterval(122), agents: [question])
    try expect(
        director.events[agent.id]?.kind == .wake,
        "a pending question wakes even when the task's reported status is completed")
    for state in AgentState.allCases where state != .finished {
        var other = agent
        other.state = state
        var probe = PikminSleepDirector()
        probe.advance(at: agent.updated.addingTimeInterval(600), agents: [other])
        try expect(
            probe.events.isEmpty, "active, idle, failed, interrupted and recorded heads never sleep"
        )
    }
    var stale = agent
    stale.stale = true
    director.advance(at: agent.updated.addingTimeInterval(123), agents: [stale])
    try expect(director.events.isEmpty, "a disconnected source is shown as disconnected")
    director.advance(at: agent.updated.addingTimeInterval(600), agents: [agent])
    director.advance(at: agent.updated.addingTimeInterval(601), agents: [])
    try expect(
        director.events.isEmpty,
        "removing, hiding or docking a desktop head discards its sleep state")
    let interrupted = PikminSleepEvent(
        kind: .wake, startedAt: bedtime.addingTimeInterval(0.4),
        startPose: sleeping.pose(at: bedtime.addingTimeInterval(0.4)))
    try expect(
        interrupted.pose(at: interrupted.startedAt) == interrupted.startPose,
        "a wake during the sleep entrance does not snap")
    for step in 0...720 {
        let date = bedtime.addingTimeInterval(Double(step) / 60)
        let rest = sleeping.pose(at: date)
        let wake = interrupted.pose(at: interrupted.startedAt.addingTimeInterval(Double(step) / 60))
        let yawn = PikminSleepEvent(kind: .yawn, startedAt: bedtime).pose(at: date)
        for pose in [rest, wake, yawn] {
            try expect(
                [
                    pose.sleepiness, pose.tilt, pose.y, pose.scaleX, pose.scaleY, pose.stemDrop,
                    pose.zOpacity, pose.zRise, pose.yawn,
                ].allSatisfy(\.isFinite), "yawn, sleep and wake poses remain finite")
            try expect(
                (0...1).contains(pose.sleepiness) && (0...1).contains(pose.zOpacity)
                    && abs(pose.tilt) <= 8 && abs(pose.y) <= 4.2
                    && (0.97...1.04).contains(pose.scaleX) && (0.95...1.05).contains(pose.scaleY),
                "breathing and stretch stay within the desktop artwork's small envelope")
        }
    }
    try expect(
        interrupted.pose(
            at: interrupted.startedAt.addingTimeInterval(PikminSleepEvent.wakingDuration))
            == .awake, "wake animation joins the normal resting pose exactly")
    try expect(
        sleeping.reducedMotionPose == .asleep && interrupted.reducedMotionPose == .awake,
        "Reduced Motion uses static sleeping and immediately awake poses")
    let model = SquadModel()
    let clock = Date.now
    defer { model.stop() }
    agent.updated = clock.addingTimeInterval(-300)
    model.mode = .desktop
    model.hidden = []
    model.docked = []
    model.pinned = [agent.id]
    model.records = [agent]
    model.advanceDesktopSleep(at: clock.addingTimeInterval(-3))
    model.observeOutput(
        agent.id, line: ConversationLine(id: "history", role: "assistant", text: "Earlier output"),
        historical: true)
    try expect(
        model.sleepEvents[agent.id]?.isSleeping == true,
        "historical output never wakes a desktop head")
    let live = ConversationLine(id: "live", role: "assistant", text: "New output")
    model.observeOutput(agent.id, line: live, historical: false)
    try expect(model.sleepEvents[agent.id]?.kind == .wake, "fresh live output wakes immediately")
    model.advanceDesktopSleep(at: clock.addingTimeInterval(125))
    model.observeOutput(agent.id, line: live, historical: false)
    try expect(
        model.sleepEvents[agent.id]?.isSleeping == true,
        "replayed output cannot continuously wake a completed task")
    model.questionLoaded(
        agent.id,
        document: AgentQuestionDocument(
            requestId: "question",
            questions: [
                AgentQuestion(
                    id: "answer", header: "Answer", question: "Which approach?", options: [],
                    allowCustomAnswer: true)
            ]))
    try expect(
        model.sleepEvents[agent.id]?.kind == .wake,
        "streamed questions wake before the next roster poll")
    model.questions = [:]
    model.attending = [agent.id]
    model.advanceDesktopSleep(at: clock.addingTimeInterval(250))
    try expect(
        model.sleepEvents[agent.id]?.isSleeping == true,
        "a conversation left open and untouched can drift back to sleep")
    let yawning = PikminSleepEvent(kind: .yawn, startedAt: start)
    try expect(
        yawning.pose(at: start).yawn == 0
            && yawning.pose(at: start.addingTimeInterval(1.4)).yawn > 0.99
            && yawning.pose(at: start.addingTimeInterval(2.8)).yawn < 0.001,
        "a yawn opens and closes before sleep")
    try expect(yawning.reducedMotionPose.yawn == 0, "Reduced Motion does not animate yawning")
    try expect(
        PikminWorkPose.make(time: 0) == .rest
            && abs(PikminWorkPose.make(time: 4.8).motion.tilt) < 0.001,
        "working cycles join without a jump")
    var effortSeen = false
    var nodSeen = false
    for step in 0...480 {
        let work = PikminWorkPose.make(time: Double(step) / 100)
        effortSeen = effortSeen || work.effort > 0.5
        nodSeen = nodSeen || work.motion.y > 2
        try expect(
            abs(work.motion.tilt) <= 5.2 && abs(work.motion.leaf) <= 8
                && (0.82...1).contains(work.motion.blink) && (0...0.8).contains(work.effort),
            "working effort stays bounded")
    }
    try expect(
        effortSeen && nodSeen, "working has distinct rhythmic effort and a brief effort bead")
    model.vocalByDefault = true
    model.vocalOverrides = [:]
    try expect(model.isVocal(agent), "interactive heads inherit vocal mode on by default")
    model.vocalOverrides[agent.id] = false
    try expect(!model.isVocal(agent), "an individual can stay quiet while the default is on")
    model.vocalByDefault = false
    model.vocalOverrides[agent.id] = true
    try expect(model.isVocal(agent), "an individual can stay vocal while the default is off")
    model.vocalOverrides = [:]
    try expect(!model.isVocal(agent), "changing the default affects heads without an override")
    var recorded = agent
    recorded.source = "Codex"
    model.vocalByDefault = true
    try expect(!model.isVocal(recorded), "recorded history is never made vocal by a default")
    print(
        "PASS: two-minute sleep and yawn; continuous click/work/input wake; return to sleep while unattended; bounded work effort; Reduced Motion and per-head vocal defaults."
    )
}
