// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Antille
import AppKit
import SwiftUI
import UserNotifications

@main enum PikminionsLauncher {
    @MainActor static func main() {
        let args = CommandLine.arguments
        if args.contains("--check-streaming") {
            Task { @MainActor in
                do {
                    try runStreamingChecks()
                    exit(0)
                } catch {
                    FileHandle.standardError.write(
                        Data(("Streaming checks: " + error.localizedDescription + "\n").utf8))
                    exit(1)
                }
            }
            dispatchMain()
        }
        if args.contains("--check") {
            Task { @MainActor in
                do {
                    try runPikminChecks()
                    try runStreamingChecks()
                    if AppRuntime.fixture { try await runFixtureConversationChecks() }
                    exit(0)
                } catch {
                    FileHandle.standardError.write(
                        Data(("Pikminions: " + error.localizedDescription + "\n").utf8))
                    exit(1)
                }
            }
            dispatchMain()
        }
        if args.contains("--live-canary") {
            Task { @MainActor in
                do {
                    try await LiveCanary.run(arguments: args)
                    exit(0)
                } catch {
                    FileHandle.standardError.write(
                        Data(("Live canary failed: " + error.localizedDescription + "\n").utf8))
                    exit(1)
                }
            }
            dispatchMain()
        }
        do {
            if let index = args.firstIndex(of: "--export-art"), index + 1 < args.count {
                _ = NSApplication.shared
                try exportPikminArt(to: URL(fileURLWithPath: args[index + 1]))
                return
            }
        } catch {
            FileHandle.standardError.write(
                Data(("Pikminions: " + error.localizedDescription + "\n").utf8))
            exit(1)
        }
        PikminionsApplication.main()
    }
}
struct PikminionsApplication: App {
    @NSApplicationDelegateAdaptor(PikminionsDelegate.self) private var delegate
    @Environment(\.openWindow) private var openWindow
    var body: some Scene {
        Window(AppRuntime.fixture ? "Pikminions — Fixture" : "Pikminions", id: "squad") {
            SquadView(model: delegate.model).frame(minWidth: 860, minHeight: 650)
        }.defaultSize(width: 980, height: 740)
        MenuBarExtra {
            Button("Open Pikminions") {
                openWindow(id: "squad")
                NSApp.activate(ignoringOtherApps: true)
            }
            ForEach(Array(delegate.model.visibleHeads.prefix(8))) { agent in
                Button(delegate.model.displayName(agent) + " · " + agent.statusLabel) {
                    delegate.model.showConversation(agent)
                }
            }
            Divider()
            Button("Connect T3") { delegate.model.connect() }.disabled(delegate.model.connecting)
            Button("Preview chirp") { delegate.model.chirps.preview() }
            Button("Quit Pikminions") {
                delegate.model.stop()
                NSApp.terminate(nil)
            }.keyboardShortcut("q")
        } label: {
            Image(systemName: "leaf.fill")
        }
    }
}
@MainActor
final class PikminionsDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let model = SquadModel()
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self
        model.start { [weak self] in self?.showWindow() }
        showWindow()
    }
    func applicationWillTerminate(_ notification: Notification) { model.stop() }
    func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.title.hasPrefix("Pikminions") })?.makeKeyAndOrderFront(nil)
    }
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        guard let id = response.notification.request.content.userInfo["agentID"] as? String else {
            return
        }
        await MainActor.run {
            guard let agent = self.model.records.first(where: { $0.id == id }) else { return }
            self.model.select(agent)
            self.model.open(agent)
        }
    }
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
