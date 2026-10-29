// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import SwiftUI
import AppKit
import UserNotifications
import Antille

@main enum PikminionsLauncher {
    @MainActor static func main() {
        let args=CommandLine.arguments
        if args.contains("--check-streaming") {
            Task { @MainActor in
                do {try runStreamingChecks();exit(0)}
                catch {FileHandle.standardError.write(Data(("Streaming checks: "+error.localizedDescription+"\n").utf8));exit(1)}
            }
            dispatchMain()
        }
        if args.contains("--check") {
            Task { @MainActor in
                do {try runPikminChecks();try runStreamingChecks();if AppRuntime.fixture {try await runFixtureConversationChecks()};exit(0)}
                catch {FileHandle.standardError.write(Data(("Pikminions: "+error.localizedDescription+"\n").utf8));exit(1)}
            }
            dispatchMain()
        }
        if args.contains("--live-canary") {
            Task { @MainActor in
                do {try await LiveCanary.run(arguments:args);exit(0)}
                catch {FileHandle.standardError.write(Data(("Live canary failed: "+error.localizedDescription+"\n").utf8));exit(1)}
            }
            dispatchMain()
        }
        do {
            if let index=args.firstIndex(of:"--export-art"),index+1<args.count {
                _=NSApplication.shared
                try exportPikminArt(to:URL(fileURLWithPath:args[index+1]));return
            }
        } catch {FileHandle.standardError.write(Data(("Pikminions: "+error.localizedDescription+"\n").utf8));exit(1)}
        PikminionsApplication.main()
    }
}
struct PikminionsApplication:App {
    @NSApplicationDelegateAdaptor(PikminionsDelegate.self) private var delegate
    @Environment(\.openWindow) private var openWindow
    var body:some Scene {
        Window(AppRuntime.fixture ? "Pikminions — Fixture":"Pikminions",id:"squad") {
            SquadView(model:delegate.model).frame(minWidth:860,minHeight:650)
        }.defaultSize(width:980,height:740)
        MenuBarExtra {
            Button("Open Pikminions"){openWindow(id:"squad");NSApp.activate(ignoringOtherApps:true)}
            ForEach(Array(delegate.model.visibleHeads.prefix(8))) {agent in
                Button(delegate.model.displayName(agent)+" · "+agent.statusLabel){delegate.model.showConversation(agent)}
            }
            Divider()
            Button("Connect T3"){delegate.model.connect()}.disabled(delegate.model.connecting)
            Button("Preview chirp"){delegate.model.chirps.preview()}
            Button("Quit Pikminions"){delegate.model.stop();NSApp.terminate(nil)}.keyboardShortcut("q")
        } label:{Image(systemName:"leaf.fill")}
    }
}
@MainActor final class PikminionsDelegate:NSObject,NSApplicationDelegate,UNUserNotificationCenterDelegate {
    let model=SquadModel()
    func applicationDidFinishLaunching(_ notification:Notification) {
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate=self
        model.start { [weak self] in self?.showWindow() }
        showWindow()
    }
    func applicationWillTerminate(_ notification:Notification){model.stop()}
    func showWindow() {
        NSApp.activate(ignoringOtherApps:true)
        NSApp.windows.first(where:{$0.title.hasPrefix("Pikminions")})?.makeKeyAndOrderFront(nil)
    }
    nonisolated func userNotificationCenter(_ center:UNUserNotificationCenter,didReceive response:UNNotificationResponse) async {
        guard let id=response.notification.request.content.userInfo["agentID"] as? String else{return}
        await MainActor.run {
            guard let agent=self.model.records.first(where:{$0.id==id}) else{return}
            self.model.select(agent);self.model.open(agent)
        }
    }
    nonisolated func userNotificationCenter(_ center:UNUserNotificationCenter,willPresent notification:UNNotification) async -> UNNotificationPresentationOptions {
        [.banner,.sound]
    }
}
struct SquadView:View {
    @Bindable var model:SquadModel
    @State private var tab="Squad"
    private var selectedSpecies:PikminSpecies {model.selected.map{model.species(for:$0)} ?? model.selectedSpecies}
    var body:some View {
        HStack(spacing:0) {
            sidebar
            Divider()
            VStack(spacing:0) {
                HStack {
                    VStack(alignment:.leading,spacing:4) {
                        Text(AppRuntime.fixture ? "Pikminions · Fixture":"Pikminions").font(.system(size:22,weight:.semibold))
                        Text(AppRuntime.fixture ? "Sample data · no live connections · silent":model.selected?.project ?? "A little head for every agent.")
                            .font(.system(size:12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("Display",selection:$model.mode) {ForEach(SquadMode.allCases,id:\.self){Text($0.rawValue).tag($0)}}
                        .pickerStyle(.segmented).labelsHidden().fixedSize(horizontal:true,vertical:false).frame(width:210).onChange(of:model.mode){_,_ in model.preferencesChanged()}
                }.padding(.horizontal,28).padding(.top,24).padding(.bottom,18)
                HStack {
                    Picker("Section",selection:$tab){ForEach(["Squad","Appearance","Connections"],id:\.self){Text($0)}}
                        .pickerStyle(.segmented).labelsHidden().frame(width:310)
                    Spacer()
                }.padding(.horizontal,28).padding(.bottom,10)
                ScrollView {
                    VStack(alignment:.leading,spacing:22) {
                        if tab=="Connections" {connections}
                        else {
                            selectedHead
                            if tab=="Squad" {speciesGallery}
                            else {appearance}
                        }
                    }.padding(28).frame(maxWidth:.infinity,alignment:.topLeading)
                }.scrollIndicators(.hidden)
                if let error=model.error {
                    HStack(alignment:.top,spacing:8) {
                        Image(systemName:"exclamationmark.circle")
                        Text(error).textSelection(.enabled)
                        Spacer()
                        Button {model.error=nil} label:{Image(systemName:"xmark")}.buttonStyle(.plain).accessibilityLabel("Dismiss message")
                    }.font(.system(size:11)).foregroundStyle(.secondary).padding(14)
                    .background(.primary.opacity(0.04))
                }
            }
            .background(Color(nsColor:.windowBackgroundColor))
        }
        .sheet(item:$model.lookEditor) {request in PikminLookEditor(model:model,request:request)}
    }
    private var sidebar:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack(spacing:7) {
                Image(systemName:"leaf.fill").foregroundStyle(.secondary)
                Text("Your squad").font(.system(size:14,weight:.semibold))
                Spacer()
                Text("\(model.listed.count)").font(.system(size:11)).foregroundStyle(.secondary)
            }.padding(.top,6)
            TextField("Find an agent",text:$model.search).textFieldStyle(.roundedBorder).font(.system(size:12))
            Picker("Project",selection:$model.projectFilter) {
                ForEach(model.projects,id:\.self){Text($0).tag($0)}
            }.labelsHidden().controlSize(.small)
            ScrollView {
                LazyVStack(spacing:3) {
                    if model.listed.isEmpty {
                        VStack(alignment:.leading,spacing:8) {
                            Text("No agents connected").font(.system(size:12,weight:.medium))
                            Text("Connect T3 to see your running conversations here.").font(.system(size:11)).foregroundStyle(.secondary)
                            Button(model.connecting ? "Connecting…":"Connect T3"){model.connect()}.disabled(model.connecting).controlSize(.small)
                        }.padding(.vertical,20)
                    }
                    ForEach(model.listed) {agent in
                        Button {model.selectedID=agent.id} label:{
                            HStack(spacing:9) {
                                PikminHead(species:model.species(for:agent),mood:agent.stale ? .disconnected:agent.mood,growth:model.growth,animated:false,appearance:model.look(for:agent))
                                    .frame(width:28,height:36)
                                VStack(alignment:.leading,spacing:3) {
                                    HStack(spacing:4) {
                                        if agent.parentID != nil {Image(systemName:"arrow.turn.down.right").font(.system(size:9))}
                                        Text(model.displayName(agent)).lineLimit(1).font(.system(size:12,weight:.medium))
                                    }
                                    Text(agent.stale ? "Recorded / disconnected":agent.statusLabel).font(.system(size:10)).foregroundStyle(.secondary)
                                }
                                Spacer(minLength:0)
                                if model.pinned.contains(agent.id){Image(systemName:"pin.fill").font(.system(size:9)).foregroundStyle(.secondary)}
                            }.padding(.horizontal,8).padding(.vertical,7)
                            .background(model.selectedID==agent.id ? Color.primary.opacity(0.065):.clear,in:RoundedRectangle(cornerRadius:8))
                        }.buttonStyle(.plain).contextMenu {
                            Toggle("Vocal mode",isOn:Binding(get:{model.vocal.contains(agent.id)},set:{model.setVocalMode($0,for:agent)})).disabled(!agent.isInteractive)
                            Button("Open conversation"){model.open(agent)}
                            Button(model.pinned.contains(agent.id) ? "Unpin":"Keep visible"){model.togglePin(agent)}
                            Button(model.muted.contains(agent.id) ? "Unmute":"Mute"){model.toggleMute(agent)}
                            Button("Customize Pikmin…"){model.editLook(model.look(for:agent),for:agent)}
                            Button("Hide head"){model.hide(agent)}
                        }
                    }
                }
            }
            Spacer(minLength:0)
            VStack(alignment:.leading,spacing:7) {
                Label("T3 · "+model.t3Status,systemImage:"circle.dotted")
                Label(model.codexStatus,systemImage:"terminal")
            }.font(.system(size:10)).foregroundStyle(.secondary)
            Button {tab="Connections"} label:{Label("Connections & alerts",systemImage:"gearshape")}
                .buttonStyle(.plain).font(.system(size:11))
        }.padding(18).frame(width:220)
        .background(Color(nsColor:.windowBackgroundColor))
    }
    private var selectedHead:some View {
        HStack(spacing:28) {
            PikminHead(species:selectedSpecies,mood:model.selected.map{$0.stale ? .disconnected:$0.mood} ?? model.previewMood,growth:model.growth,animated:!(model.selected.map{model.attending.contains($0.id)} ?? false),focusGaze:model.selected.flatMap{model.attentionGazes[$0.id]},appearance:model.previewLook)
                .frame(width:112,height:140)
                .padding(.horizontal,18)
            VStack(alignment:.leading,spacing:10) {
                if let agent=model.selected {
                    Text(model.displayName(agent)).font(.system(size:20,weight:.medium)).fixedSize(horizontal:false,vertical:true).lineLimit(3)
                    Label(agent.stale ? "Source disconnected":agent.statusLabel,systemImage:agent.attention.rank>1 ? "hand.raised":"circle.dotted")
                        .font(.system(size:12)).foregroundStyle(.secondary)
                    Text(agent.project+" · "+agent.model).font(.system(size:11)).foregroundStyle(.tertiary)
                    if !agent.detail.isEmpty {Text(agent.detail).font(.system(size:12)).foregroundStyle(.secondary)}
                    HStack(spacing:10) {
                        Button("Talk"){model.showConversation(agent)}.controlSize(.small)
                        Button("Rename…"){model.renameHead(agent)}.controlSize(.small)
                        Button(model.pinned.contains(agent.id) ? "Unpin":"Keep visible"){model.togglePin(agent)}.controlSize(.small)
                        Button(model.muted.contains(agent.id) ? "Unmute":"Mute"){model.toggleMute(agent)}.controlSize(.small)
                        Button(model.docked.contains(agent.id) ? "To desktop":"To island"){model.docked.contains(agent.id) ? model.undock(agent):model.dismiss(agent)}.controlSize(.small)
                    }
                } else {
                    Text(model.previewLook?.name ?? selectedSpecies.name+" Pikmin").font(.system(size:24,weight:.medium))
                    Text("Preview").font(.system(size:11,weight:.medium)).foregroundStyle(.secondary)
                    Text("Choose a head below. Connect an agent to make it theirs.").font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                }
            }
            Spacer(minLength:0)
        }.frame(maxWidth:.infinity,minHeight:155,alignment:.leading)
    }
    private var speciesGallery:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {
                Text("Choose a Pikmin").font(.system(size:13,weight:.semibold))
                Spacer()
                if model.selected != nil {Button("Preview all"){model.selectedID=nil}.buttonStyle(.plain).font(.system(size:11))}
            }
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:8),count:3),spacing:8) {
                ForEach(PikminSpecies.allCases) {species in
                    SpeciesCell(species:species,selected:model.previewLook == nil && species==selectedSpecies,growth:model.growth) {
                        model.setSpecies(species,for:model.selected)
                    }
                }
            }
            customLooks
        }
    }
    private var customLooks:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {
                Text("Custom looks").font(.system(size:13,weight:.semibold))
                Spacer()
                Button("New look…"){model.editLook(for:model.selected)}.controlSize(.small)
            }
            if model.customLooks.isEmpty {
                Text("Create a look with your own colors, eyes and stem. Save it once and use it for any agent.").font(.system(size:11)).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:8),count:3),spacing:8) {
                    ForEach(model.customLooks) {look in
                        Button {model.chooseLook(look,for:model.selected)} label:{
                            VStack(spacing:5) {
                                PikminHead(species:look.species,mood:.calm,growth:model.growth,animated:false,tracksCursor:false,appearance:look).frame(width:57,height:68)
                                Text(look.name).font(.system(size:11)).lineLimit(2)
                            }.frame(maxWidth:.infinity).padding(.vertical,12)
                            .background(model.previewLook?.id==look.id ? Color.primary.opacity(0.055):.clear,in:RoundedRectangle(cornerRadius:12))
                        }.buttonStyle(.plain).accessibilityLabel("Use "+look.name)
                        .accessibilityAddTraits(model.previewLook?.id==look.id ? .isSelected:[])
                        .contextMenu {
                            Button("Edit look…"){model.editLook(look)}
                            Button("Duplicate…"){var copy=look;copy.id=UUID().uuidString;copy.name=look.name+" copy";model.editLook(copy)}
                        }
                    }
                }
                if let look=model.previewLook {Button("Edit \(look.name)…"){model.editLook(look,for:model.selected)}.controlSize(.small)}
            }
        }
    }
    private var appearance:some View {
        VStack(alignment:.leading,spacing:22) {
            VStack(alignment:.leading,spacing:10) {
                Text("Growth").font(.system(size:13,weight:.semibold))
                Picker("Growth",selection:$model.growth){ForEach(PikminGrowth.allCases,id:\.self){Text($0.title).tag($0)}}
                    .pickerStyle(.segmented).frame(width:320).onChange(of:model.growth){_,_ in model.preferencesChanged()}
            }
            if model.selected==nil {
                VStack(alignment:.leading,spacing:10) {
                    Text("Preview expression").font(.system(size:13,weight:.semibold))
                    Picker("Expression",selection:$model.previewMood){ForEach(PikminMood.allCases,id:\.self){Text($0.rawValue.capitalized).tag($0)}}.frame(width:250)
                    Text("Preview expressions do not change a live agent’s status.").font(.system(size:11)).foregroundStyle(.secondary)
                }
            }
            Text("Toss a desktop head toward the notch to dock it. Use To desktop to bring it back.").font(.system(size:11)).foregroundStyle(.secondary)
            Toggle("Gravity for loose heads",isOn:$model.gravityEnabled).onChange(of:model.gravityEnabled){_,_ in model.preferencesChanged()}
            Text("Released heads settle along the bottom of the screen. Pin a head’s position to keep it placed.").font(.system(size:11)).foregroundStyle(.secondary)
            Stepper("Show up to \(model.maxHeads) heads",value:$model.maxHeads,in:1...24)
                .onChange(of:model.maxHeads){_,_ in model.preferencesChanged()}
            Button("Restore hidden heads"){model.revealAll()}
            speciesGallery
        }
    }
    private var connections:some View {
        VStack(alignment:.leading,spacing:24) {
            VStack(alignment:.leading,spacing:12) {
                Label("T3 Code",systemImage:"point.3.connected.trianglepath.dotted").font(.system(size:15,weight:.semibold))
                Text(model.t3Status).font(.system(size:12)).foregroundStyle(.secondary)
                Text("Connect once to follow agents, reply, answer questions and manage conversations.").font(.system(size:12)).foregroundStyle(.secondary)
                HStack {
                    Button(model.connecting ? "Connecting…":"Connect T3"){model.connect()}.disabled(model.connecting)
                    if model.t3Status.hasPrefix("Connected") {Button("Disconnect & revoke"){model.disconnect()}}
                }
            }
            Divider()
            VStack(alignment:.leading,spacing:10) {
                Label("Codex",systemImage:"terminal").font(.system(size:15,weight:.semibold))
                Text(model.codexStatus).font(.system(size:12)).foregroundStyle(.secondary)
                Toggle("Include recorded Codex conversations",isOn:$model.showRecorded).font(.system(size:12))
                Text("A shared live server is observed when available. Saved sessions are labeled recorded and never pretend to be running.").font(.system(size:11)).foregroundStyle(.secondary)
            }
            Divider()
            VStack(alignment:.leading,spacing:10) {
                Label("Antille",systemImage:"capsule.tophalf.filled").font(.system(size:15,weight:.semibold))
                Text(model.islandStatus).font(.system(size:12)).foregroundStyle(.secondary)
                HStack {
                    Button("Pair with Antille"){model.pairHost()}
                    Button("Open Antille") {
                        let name=AppRuntime.fixture ? "AntilleFixture.app":"Antille.app"
                        let sibling=Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appending(path:"QOL/antille/dist/"+name)
                        let app=NSWorkspace.shared.urlForApplication(withBundleIdentifier:"dev.upsided.antille"+(AppRuntime.fixture ? ".fixture":"")) ?? sibling
                        NSWorkspace.shared.openApplication(at:app,configuration:NSWorkspace.OpenConfiguration())
                    }
                }
                Text("Approve Pikminions in Antille’s Sources tab, then press Pair again. Without a host, Pikminions uses the same library to show its own island.").font(.system(size:11)).foregroundStyle(.secondary)
            }
            Divider()
            VStack(alignment:.leading,spacing:10) {
                Label("Sounds & alerts",systemImage:"speaker.wave.2").font(.system(size:15,weight:.semibold))
                HStack {
                    Button(model.alertsEnabled ? "Alerts enabled":"Enable alerts…"){Task{await model.enableAlerts()}}
                    Button("Preview chirp"){model.chirps.preview()}
                }
                Text("Short original chirps for a finished turn, a question, or a failure. System notification preferences and Focus govern delivery.").font(.system(size:11)).foregroundStyle(.secondary)
            }
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}
private struct SpeciesCell:View {
    let species:PikminSpecies
    let selected:Bool
    let growth:PikminGrowth
    let action:()->Void
    @State private var hover=false
    var body:some View {
        Button(action:action) {
            VStack(spacing:5) {
                PikminHead(species:species,mood:hover ? .working:.calm,growth:growth,animated:hover)
                    .frame(width:57,height:68)
                Text(species.name).font(.system(size:11,weight:selected ? .semibold:.regular))
                    .foregroundStyle(selected ? .primary:.secondary)
            }.frame(maxWidth:.infinity).padding(.vertical,12)
            .background(selected ? Color.primary.opacity(0.055):.clear,in:RoundedRectangle(cornerRadius:12))
        }.buttonStyle(.plain).onHover{hover=$0}
        .accessibilityLabel(species.name+" Pikmin").accessibilityAddTraits(selected ? .isSelected:[])
    }
}
