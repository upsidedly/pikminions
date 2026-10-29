// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Foundation
import AppKit
import AVFoundation
import UserNotifications

@MainActor final class Chirps {
    private var player:AVAudioPlayer?
    private let directory=FileManager.default.homeDirectoryForCurrentUser.appending(path:"Library/Sounds")
    func prepare() async throws {
        let directory=self.directory
        try await Task.detached(priority:.utility) {
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            for (name,base) in [("pikminions-finished",880.0),("pikminions-attention",640.0),("pikminions-failed",390.0),("pikminions-dock",1100.0)] {
                let data=Self.wave(base:base,pop:name=="pikminions-dock")
                try data.write(to:directory.appending(path:name+".wav"),options:.atomic)
            }
        }.value
    }
    func preview(_ state:AgentState = .finished) {
        guard !AppRuntime.fixture else{return}
        do {
            player=try AVAudioPlayer(contentsOf:directory.appending(path:filename(state)))
            player?.volume=0.32;player?.play()
        } catch { NSSound.beep() }
    }
    func pop() {
        guard !AppRuntime.fixture else{return}
        do {
            player=try AVAudioPlayer(contentsOf:directory.appending(path:"pikminions-dock.wav"))
            player?.volume=0.22;player?.play()
        } catch {NSSound.beep()}
    }
    func filename(_ state:AgentState)->String {
        state == .failed ? "pikminions-failed.wav" : state == .finished ? "pikminions-finished.wav" : "pikminions-attention.wav"
    }
    nonisolated private static func wave(base:Double,pop:Bool=false)->Data {
        let rate=22050
        let duration=pop ? 0.095:0.34
        let count=Int(Double(rate)*duration)
        var samples=[Int16]();samples.reserveCapacity(count)
        for index in 0..<count {
            let t=Double(index)/Double(rate)
            let local=pop ? t/duration:t.truncatingRemainder(dividingBy:0.17)/0.17
            let envelope=pow(sin(Double.pi*local),2)*(t<0.30 ? 1:((duration-t)/0.04))
            let note=pop ? base*(1.7-local):base*(t>0.17 ? 1.25:1)*(1+0.18*sin(local*Double.pi))
            let phase=2*Double.pi*note*t
            let sample=(sin(phase)+0.2*sin(phase*2))*envelope*0.22
            samples.append(Int16(max(-32767,min(32767,Int(sample*32767)))))
        }
        var data=Data()
        func text(_ value:String) {data.append(contentsOf:value.utf8)}
        func u32(_ value:UInt32) {var value=value.littleEndian;withUnsafeBytes(of:&value){data.append(contentsOf:$0)}}
        func u16(_ value:UInt16) {var value=value.littleEndian;withUnsafeBytes(of:&value){data.append(contentsOf:$0)}}
        text("RIFF");u32(UInt32(36+count*2));text("WAVEfmt ");u32(16);u16(1);u16(1);u32(UInt32(rate));u32(UInt32(rate*2));u16(2);u16(16);text("data");u32(UInt32(count*2))
        for sample in samples {u16(UInt16(bitPattern:sample))}
        return data
    }
}
