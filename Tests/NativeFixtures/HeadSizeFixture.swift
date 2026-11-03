// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import AppKit
import SwiftUI

@testable import Antille
@testable import PikminionsApp

/// Real desktop views and floating panels, with no model.start(), host or T3.
@MainActor @Observable final class HeadSizeSamples: NSObject {
    let model: SquadModel
    let desktop: DesktopSquadController
    let sampleIDs: [String]
    var sleepMode: Bool {
        Bundle.main.bundleIdentifier?.contains(".sleep.fixture") == true
            || CommandLine.arguments.contains("--sleep-check")
    }
    var result = "Right-click a sample head → Size."
    var reduceMotion = false
    private var menuTimers: [Timer] = []
    private var trackingMenu: NSMenu?
    private var highlightedTitle: String?
    private var trackedItems: [NSMenuItem] = []
    private var trackedHeadID: String?
    private var trackedFrame: CGRect?
    private var menuStage = 0
    private var menuAutomatic = true
    override init() {
        let model = SquadModel()
        let saved = model.headSizes
        model.mode = .desktop
        model.hidden = []
        model.docked = []
        model.pinned = []
        model.headSizes = [:]
        model.records = PikminSize.allCases.enumerated().map { index, size in
            AgentRecord(
                id: "size-sample-\(size.rawValue)", source: "Fixture",
                threadID: "size-sample-\(index)", runID: "sample-run",
                title: "Size fixture · \(size.title)", project: "Fixture", model: "Sample",
                state: .working, detail: "", updated: .distantPast, openURL: nil)
        }
        model.speciesOverrides = Dictionary(
            uniqueKeysWithValues: zip(model.records.map(\.id), ["blue", "red", "yellow", "glow"]))
        for (agent, size) in zip(model.records, PikminSize.allCases) {
            model.headSizes[agent.id] =
                saved[agent.id].flatMap(PikminSize.init(rawValue:))?.rawValue ?? size.rawValue
        }
        self.model = model
        desktop = DesktopSquadController(model: model)
        sampleIDs = model.records.map(\.id)
        model.desktop = desktop
        super.init()
        if sleepMode {
            if let screen = NSScreen.main?.visibleFrame {
                UserDefaults.standard.set(
                    [screen.minX + 20.25, screen.minY + 30.625],
                    forKey: "Pikminions.position.size-sample-medium")
            }
            model.records = model.records.map { agent in
                var result = agent
                result.state = .finished
                result.updated = Date.now.addingTimeInterval(-300)
                return result
            }
            model.conversationCoordinator = ConversationCoordinator(model: model)
            model.advanceDesktopSleep(at: Date.now.addingTimeInterval(-3))
            result = "Finished samples · click a head to wake it and open its conversation."
        }
    }
    func validate() throws {
        for agent in model.records {
            let expected = model.size(for: agent).panelSize
            let frame = desktop.frame(for: agent.id)
            let window = NSApp.windows.first(where: {
                $0.title == model.displayName(agent) + " · Desktop Pikmin"
            })
            guard let frame = desktop.frame(for: agent.id), frame.size == expected,
                let window, window.contentView?.bounds.size == expected
            else {
                throw SourceFailure.message(
                    "Native panel does not match \(model.size(for:agent).title): expected \(expected), panel \(String(describing:frame)), content \(String(describing:window?.contentView?.bounds)), visible \(model.visibleHeads.map(\.id))"
                )
            }
        }
        result = "Native panels match selected sizes."
    }
    func check() async {
        do {
            for size in PikminSize.allCases + PikminSize.allCases.reversed() {
                for agent in model.records { model.headSizes[agent.id] = size.rawValue }
                desktop.sync()
                try await Task.sleep(for: .milliseconds(80))
                try validate()
            }
            print(
                "PASS: real native desktop panels and content bounds follow all four sizes through forward/reverse resizing."
            )
            desktop.close()
            exit(0)
        } catch {
            FileHandle.standardError.write(
                Data(("FAIL: " + error.localizedDescription + "\n").utf8))
            desktop.close()
            exit(1)
        }
    }
    func checkSleep() async {
        do {
            try validate()
            for id in sampleIDs {
                guard let event = model.sleepEvents[id], event.isSleeping,
                    event.pose(at: .now).sleepiness == 1
                else { throw SourceFailure.message("Completed native sample did not sleep") }
            }
            guard let clicked = model.records.first else {
                throw SourceFailure.message("Missing sample head")
            }
            model.showConversation(clicked)
            guard model.sleepEvents[clicked.id]?.kind == .wake,
                model.attending.contains(clicked.id),
                NSApp.windows.contains(where: {
                    $0.title == model.displayName(clicked) + " · Pikminions" && $0.isVisible
                })
            else {
                throw SourceFailure.message(
                    "Wake activation did not keep the same-click conversation behavior")
            }
            try await Task.sleep(for: .milliseconds(1500))
            model.advanceDesktopSleep()
            guard model.sleepEvents[clicked.id] == nil, model.attending.contains(clicked.id) else {
                throw SourceFailure.message(
                    "A completed head slept again while its conversation was open")
            }
            model.advanceDesktopSleep(at: Date.now.addingTimeInterval(121))
            guard model.sleepEvents[clicked.id]?.isSleeping == true,
                model.attending.contains(clicked.id)
            else {
                throw SourceFailure.message(
                    "An untouched conversation prevented a later return to sleep")
            }
            let workingID = sampleIDs[1]
            let questionID = sampleIDs[2]
            let dockedID = sampleIDs[3]
            model.records = model.records.map { agent in
                var result = agent
                if agent.id == workingID {
                    result.state = .working
                    result.runID = "new-work"
                }
                if agent.id == questionID {
                    result.pendingRequestID = "sample-question"
                    result.pendingRequestKind = "user_input"
                }
                return result
            }
            desktop.sync()
            guard model.sleepEvents[workingID]?.kind == .wake,
                model.sleepEvents[questionID]?.kind == .wake
            else { throw SourceFailure.message("Native head did not wake for work or input") }
            model.docked.insert(dockedID)
            desktop.sync()
            guard model.sleepEvents[dockedID] == nil, desktop.frame(for: dockedID) == nil else {
                throw SourceFailure.message("A docked head retained desktop sleep state")
            }
            model.mode = .island
            desktop.sync()
            guard model.sleepEvents.isEmpty else {
                throw SourceFailure.message("Desktop sleep leaked into island mode")
            }
            model.conversationCoordinator?.closeAll()
            desktop.close()
            print(
                "PASS: native Small/Medium/Large/XL desktop heads sleep; activation wakes and opens conversation once; untouched conversations can sleep again; work/input wake; docking/island clear sleep."
            )
            exit(0)
        } catch {
            FileHandle.standardError.write(
                Data(("FAIL: " + error.localizedDescription + "\n").utf8))
            model.conversationCoordinator?.closeAll()
            desktop.close()
            exit(1)
        }
    }
    func previewActivity(_ state: AgentState, age: TimeInterval = 300) {
        model.conversationCoordinator?.closeAll()
        model.mode = .island
        model.advanceDesktopSleep()
        model.mode = .desktop
        model.records = model.records.map { agent in
            var result = agent
            result.state = state
            result.updated = Date.now.addingTimeInterval(-age)
            result.runID = state.rawValue
            result.pendingRequestID = nil
            result.pendingRequestKind = nil
            return result
        }
        model.advanceDesktopSleep(at: age > 200 ? Date.now.addingTimeInterval(-3) : .now)
        desktop.sync()
    }
    func checkSpawning() {
        desktop.close()
        let squad = SquadModel()
        let controller = DesktopSquadController(model: squad)
        squad.mode = .desktop
        squad.hidden = []
        squad.docked = []
        squad.pinned = []
        squad.maxHeads = 24
        squad.headSizes = [:]
        let prefix = "spawn-check-" + UUID().uuidString
        let ids = (0..<13).map { prefix + String($0) }
        func run() throws {
            defer {
                controller.close()
                for id in ids {
                    UserDefaults.standard.removeObject(forKey: "Pikminions.position." + id)
                }
            }
            for screen in [
                CGRect(x: 0, y: 40, width: 1400, height: 800),
                CGRect(x: -1440, y: -600, width: 1440, height: 800),
            ] {
                var occupied: [CGRect] = []
                for index in 0..<24 {
                    let frame = DesktopHeadPlacement.frame(
                        size: PikminSize.allCases[index % 4].panelSize, screen: screen,
                        occupied: occupied)
                    guard screen.contains(frame),
                        occupied.allSatisfy({
                            !frame.intersects($0.insetBy(dx: -11.99, dy: -11.99))
                        })
                    else {
                        throw SourceFailure.message(
                            "Mixed-size stack overlaps or leaves a screen with a negative origin")
                    }
                    occupied.append(frame)
                }
                let invalid = DesktopHeadPlacement.frame(
                    size: PikminSize.medium.panelSize,
                    preferred: CGPoint(x: Double.nan, y: Double.infinity), screen: screen,
                    occupied: [])
                guard screen.contains(invalid) else {
                    throw SourceFailure.message("Invalid saved coordinates did not recover")
                }
            }
            let short = CGRect(x: 0, y: 0, width: 350, height: 210)
            let size = PikminSize.medium.panelSize
            let first = DesktopHeadPlacement.frame(size: size, screen: short, occupied: [])
            let wrapped = DesktopHeadPlacement.frame(size: size, screen: short, occupied: [first])
            guard wrapped.maxX + 12 <= first.minX, wrapped.minY == first.minY else {
                throw SourceFailure.message("A full vertical stack did not wrap into a left column")
            }
            var previous: [String: CGRect] = [:]
            for index in 0..<12 {
                let id = ids[index]
                let agent = AgentRecord(
                    id: id, source: "Fixture", threadID: id, runID: id,
                    title: "Spawn sample \(index)", project: "Fixture", model: "Sample",
                    state: .working, detail: "", updated: .now, openURL: nil)
                squad.headSizes[id] =
                    (index < 2 ? PikminSize.medium : PikminSize.allCases[index % 4]).rawValue
                if index == 2, let first = previous[ids[0]] {
                    UserDefaults.standard.set(
                        [first.minX, first.minY], forKey: "Pikminions.position." + id)
                }
                let placed = NSScreen.main.map {
                    CGPoint(x: $0.visibleFrame.minX + 20, y: $0.visibleFrame.minY + 30)
                }
                if index == 3, let placed {
                    UserDefaults.standard.set(
                        [placed.x, placed.y], forKey: "Pikminions.position." + id)
                }
                squad.records.insert(agent, at: 0)
                controller.sync()
                if index == 3, let placed, controller.frame(for: id)?.origin != placed {
                    throw SourceFailure.message("A free saved position was changed")
                }
                for record in squad.records {
                    guard let frame = controller.frame(for: record.id),
                        NSScreen.screens.contains(where: { $0.visibleFrame.contains(frame) })
                    else { throw SourceFailure.message("Spawned head leaves the visible screen") }
                    if let old = previous[record.id], old != frame {
                        throw SourceFailure.message("Spawning moved an existing head")
                    }
                    for other in squad.records where other.id != record.id {
                        if let occupied = controller.frame(for: other.id),
                            frame.intersects(occupied)
                        {
                            throw SourceFailure.message(
                                "Spawned heads overlap after insertion \(index+1)")
                        }
                    }
                    previous[record.id] = frame
                }
                if index == 1, let first = previous[ids[0]], let second = previous[id] {
                    guard second.minX == first.minX, second.minY >= first.maxY + 12 else {
                        throw SourceFailure.message(
                            "New heads do not stack above an occupied spawn point")
                    }
                }
            }
            squad.records.reverse()
            controller.sync()
            for (id, frame) in previous where controller.frame(for: id) != frame {
                throw SourceFailure.message("Roster reordering moved an existing head")
            }
            squad.records.removeAll { $0.id == ids[0] }
            controller.sync()
            let id = ids[12]
            squad.records.insert(
                AgentRecord(
                    id: id, source: "Fixture", threadID: id, runID: id, title: "Reused slot",
                    project: "Fixture", model: "Sample", state: .working, detail: "", updated: .now,
                    openURL: nil), at: 0)
            controller.sync()
            guard controller.frame(for: id) == previous[ids[0]] else {
                throw SourceFailure.message("A retired head's free spawn slot was not reused")
            }
            let saved = Dictionary(
                uniqueKeysWithValues: squad.records.compactMap { agent in
                    controller.frame(for: agent.id).map { (agent.id, $0) }
                })
            controller.close()
            let restored = DesktopSquadController(model: squad)
            defer { restored.close() }
            restored.sync()
            for (id, frame) in saved where restored.frame(for: id) != frame {
                throw SourceFailure.message("Saved stack did not survive panel recreation")
            }
        }
        do {
            try run()
            print(
                "PASS: sequential native spawns stack without overlap, retain moved/saved mixed-size panels, reuse freed slots and restore positions."
            )
            exit(0)
        } catch {
            FileHandle.standardError.write(
                Data(("FAIL: " + error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }
    private func after(_ delay: Double, _ action: @escaping @MainActor () -> Void) {
        let timer = Timer(timeInterval: delay, repeats: false) { _ in
            MainActor.assumeIsolated { action() }
        }
        menuTimers.append(timer)
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
    }
    func checkMenu(automatic: Bool = true) {
        for timer in menuTimers { timer.invalidate() }
        menuTimers = []
        NotificationCenter.default.removeObserver(self)
        menuAutomatic = automatic
        menuStage = 0
        trackingMenu = nil
        highlightedTitle = nil
        trackedHeadID = nil
        trackedFrame = nil
        result = "Right-click a sample head, then highlight a menu item."
        // AppKit sends menu tracking notifications synchronously on its UI
        // thread. Selector delivery keeps NSMenu references on that thread.
        NotificationCenter.default.addObserver(
            self, selector: #selector(menuBegan(_:)), name: NSMenu.didBeginTrackingNotification,
            object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(menuEnded(_:)), name: NSMenu.didEndTrackingNotification,
            object: nil)
        if automatic {
            after(0.2) { [self] in
                NSApp.activate(ignoringOtherApps: true)
                guard let agent = model.records.first, let frame = desktop.frame(for: agent.id),
                    let window = NSApp.windows.first(where: {
                        $0.title == model.displayName(agent) + " · Desktop Pikmin"
                    }), let root = window.contentView
                else {
                    menuFailure("sample head unavailable")
                    return
                }
                @MainActor func anchor(in view: NSView) -> IslandContextMenuView? {
                    if let anchor = view as? IslandContextMenuView { return anchor }
                    for child in view.subviews { if let found = anchor(in: child) { return found } }
                    return nil
                }
                guard !frame.isEmpty, let menuView = anchor(in: root) else {
                    menuFailure("native menu anchor unavailable")
                    return
                }
                menuView.showMenu()
            }
        }
        after(automatic ? 5 : 30) { [self] in
            menuFailure(
                trackingMenu == nil
                    ? "native context menu never opened" : "menu refresh probe timed out")
        }
    }
    @objc private func menuBegan(_ notice: Notification) {
        guard trackingMenu == nil, let menu = notice.object as? NSMenu else { return }
        trackingMenu = menu
        after(0.3) { [self] in
            guard let id = model.contextMenuHeads.first, let frame = desktop.frame(for: id) else {
                menuFailure("menu did not pause its source head")
                return
            }
            trackedHeadID = id
            trackedFrame = frame
            highlightedTitle = menu.highlightedItem?.title
            trackedItems = menu.items
            exerciseMenu()
        }
    }
    @objc private func menuEnded(_ notice: Notification) {
        guard let menu = notice.object as? NSMenu, menu === trackingMenu, menuStage < 4 else {
            return
        }
        menuFailure(
            menuStage == 0
                ? "context menu closed before refresh stimulus"
                : "context menu closed during background refresh")
    }
    private func exerciseMenu() {
        guard let menu = trackingMenu else {
            menuFailure("context menu unavailable")
            return
        }
        guard let id = trackedHeadID, desktop.frame(for: id) == trackedFrame else {
            menuFailure("menu source moved or retired during interaction")
            return
        }
        if let title = highlightedTitle, menu.highlightedItem?.title != title {
            menuFailure("context menu lost the highlighted item during snapshot refresh")
            return
        }
        guard menu.items.count == trackedItems.count,
            zip(menu.items, trackedItems).allSatisfy({ $0 === $1 })
        else {
            menuFailure("context menu replaced its action items during snapshot refresh")
            return
        }
        if menuStage == 4 {
            for timer in menuTimers { timer.invalidate() }
            NotificationCenter.default.removeObserver(self)
            menu.cancelTrackingWithoutAnimation()
            after(0.1) { [self] in
                guard model.contextMenuHeads.isEmpty, desktop.frame(for: id) == nil else {
                    menuFailure("deferred head retirement did not finish after menu close")
                    return
                }
                result =
                    "PASS: menu items and source survive refresh, motion and retirement until close."
                print(
                    "PASS: real desktop context menu preserves item identity and source frame through four snapshot updates, attention/success motion, visibility eviction and source removal; deferred retirement completes on close."
                )
                if menuAutomatic {
                    desktop.close()
                    exit(0)
                }
            }
            return
        }
        menuStage += 1
        model.records = model.records.map { agent in
            var result = agent
            result.updated = Date(timeIntervalSince1970: Double(menuStage))
            result.output = "Sample background update \(menuStage)"
            return result
        }
        if menuStage == 2 {
            desktop.celebrate(id)
            desktop.faceBubble(id, direction: 1)
        }
        if menuStage == 3 { model.hidden.insert(id) }
        if menuStage == 4 { model.records.removeAll { $0.id == id } }
        desktop.sync()
        after(0.3) { [self] in exerciseMenu() }
    }
    private func menuFailure(_ reason: String) {
        for timer in menuTimers { timer.invalidate() }
        NotificationCenter.default.removeObserver(self)
        menuStage = 4
        trackingMenu?.cancelTrackingWithoutAnimation()
        desktop.close()
        result = "FAIL: " + reason
        FileHandle.standardError.write(Data(("FAIL: " + reason + "\n").utf8))
        if menuAutomatic { exit(1) }
    }
}
@main struct HeadSizeFixture: App {
    @State private var samples = HeadSizeSamples()
    var body: some Scene {
        Window(
            samples.sleepMode ? "Pikminions Sleep Fixture" : "Pikminions Size Fixture", id: "sizes"
        ) {
            VStack(alignment: .leading, spacing: 18) {
                Text(samples.sleepMode ? "Sleeping desktop Pikmin" : "Desktop head sizes").font(
                    .headline)
                Text("Sample data only · no live connection or credentials").font(.caption)
                    .foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 18) {
                    ForEach(samples.sampleIDs, id: \.self) { id in
                        VStack {
                            if samples.reduceMotion,
                                let agent = samples.model.records.first(where: { $0.id == id })
                            {
                                let size = samples.model.size(for: agent)
                                PikminDrawing(
                                    species: samples.model.species(for: agent), mood: agent.mood,
                                    growth: samples.model.growth, time: 0,
                                    rest: samples.model.sleepEvents[id]?.reducedMotionPose ?? .awake
                                )
                                .frame(width: size.artSize.width, height: size.artSize.height)
                                .frame(
                                    width: size.panelSize.width, height: size.panelSize.height,
                                    alignment: .top)
                            } else {
                                DesktopHead(model: samples.model, id: id)
                            }
                            Text(
                                samples.model.records.first(where: { $0.id == id }).map {
                                    samples.model.size(for: $0).title
                                } ?? "Removed sample"
                            ).font(.caption)
                        }.frame(width: 142, height: 218, alignment: .top)
                    }
                }
                Text(samples.result).font(.caption)
                if samples.sleepMode {
                    HStack {
                        Button("Sleeping") { samples.previewActivity(.finished) }
                        Button("Nearly asleep") { samples.previewActivity(.finished, age: 117) }
                        Button("Working") { samples.previewActivity(.working) }
                        Toggle("Static pose preview", isOn: $samples.reduceMotion)
                    }.controlSize(.small)
                    HStack(spacing: 12) {
                        ForEach(PikminSpecies.allCases) { species in
                            PikminDrawing(
                                species: species, mood: .happy, growth: .reference, time: 0,
                                rest: .asleep
                            ).frame(width: 52, height: 64)
                        }
                    }.accessibilityLabel(
                        "Static sleeping poses for all nine species, also used with Reduce Motion")
                }
                Button("Check native panels") {
                    do { try samples.validate() } catch {
                        samples.result = error.localizedDescription
                    }
                }
                if !samples.sleepMode {
                    Button("Arm menu check") { samples.checkMenu(automatic: false) }
                }
            }.padding(22).preferredColorScheme(.dark)
                .task {
                    samples.desktop.sync()
                    if CommandLine.arguments.contains("--check") { await samples.check() }
                    if CommandLine.arguments.contains("--spawn-check") { samples.checkSpawning() }
                    if CommandLine.arguments.contains("--menu-check") { samples.checkMenu() }
                    if CommandLine.arguments.contains("--sleep-check") {
                        await samples.checkSleep()
                    }
                }
                .onDisappear { samples.desktop.close() }
        }.defaultSize(width: 680, height: 340)
    }
}
