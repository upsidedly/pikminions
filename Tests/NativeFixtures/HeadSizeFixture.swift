// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import AppKit
import SwiftUI
@testable import PikminionsApp
@testable import Antille

/// Real desktop views and floating panels, with no model.start(), host or T3.
@MainActor @Observable final class HeadSizeSamples:NSObject {
    let model:SquadModel
    let desktop:DesktopSquadController
    let sampleIDs:[String]
    var result="Right-click a sample head → Size."
    private var menuTimers:[Timer]=[]
    private var trackingMenu:NSMenu?
    private var highlightedTitle:String?
    private var trackedItems:[NSMenuItem]=[]
    private var trackedHeadID:String?
    private var trackedFrame:CGRect?
    private var menuStage=0
    private var menuAutomatic=true
    override init() {
        let model=SquadModel()
        let saved=model.headSizes
        model.mode = .desktop;model.hidden=[];model.docked=[];model.pinned=[];model.headSizes=[:]
        model.records=PikminSize.allCases.enumerated().map {index,size in
            AgentRecord(id:"size-sample-\(size.rawValue)",source:"Fixture",threadID:"size-sample-\(index)",runID:"sample-run",title:"Size fixture · \(size.title)",project:"Fixture",model:"Sample",state:.working,detail:"",updated:.distantPast,openURL:nil)
        }
        model.speciesOverrides=Dictionary(uniqueKeysWithValues:zip(model.records.map(\.id),["blue","red","yellow","glow"]))
        for (agent,size) in zip(model.records,PikminSize.allCases) {model.headSizes[agent.id]=saved[agent.id].flatMap(PikminSize.init(rawValue:))?.rawValue ?? size.rawValue}
        self.model=model;desktop=DesktopSquadController(model:model);sampleIDs=model.records.map(\.id)
        model.desktop=desktop
        super.init()
    }
    func validate() throws {
        for agent in model.records {
            let expected=model.size(for:agent).panelSize
            guard let frame=desktop.frame(for:agent.id),frame.size==expected,
                  let window=NSApp.windows.first(where:{$0.title==model.displayName(agent)+" · Desktop Pikmin"}),
                  window.contentView?.bounds.size==expected else {throw SourceFailure.message("Native panel does not match \(model.size(for:agent).title)")}
        }
        result="Native panels match selected sizes."
    }
    func check() async {
        do {
            for size in PikminSize.allCases+PikminSize.allCases.reversed() {
                for agent in model.records {model.headSizes[agent.id]=size.rawValue}
                desktop.sync();try await Task.sleep(for:.milliseconds(80));try validate()
            }
            print("PASS: real native desktop panels and content bounds follow all four sizes through forward/reverse resizing.")
            desktop.close();exit(0)
        } catch {FileHandle.standardError.write(Data(("FAIL: "+error.localizedDescription+"\n").utf8));desktop.close();exit(1)}
    }
    private func after(_ delay:Double,_ action:@escaping @MainActor ()->Void) {
        let timer=Timer(timeInterval:delay,repeats:false) {_ in MainActor.assumeIsolated {action()}}
        menuTimers.append(timer)
        RunLoop.main.add(timer,forMode:.common);RunLoop.main.add(timer,forMode:.eventTracking)
    }
    func checkMenu(automatic:Bool=true) {
        for timer in menuTimers {timer.invalidate()};menuTimers=[]
        NotificationCenter.default.removeObserver(self)
        menuAutomatic=automatic;menuStage=0;trackingMenu=nil;highlightedTitle=nil;trackedHeadID=nil;trackedFrame=nil
        result="Right-click a sample head, then highlight a menu item."
        // AppKit sends menu tracking notifications synchronously on its UI
        // thread. Selector delivery keeps NSMenu references on that thread.
        NotificationCenter.default.addObserver(self,selector:#selector(menuBegan(_:)),name:NSMenu.didBeginTrackingNotification,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(menuEnded(_:)),name:NSMenu.didEndTrackingNotification,object:nil)
        if automatic {after(0.2) { [self] in
            NSApp.activate(ignoringOtherApps:true)
            guard let agent=model.records.first,let frame=desktop.frame(for:agent.id),
                  let window=NSApp.windows.first(where:{$0.title==model.displayName(agent)+" · Desktop Pikmin"}),let root=window.contentView else {menuFailure("sample head unavailable");return}
            @MainActor func anchor(in view:NSView)->IslandContextMenuView? {
                if let anchor=view as? IslandContextMenuView {return anchor}
                for child in view.subviews {if let found=anchor(in:child) {return found}}
                return nil
            }
            guard !frame.isEmpty,let menuView=anchor(in:root) else {menuFailure("native menu anchor unavailable");return}
            menuView.showMenu()
        }}
        after(automatic ? 5:30) { [self] in menuFailure(trackingMenu==nil ? "native context menu never opened":"menu refresh probe timed out")}
    }
    @objc private func menuBegan(_ notice:Notification) {
        guard trackingMenu==nil,let menu=notice.object as? NSMenu else{return}
        trackingMenu=menu
        after(0.3) { [self] in
            guard let id=model.contextMenuHeads.first,let frame=desktop.frame(for:id) else {menuFailure("menu did not pause its source head");return}
            trackedHeadID=id;trackedFrame=frame
            highlightedTitle=menu.highlightedItem?.title;trackedItems=menu.items;exerciseMenu()
        }
    }
    @objc private func menuEnded(_ notice:Notification) {
        guard let menu=notice.object as? NSMenu,menu===trackingMenu,menuStage<4 else{return}
        menuFailure(menuStage==0 ? "context menu closed before refresh stimulus":"context menu closed during background refresh")
    }
    private func exerciseMenu() {
        guard let menu=trackingMenu else {menuFailure("context menu unavailable");return}
        guard let id=trackedHeadID,desktop.frame(for:id)==trackedFrame else {menuFailure("menu source moved or retired during interaction");return}
        if let title=highlightedTitle,menu.highlightedItem?.title != title {menuFailure("context menu lost the highlighted item during snapshot refresh");return}
        guard menu.items.count==trackedItems.count,zip(menu.items,trackedItems).allSatisfy({$0===$1}) else {menuFailure("context menu replaced its action items during snapshot refresh");return}
        if menuStage==4 {
            for timer in menuTimers {timer.invalidate()}
            NotificationCenter.default.removeObserver(self)
            menu.cancelTrackingWithoutAnimation()
            after(0.1) { [self] in
                guard model.contextMenuHeads.isEmpty,desktop.frame(for:id)==nil else {menuFailure("deferred head retirement did not finish after menu close");return}
                result="PASS: menu items and source survive refresh, motion and retirement until close."
                print("PASS: real desktop context menu preserves item identity and source frame through four snapshot updates, attention/success motion, visibility eviction and source removal; deferred retirement completes on close.")
                if menuAutomatic {desktop.close();exit(0)}
            }
            return
        }
        menuStage+=1
        model.records=model.records.map {agent in var result=agent;result.updated=Date(timeIntervalSince1970:Double(menuStage));result.output="Sample background update \(menuStage)";return result}
        if menuStage==2 {desktop.celebrate(id);desktop.faceBubble(id,direction:1)}
        if menuStage==3 {model.hidden.insert(id)}
        if menuStage==4 {model.records.removeAll{$0.id==id}}
        desktop.sync()
        after(0.3) { [self] in exerciseMenu()}
    }
    private func menuFailure(_ reason:String) {
        for timer in menuTimers {timer.invalidate()}
        NotificationCenter.default.removeObserver(self)
        menuStage=4;trackingMenu?.cancelTrackingWithoutAnimation();desktop.close()
        result="FAIL: "+reason
        FileHandle.standardError.write(Data(("FAIL: "+reason+"\n").utf8))
        if menuAutomatic {exit(1)}
    }
}
@main struct HeadSizeFixture:App {
    @State private var samples=HeadSizeSamples()
    var body:some Scene {
        Window("Pikminions Size Fixture",id:"sizes") {
            VStack(alignment:.leading,spacing:18) {
                Text("Desktop head sizes").font(.headline)
                Text("Sample data only · no live connection or credentials").font(.caption).foregroundStyle(.secondary)
                HStack(alignment:.top,spacing:18) {
                    ForEach(samples.sampleIDs,id:\.self) {id in
                        VStack {
                            DesktopHead(model:samples.model,id:id)
                            Text(samples.model.records.first(where:{$0.id==id}).map{samples.model.size(for:$0).title} ?? "Removed sample").font(.caption)
                        }.frame(width:142,height:218,alignment:.top)
                    }
                }
                Text(samples.result).font(.caption)
                Button("Check native panels") {do {try samples.validate()} catch {samples.result=error.localizedDescription}}
                Button("Arm menu check") {samples.checkMenu(automatic:false)}
            }.padding(22).preferredColorScheme(.dark)
                .task {
                    samples.desktop.sync()
                    if CommandLine.arguments.contains("--check") {await samples.check()}
                    if CommandLine.arguments.contains("--menu-check") {samples.checkMenu()}
                }
                .onDisappear {samples.desktop.close()}
        }.defaultSize(width:680,height:340)
    }
}
