// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import SwiftUI
import AppKit
import Antille

@MainActor final class SpriteLibrary {
    private var cache:[String:[String]]=[:]
    private var inFlight:[String:Task<[String],Error>]=[:]
    private let directory=URL.applicationSupportDirectory.appending(path:AppRuntime.fixture ? "PikminionsFixture/sprites":"Pikminions/sprites")
    func cancel() {for task in inFlight.values {task.cancel()};inFlight=[:]}
    private func key(_ species:PikminSpecies,_ mood:PikminMood,_ growth:PikminGrowth,_ idle:PikminIdleKind?=nil,_ appearance:PikminLook?=nil)->String {"\(species.rawValue)-\(mood.rawValue)-\(growth.rawValue)-v7"+(appearance.map{"-look-"+$0.assetKey} ?? "")+(idle.map{"-idle-"+$0.rawValue} ?? "")}
    func cachedFrames(species:PikminSpecies,mood:PikminMood,growth:PikminGrowth,idle:PikminIdleKind?=nil,appearance:PikminLook?=nil)->[String]? {cache[key(species,mood,growth,idle,appearance)]}
    func poster(species:PikminSpecies,mood:PikminMood,growth:PikminGrowth,gaze:PikminGaze = .zero,appearance:PikminLook?=nil) async throws -> String {
        let pose=gaze == .zero ? "":"-gaze-\(Int(gaze.x))-\(Int(gaze.y))"
        let target=directory.appending(path:key(species,mood,growth,nil,appearance)+pose+"-poster.png")
        if FileManager.default.fileExists(atPath:target.path) {return target.path}
        let renderer=ImageRenderer(content:PikminDrawing(species:species,mood:mood,growth:growth,time:0,gaze:gaze,appearance:appearance).frame(width:50,height:60))
        renderer.scale=2
        guard let cg=renderer.cgImage,let data=NSBitmapImageRep(cgImage:cg).representation(using:.png,properties:[:]) else {throw SourceFailure.message("The head could not be drawn.")}
        try await Task.detached(priority:.utility) {
            try FileManager.default.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
            try data.write(to:target,options:.atomic)
        }.value
        return target.path
    }
    func frames(species:PikminSpecies,mood:PikminMood,growth:PikminGrowth,idle:PikminIdleKind?=nil,appearance:PikminLook?=nil) async throws -> [String] {
        let key=key(species,mood,growth,idle,appearance)
        if let paths=cache[key] {return paths}
        if let task=inFlight[key] {return try await task.value}
        let task=Task { @MainActor in try await self.render(species:species,mood:mood,growth:growth,key:key,idle:idle,appearance:appearance) }
        inFlight[key]=task
        defer {inFlight.removeValue(forKey:key)}
        let result=try await task.value
        cache[key]=result
        return result
    }
    private func render(species:PikminSpecies,mood:PikminMood,growth:PikminGrowth,key:String,idle:PikminIdleKind?,appearance:PikminLook?) async throws -> [String] {
        let folder=directory.appending(path:key)
        let count=idle != nil ? 60:mood == .disconnected ? 1:120
        let paths=(0..<count).map {folder.appending(path:String(format:"%02d.png",$0)).path}
        let ready=folder.appending(path:"ready")
        if FileManager.default.fileExists(atPath:ready.path),paths.allSatisfy({FileManager.default.fileExists(atPath:$0)}) {
            cache[key]=paths;return paths
        }
        var frames:[Data]=[]
        for index in 0..<count {
            try Task.checkCancellation()
            let pose=idle.map{PikminIdlePose.make($0,progress:Double(index)/Double(max(1,count-1)))} ?? .rest
            let renderer=ImageRenderer(content:PikminDrawing(species:species,mood:mood,growth:growth,time:Double(index)*(idle?.duration ?? 4.8)/Double(count),idle:pose,appearance:appearance).frame(width:50,height:60))
            renderer.scale=2;renderer.isOpaque=false
            guard let cg=renderer.cgImage,let data=NSBitmapImageRep(cgImage:cg).representation(using:.png,properties:[:]) else {
                throw SourceFailure.message("A Pikmin frame could not be rendered.")
            }
            frames.append(data)
            await Task.yield()
        }
        let rendered=frames
        try await Task.detached(priority:.utility) {
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            for (index,data) in rendered.enumerated() {try data.write(to:URL(fileURLWithPath:paths[index]),options:.atomic)}
            try Data("2".utf8).write(to:ready,options:.atomic)
        }.value
        cache[key]=paths;return paths
    }
}
