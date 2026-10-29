// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import AppKit
import SwiftUI
import Antille
import QuartzCore

private final class HeadPanel:NSPanel {
    override var canBecomeKey:Bool {false}
    override var canBecomeMain:Bool {false}
}
@MainActor final class DesktopSquadController {
    private weak var model:SquadModel?
    private var panels:[String:HeadPanel]=[:]
    private var origins:[String:CGPoint]=[:]
    private var pointerOrigins:[String:CGPoint]=[:]
    private var lastSamples:[String:(point:CGPoint,time:TimeInterval)]=[:]
    private var velocities:[String:CGPoint]=[:]
    private var dragging:Set<String>=[]
    private var eventMonitor:Any?
    private var flights:[String:Task<Void,Never>]=[:]
    private var swings:[String:Task<Void,Never>]=[:]
    private var glides:[String:Task<Void,Never>]=[:]
    private var celebrations:[String:Task<Void,Never>]=[:]
    private var attentionBases:[String:CGPoint]=[:]
    private var attentionTargets:[String:CGPoint]=[:]
    private var attentionMotions:[String:Task<Void,Never>]=[:]
    private var attentionVersions:[String:UUID]=[:]
    private var hoveredID:String?
    private var hoverArrow:IslandHoverArrowShortcut?
    init(model:SquadModel) {
        self.model=model
        hoverArrow=IslandHoverArrowShortcut(key:.up,isEligible:{ [weak self] in
            guard let self,let id=self.hoveredID,let panel=self.panels[id],self.model?.contextMenuHeads.isEmpty==true else{return false}
            return panel.frame.contains(NSEvent.mouseLocation) && self.flights[id]==nil
        }) { [weak self] in self?.dismissHovered() }
        eventMonitor=NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDown,.leftMouseDragged,.leftMouseUp]) { [weak self] event in
            self?.handle(event)
            return event
        }
    }
    func frame(for id:String)->CGRect? {panels[id]?.frame}
    func hover(_ id:String,inside:Bool) {
        if inside {hoveredID=id} else if hoveredID==id {hoveredID=nil}
        hoverArrow?.setEnabled(hoveredID != nil && model?.contextMenuHeads.isEmpty==true)
    }
    private func dismissHovered() {
        guard let id=hoveredID,let panel=panels[id],panel.frame.contains(NSEvent.mouseLocation),let agent=model?.records.first(where:{$0.id==id}) else{hoveredID=nil;hoverArrow?.setEnabled(false);return}
        hoveredID=nil;hoverArrow?.setEnabled(false);model?.dismiss(agent)
    }
    func anchorFrame(for id:String)->CGRect? {
        guard let panel=panels[id] else{return nil}
        return CGRect(origin:attentionBases[id] ?? panel.frame.origin,size:panel.frame.size)
    }
    func faceBubble(_ id:String,direction:Double) {
        guard let panel=panels[id],let model,!model.contextMenuHeads.contains(id),!model.grabbed.contains(id),flights[id]==nil,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else{return}
        let base=attentionBases[id] ?? panel.frame.origin;attentionBases[id]=base
        let screen=NSScreen.screens.first(where:{$0.frame.intersects(panel.frame)})?.visibleFrame ?? panel.frame.insetBy(dx:-100,dy:-100)
        let target=CGPoint(x:base.x,y:min(screen.maxY-panel.frame.height,max(screen.minY,base.y+direction*6)))
        if attentionTargets[id]==target {return}
        animateAttention(id,to:target,returning:false)
    }
    func releaseAttention(_ id:String) {
        guard let base=attentionBases[id] else{return}
        guard let model,!model.grabbed.contains(id),flights[id]==nil else {resetAttention(id);return}
        animateAttention(id,to:base,returning:true)
    }
    private func animateAttention(_ id:String,to target:CGPoint,returning:Bool) {
        guard model?.contextMenuHeads.contains(id) != true else{return}
        attentionMotions.removeValue(forKey:id)?.cancel()
        guard let panel=panels[id] else {resetAttention(id);return}
        let version=UUID();attentionVersions[id]=version;attentionTargets[id]=target
        let start=panel.frame.origin
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.setFrameOrigin(target);if returning {resetAttention(id)};return
        }
        attentionMotions[id]=Task { @MainActor [weak self] in
            let began=ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                guard let self,self.panels[id]===panel,self.attentionVersions[id]==version else{return}
                let t=min(1,(ProcessInfo.processInfo.systemUptime-began)/0.28),p=1-pow(1-t,3)
                panel.setFrameOrigin(CGPoint(x:start.x+(target.x-start.x)*p,y:start.y+(target.y-start.y)*p))
                if t>=1 {break}
                do {try await Task.sleep(for:.milliseconds(16))} catch{return}
            }
            guard let self,!Task.isCancelled,self.attentionVersions[id]==version else{return}
            self.attentionMotions.removeValue(forKey:id)
            if returning {self.attentionBases.removeValue(forKey:id);self.attentionTargets.removeValue(forKey:id);self.attentionVersions.removeValue(forKey:id)}
        }
    }
    private func resetAttention(_ id:String) {
        attentionMotions.removeValue(forKey:id)?.cancel();attentionBases.removeValue(forKey:id)
        attentionTargets.removeValue(forKey:id);attentionVersions.removeValue(forKey:id)
    }
    func sync() {
        guard let model else{return}
        let agents=model.mode == .island ? []:model.visibleHeads.filter{!model.docked.contains($0.id)}
        let ids=Set(agents.map(\.id))
        for id in Array(panels.keys) where !ids.contains(id) && !model.contextMenuHeads.contains(id) {
            model.endDrag(id)
            flights.removeValue(forKey:id)?.cancel();swings.removeValue(forKey:id)?.cancel();glides.removeValue(forKey:id)?.cancel()
            celebrations.removeValue(forKey:id)?.cancel()
            resetAttention(id)
            if hoveredID==id {hoveredID=nil;hoverArrow?.setEnabled(false)}
            model.grabbed.remove(id);model.grabAngles.removeValue(forKey:id);model.grabAnchors.removeValue(forKey:id)
            panels.removeValue(forKey:id)?.close()
        }
        let frame=NSScreen.main?.visibleFrame ?? CGRect(x:0,y:0,width:1440,height:900)
        let cellWidth=(agents.map{model.size(for:$0).panelSize.width}.max() ?? 86)+12
        let cellHeight=(agents.map{model.size(for:$0).panelSize.height}.max() ?? 116)+12
        let columns=max(1,min(8,Int((frame.width-24)/cellWidth)))
        for (index,agent) in agents.enumerated() {
            let selectedSize=model.size(for:agent),size=selectedSize.panelSize
            if let panel=panels[agent.id] {
                panel.title=model.displayName(agent)+" · Desktop Pikmin"
                if panel.frame.size != size {resize(agent.id,panel:panel,to:selectedSize)}
                continue
            }
            let saved=UserDefaults.standard.array(forKey:"Pikminions.position."+agent.id) as? [Double]
            let x=saved?.first ?? (frame.maxX-19-size.width-Double(index%columns)*cellWidth)
            let y=(saved?.count==2 ? saved?[1]:nil) ?? (frame.minY+30+Double(index/columns)*cellHeight)
            let origin=CGPoint(x:min(frame.maxX-size.width,max(frame.minX,x)),y:min(frame.maxY-size.height,max(frame.minY,y)))
            let panel=HeadPanel(contentRect:CGRect(origin:origin,size:size),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            panel.backgroundColor = .clear;panel.isOpaque=false;panel.hasShadow=false;panel.isFloatingPanel=true
            panel.animationBehavior = .none
            panel.title=model.displayName(agent)+" · Desktop Pikmin"
            panel.hidesOnDeactivate=false;panel.level = .floating
            panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.stationary,.ignoresCycle]
            let hosting=NSHostingView(rootView:DesktopHead(model:model,id:agent.id))
            hosting.sizingOptions=[];hosting.frame=CGRect(origin:.zero,size:size);hosting.autoresizingMask=[.width,.height]
            let container=NSView(frame:hosting.frame);container.addSubview(hosting);panel.contentView=container
            panels[agent.id]=panel;panel.orderFrontRegardless()
        }
    }
    func pauseForMenu(_ id:String) {
        hoverArrow?.setEnabled(false)
        glides.removeValue(forKey:id)?.cancel();celebrations.removeValue(forKey:id)?.cancel()
        attentionMotions.removeValue(forKey:id)?.cancel();attentionTargets.removeValue(forKey:id);attentionVersions.removeValue(forKey:id)
    }
    func resumeAfterMenu() {
        hoveredID=panels.first(where:{$0.value.frame.contains(NSEvent.mouseLocation)})?.key
        hoverArrow?.setEnabled(hoveredID != nil && model?.contextMenuHeads.isEmpty==true)
    }
    private func resize(_ id:String,panel:HeadPanel,to size:PikminSize) {
        glides.removeValue(forKey:id)?.cancel();celebrations.removeValue(forKey:id)?.cancel();resetAttention(id)
        if flights[id] != nil || dragging.contains(id) || model?.grabbed.contains(id)==true {
            flights.removeValue(forKey:id)?.cancel();swings.removeValue(forKey:id)?.cancel();dragging.remove(id)
            origins.removeValue(forKey:id);pointerOrigins.removeValue(forKey:id);lastSamples.removeValue(forKey:id);velocities.removeValue(forKey:id)
            model?.grabbed.remove(id);model?.grabAngles.removeValue(forKey:id);model?.grabAnchors.removeValue(forKey:id)
            model?.tossProgress.removeValue(forKey:id);model?.endDrag(id)
        }
        let screen=NSScreen.screens.first(where:{$0.visibleFrame.intersects(panel.frame)})?.visibleFrame ?? NSScreen.main?.visibleFrame ?? panel.frame
        panel.setFrame(size.resizedFrame(from:panel.frame,within:screen),display:true)
        UserDefaults.standard.set([panel.frame.minX,panel.frame.minY],forKey:"Pikminions.position."+id)
    }
    private func handle(_ event:NSEvent) {
        guard let (id,panel)=panels.first(where:{$0.value===event.window}) else{return}
        guard flights[id]==nil else{return}
        let pointer=panel.convertPoint(toScreen:event.locationInWindow)
        switch event.type {
        case .leftMouseDown:
            guard !event.modifierFlags.contains(.control),model?.contextMenuHeads.isEmpty==true else{return}
            attentionMotions.removeValue(forKey:id)?.cancel();attentionTargets.removeValue(forKey:id);attentionVersions.removeValue(forKey:id)
            celebrations.removeValue(forKey:id)?.cancel()
            glides.removeValue(forKey:id)?.cancel()
            origins[id]=panel.frame.origin;pointerOrigins[id]=pointer
            lastSamples[id]=(pointer,ProcessInfo.processInfo.systemUptime)
            velocities[id] = .zero
            let scale=panel.frame.width/86,art=CGSize(width:74*scale,height:89*scale)
            startSwing(id,anchor:UnitPoint(x:max(0,min(1,(event.locationInWindow.x-(panel.frame.width-art.width)/2)/art.width)),y:max(0,min(1,(panel.frame.height-event.locationInWindow.y)/art.height))))
        case .leftMouseDragged:
            guard let start=pointerOrigins[id] else{return}
            if !dragging.contains(id),hypot(pointer.x-start.x,pointer.y-start.y)<4 {return}
            if dragging.insert(id).inserted {resetAttention(id);model?.beginDrag(id)}
            drag(id,pointer:pointer,ended:false)
        case .leftMouseUp:
            releaseSwing(id)
            if dragging.remove(id) != nil {drag(id,pointer:pointer,ended:true)}
            else {origins.removeValue(forKey:id);pointerOrigins.removeValue(forKey:id);lastSamples.removeValue(forKey:id);velocities.removeValue(forKey:id)}
            if flights[id]==nil {model?.endDrag(id)}
        default:break
        }
    }
    private func drag(_ id:String,pointer:CGPoint,ended:Bool) {
        guard let panel=panels[id],let model else{return}
        // Native captured events give stable screen coordinates as the panel moves.
        let now=ProcessInfo.processInfo.systemUptime
        model.tossProgress.removeValue(forKey:id)
        let start=origins[id] ?? panel.frame.origin
        let pointerStart=pointerOrigins[id] ?? pointer
        if !ended,let sample=lastSamples[id],now>sample.time {
            let dt=max(0.008,now-sample.time)
            let measured=CGPoint(x:(pointer.x-sample.point.x)/dt,y:(pointer.y-sample.point.y)/dt)
            let previous=velocities[id] ?? measured
            velocities[id]=CGPoint(x:previous.x*0.35+measured.x*0.65,y:previous.y*0.35+measured.y*0.65)
        }
        lastSamples[id]=(pointer,now)
        let target=model.islandDropTarget()
        let attraction=IslandMagnet.strength(pointer:pointer,target:target)
        model.magnet(attraction,for:id,at:pointer)
        var point=IslandMagnet.dragOrigin(window:start,startPointer:pointerStart,pointer:pointer)
        let dockPoint=CGPoint(x:target.midX,y:target.maxY-38)
        if attraction>0 {
            let pull=attraction*attraction*0.24
            point.x+=(dockPoint.x-panel.frame.width/2-point.x)*pull
            point.y+=(dockPoint.y-panel.frame.height/2-point.y)*pull
        }
        panel.setFrameOrigin(point)
        model.conversationCoordinator?.follow(id,anchor:panel.frame)
        guard ended else{return}
        let velocity=velocities.removeValue(forKey:id) ?? .zero
        origins.removeValue(forKey:id);pointerOrigins.removeValue(forKey:id);lastSamples.removeValue(forKey:id)
        model.magnet(0,for:id)
        if IslandMagnet.shouldDock(pointer:pointer,velocity:velocity,target:target) {
            _=jump(id)
        } else {
            let frame=NSScreen.screens.first(where:{$0.visibleFrame.contains(pointer)})?.visibleFrame ?? NSScreen.main?.visibleFrame ?? CGRect(x:0,y:0,width:1440,height:900)
            point=CGPoint(x:min(frame.maxX-panel.frame.width,max(frame.minX,point.x)),y:min(frame.maxY-panel.frame.height,max(frame.minY,point.y)))
            panel.setFrameOrigin(point)
            if let partner=panels.first(where:{$0.key != id && $0.value.frame.contains(pointer)}) {
                let proposed=partner.value.frame.minX-panel.frame.width-8
                point.x=proposed>=frame.minX ? proposed:min(frame.maxX-panel.frame.width,partner.value.frame.maxX+8)
                point.y=partner.value.frame.minY;panel.setFrameOrigin(point)
                model.prepareCollaboration(id,partner.key)
                UserDefaults.standard.set([point.x,point.y],forKey:"Pikminions.position."+id)
                return
            }
            UserDefaults.standard.set([point.x,point.y],forKey:"Pikminions.position."+id)
            if !model.fixedPositions.contains(id),!NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
               model.gravityEnabled || hypot(velocity.x,velocity.y)>180 {startGlide(id,velocity:velocity,frame:frame)}
        }
    }
    private func startSwing(_ id:String,anchor:UnitPoint) {
        guard let model else{return}
        model.grabbed.insert(id);model.grabAnchors[id]=anchor
        swings.removeValue(forKey:id)?.cancel()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else{return}
        swings[id]=Task { @MainActor [weak self] in
            var pendulum=HeadPendulum()
            var last=ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                guard let self,let model=self.model,model.grabbed.contains(id) else{return}
                let now=ProcessInfo.processInfo.systemUptime
                let fresh=now-(self.lastSamples[id]?.time ?? 0)<0.1
                let velocity=fresh ? (self.velocities[id]?.x ?? 0):0
                model.grabAngles[id]=pendulum.step(cursorVelocity:velocity,anchorX:anchor.x,dt:now-last)
                last=now
                do {try await Task.sleep(for:.milliseconds(16))} catch{return}
            }
        }
    }
    private func releaseSwing(_ id:String) {
        swings.removeValue(forKey:id)?.cancel()
        guard let model else{return}
        model.grabbed.remove(id)
        withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil:.spring(response:0.42,dampingFraction:0.5)) {model.grabAngles[id]=0}
    }
    private func startGlide(_ id:String,velocity:CGPoint,frame:CGRect) {
        glides.removeValue(forKey:id)?.cancel()
        guard let panel=panels[id],let model,!model.attending.contains(id),!model.contextMenuHeads.contains(id) else{return}
        glides[id]=Task { @MainActor [weak self] in
            var speed=CGPoint(x:max(-1600,min(1600,velocity.x)),y:max(-1600,min(1600,velocity.y)))
            var point=panel.frame.origin
            var last=ProcessInfo.processInfo.systemUptime
            let started=last
            while !Task.isCancelled {
                guard let self,self.panels[id]===panel,!model.fixedPositions.contains(id) else{return}
                let now=ProcessInfo.processInfo.systemUptime,dt=min(0.035,now-last);last=now
                let gravity=model.gravityEnabled
                speed.x*=exp(-9*dt)
                if gravity {speed.y-=950*dt} else {speed.y*=exp(-9*dt)}
                point.x+=speed.x*dt;point.y+=speed.y*dt
                if point.x<frame.minX || point.x>frame.maxX-panel.frame.width {
                    point.x=min(frame.maxX-panel.frame.width,max(frame.minX,point.x));speed.x *= -0.22
                }
                if point.y<frame.minY {
                    point.y=frame.minY;speed.y *= -0.23
                    if abs(speed.y)<45 {speed.y=0}
                }
                if point.y>frame.maxY-panel.frame.height {point.y=frame.maxY-panel.frame.height;speed.y *= -0.2}
                panel.setFrameOrigin(point)
                model.conversationCoordinator?.follow(id,anchor:panel.frame)
                if now-started>2.2 || (hypot(speed.x,speed.y)<12 && (!gravity || point.y<=frame.minY+0.5)) {break}
                do {try await Task.sleep(for:.milliseconds(16))} catch{return}
            }
            guard let self,self.panels[id]===panel,!Task.isCancelled else{return}
            UserDefaults.standard.set([point.x,point.y],forKey:"Pikminions.position."+id)
            self.glides.removeValue(forKey:id)
        }
    }
    func callToAttention(_ id:String) {
        celebrations.removeValue(forKey:id)?.cancel()
        glides.removeValue(forKey:id)?.cancel()
    }
    func celebrate(_ id:String) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,let panel=panels[id],let model,flights[id]==nil,!model.grabbed.contains(id),!model.attending.contains(id),!model.contextMenuHeads.contains(id) else{return}
        celebrations.removeValue(forKey:id)?.cancel()
        let origin=panel.frame.origin
        celebrations[id]=Task { @MainActor [weak self] in
            let start=ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                guard let self,self.panels[id]===panel else{return}
                let t=min(1,(ProcessInfo.processInfo.systemUptime-start)/1.05)
                let hop=abs(sin(t*Double.pi*2))*12*(1-t)
                panel.setFrameOrigin(CGPoint(x:origin.x,y:origin.y+hop))
                model.conversationCoordinator?.follow(id,anchor:panel.frame)
                if t>=1 {break}
                do {try await Task.sleep(for:.milliseconds(16))} catch{return}
            }
            guard let self,self.panels[id]===panel,!Task.isCancelled else{return}
            panel.setFrameOrigin(origin);self.celebrations.removeValue(forKey:id)
        }
    }
    @discardableResult func jump(_ id:String)->Bool {
        if flights[id] != nil {return true}
        guard let panel=panels[id],let model,let agent=model.records.first(where:{$0.id==id}) else{return false}
        model.conversationCoordinator?.dismissHead(id);resetAttention(id);model.tossProgress[id]=0
        glides.removeValue(forKey:id)?.cancel();releaseSwing(id)
        model.beginDrag(id)
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {model.endDrag(id);model.dock(agent);return true}
        let from=panel.frame.origin
        flights[id]=Task { @MainActor [weak self] in
            guard let self else{return}
            let landing=await model.landingPoint(for:agent)
            guard !Task.isCancelled,self.panels[id]===panel else {model.endDrag(id);return}
            let target=model.islandDropTarget()
            let centerOffset=PikminSize.artCenter(in:CGRect(origin:.zero,size:panel.frame.size))
            let end=CGPoint(x:landing.x-centerOffset.x,y:landing.y-centerOffset.y)
            let perch=CGPoint(x:end.x,y:end.y-36)
            let distance=hypot(end.x-from.x,end.y-from.y)
            let height=min(150,max(65,distance*0.13))
            let duration=min(0.85,max(0.52,distance/1400))
            let start=ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                let t=min(1,(ProcessInfo.processInfo.systemUptime-start)/duration)
                let point:CGPoint
                if t<0.76 {
                    let u=t/0.76
                    point=IslandMagnet.arcPoint(from:from,to:perch,progress:u*u*(3-2*u),height:height)
                } else {
                    point=IslandMagnet.arcPoint(from:perch,to:end,progress:(t-0.76)/0.24,height:25)
                }
                panel.setFrameOrigin(point)
                model.tossProgress[id]=t
                let center=CGPoint(x:point.x+centerOffset.x,y:point.y+centerOffset.y)
                model.magnet(IslandMagnet.strength(pointer:center,target:target),for:id,at:center)
                if t>=1 {break}
                do {try await Task.sleep(for:.milliseconds(16))} catch {break}
            }
            guard self.panels[id]===panel else{return}
            self.flights.removeValue(forKey:id)
            model.endDrag(id)
            if !Task.isCancelled {model.dock(agent)}
            else {model.tossProgress.removeValue(forKey:id)}
        }
        return true
    }
    func close() {
        hoverArrow?.close();hoverArrow=nil;hoveredID=nil
        if let eventMonitor {NSEvent.removeMonitor(eventMonitor)};eventMonitor=nil
        for task in flights.values {task.cancel()};flights=[:]
        for task in swings.values {task.cancel()};swings=[:]
        for task in glides.values {task.cancel()};glides=[:]
        for task in celebrations.values {task.cancel()};celebrations=[:]
        for task in attentionMotions.values {task.cancel()};attentionMotions=[:];attentionBases=[:];attentionTargets=[:];attentionVersions=[:]
        for panel in panels.values {panel.close()};panels=[:]
        origins=[:];pointerOrigins=[:];lastSamples=[:];velocities=[:];dragging=[]
    }
}
struct DesktopHead:View {
    @Bindable var model:SquadModel
    let id:String
    @State private var hover=false
    @State private var menuAgent:AgentRecord?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body:some View {
        if let agent=model.records.first(where:{$0.id==id}) ?? menuAgent {
            let size=model.size(for:agent)
            VStack(spacing:0) {
                Button {model.showConversation(agent)} label:{
                    PikminHead(species:model.species(for:agent),mood:agent.stale ? .disconnected:model.successes[id] != nil ? .happy:agent.mood,growth:model.growth,animated:!model.attending.contains(id) && !model.grabbed.contains(id) && !model.contextMenuHeads.contains(id),tracksCursor:!model.contextMenuHeads.contains(id),phase:Double(abs(id.hashValue%20)),focusGaze:model.attentionGazes[id],idleEvent:model.idleDirector.active[id],appearance:model.look(for:agent))
                        .frame(width:size.artSize.width,height:size.artSize.height)
                        .modifier(IslandSuccessEffect(trigger:model.attending.contains(id) ? nil:model.successes[id]?.id,amplitude:0))
                        .scaleEffect(1-0.68*(model.tossProgress[id] ?? 0))
                        .scaleEffect(!reduceMotion && model.grabbed.contains(id) ? 1.035:1)
                        .rotationEffect(.degrees(model.grabAngles[id] ?? 0),anchor:model.grabAnchors[id] ?? .center)
                        .rotationEffect(.degrees(360*(model.tossProgress[id] ?? 0)))
                        .animation(reduceMotion ? nil:.spring(response:0.22,dampingFraction:0.65),value:model.grabbed.contains(id))
                        .overlay(alignment:.bottomTrailing) {
                            if agent.attention.rank>1 && !agent.needsUserInput {
                                Image(systemName:agent.state == .failed ? "exclamationmark.circle.fill":"questionmark.circle.fill")
                                    .font(.system(size:12)).foregroundStyle(.white,Color(islandHex:model.species(for:agent).hex))
                            }
                        }
                }.buttonStyle(.plain)
                .accessibilityLabel(model.displayName(agent)+", "+agent.statusLabel)
                .accessibilityAction(named:Text("Dismiss to island")) {model.dismiss(agent)}
                .accessibilityAction(named:Text("Rename Pikmin")) {model.renameHead(agent)}
                .accessibilityAction(named:Text(model.vocal.contains(id) ? "Disable vocal mode":"Enable vocal mode")) {model.toggleVocalMode(agent)}
                .accessibilityValue("Size "+size.title)
                .accessibilityActions {
                    ForEach(PikminSize.allCases) {size in Button("Size "+size.title) {model.setSize(size,for:agent)}}
                }
                if hover {Text(model.displayName(agent)).font(.system(size:9,weight:.medium)).lineLimit(1).padding(.horizontal,5).padding(.vertical,2).background(.regularMaterial,in:Capsule())}
            }
            .frame(width:size.panelSize.width,height:size.panelSize.height,alignment:.top)
            .onHover{hover=$0;model.hoverHead(id,inside:$0)}
            // Recognition cancels the button's click; AppKit owns window movement.
            .highPriorityGesture(DragGesture(minimumDistance:4).onChanged{_ in})
            .islandContextMenu(onOpen:{menuAgent=agent;model.beginContextMenu(id)},onClose:{model.endContextMenu(id);menuAgent=nil}) {
                guard !model.grabbed.contains(id),model.tossProgress[id]==nil else{return []}
                return DesktopHeadContextMenu.items(model:model,id:id)
            }
            .help(model.displayName(agent)+" · "+agent.statusLabel)
        }
    }
}


/// Build a stable menu for this interaction; resolve the latest agent at action time.
@MainActor enum DesktopHeadContextMenu {
    static func items(model:SquadModel,id:String)->[IslandContextMenuItem] {
        guard let agent=model.records.first(where:{$0.id==id}) else{return []}
        func perform(_ action:(AgentRecord)->Void) {
            guard let current=model.records.first(where:{$0.id==id}) else{return};action(current)
        }
        let vocal=model.vocal.contains(id),size=model.size(for:agent)
        let species=PikminSpecies.allCases.map {value in IslandContextMenuItem(value.name) {perform{model.setSpecies(value,for:$0)}}}
        let looks=model.customLooks.map {look in IslandContextMenuItem(look.name) {perform{model.chooseLook(look,for:$0)}}}
        let appearance=species+(looks.isEmpty ? []:[.separator]+looks)+[.separator,IslandContextMenuItem("Customize…") {perform{model.editLook(model.look(for:$0),for:$0)}}]
        return [
            IslandContextMenuItem("Talk") {perform{model.showConversation($0)}},
            IslandContextMenuItem("Vocal mode",enabled:agent.isInteractive,checked:vocal) {perform{model.setVocalMode(!vocal,for:$0)}},
            IslandContextMenuItem("Rename…") {perform{model.renameHead($0)}},
            IslandContextMenuItem("Size",children:PikminSize.allCases.map {value in IslandContextMenuItem(value.title,checked:value==size) {perform{model.setSize(value,for:$0)}}}),
            IslandContextMenuItem("Collaborate…",enabled:agent.isInteractive) {perform{model.conversationCoordinator?.prepareCollaboration($0)}},
            IslandContextMenuItem("Open conversation") {perform{model.open($0)}},
            IslandContextMenuItem(model.pinned.contains(id) ? "Unpin":"Keep visible") {perform{model.togglePin($0)}},
            IslandContextMenuItem(model.fixedPositions.contains(id) ? "Unpin position":"Pin position") {perform{model.toggleFixedPosition($0)}},
            IslandContextMenuItem("Pikmin",children:appearance),
            IslandContextMenuItem(model.muted.contains(id) ? "Unmute":"Mute") {perform{model.toggleMute($0)}},
            IslandContextMenuItem("Dismiss") {perform{model.dismiss($0)}},
            IslandContextMenuItem("Hide") {perform{model.hide($0)}}
        ]
    }
}
