// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import SwiftUI
import AppKit
import Antille

enum PikminSpecies:String,CaseIterable,Codable,Identifiable,Sendable {
    case red,yellow,blue,purple,white,rock,winged,ice,glow
    var id:String { rawValue }
    var name:String { rawValue.capitalized }
    var hex:String {
        switch self {
        case .red:"E93842";case .yellow:"F4CE31";case .blue:"3289CA";case .purple:"833A91"
        case .white:"F4F4E8";case .rock:"34474E";case .winged:"E87CB1";case .ice:"84DCE2";case .glow:"8AE234"
        }
    }
    var flowerHex:String {
        switch self {case .white,.purple:"E1498C";case .rock,.winged:"9183CB";case .ice,.glow:"F3D345";default:"F7F8E9"}
    }
    var outlineHex:String {Self.darkened(hex)}
    var flowerOutlineHex:String {Self.darkened(flowerHex,by:0.43)}
    static func darkened(_ hex:String,by factor:Double=0.4)->String {
        let value=UInt32(hex,radix:16) ?? 0
        return String(format:"%02X%02X%02X",Int(Double((value>>16)&255)*factor),Int(Double((value>>8)&255)*factor),Int(Double(value&255)*factor))
    }
    var referenceGrowth:PikminGrowth {[.red,.yellow,.blue].contains(self) ? .leaf:.flower}
    var top:PikminTopProfile {
        switch self {
        case .red,.yellow,.blue:return .init(offset:34,tipX:52,stemWidth:7,stemHex:hex,leafLength:43,budWidth:12,budHeight:25)
        case .purple:return .init(offset:34,tipX:56,stemWidth:7.5,stemHex:hex,leafLength:40,budWidth:16,budHeight:25)
        case .white:return .init(offset:38,tipX:59,stemWidth:4.8,stemHex:hex,leafLength:37,budWidth:11,budHeight:24)
        case .rock:return .init(offset:26,tipX:64,stemWidth:7,stemHex:"A0ADA2",leafLength:37,budWidth:13,budHeight:25)
        case .winged:return .init(offset:36,tipX:62,stemWidth:5.5,stemHex:hex,leafLength:37,budWidth:12,budHeight:25)
        case .ice:return .init(offset:44,tipX:61,stemWidth:5.5,stemHex:"99E7EA",leafLength:43,budWidth:12,budHeight:25)
        case .glow:return .init(offset:56,tipX:32,stemWidth:6,stemHex:hex,leafLength:39,budWidth:10,budHeight:29)
        }
    }
    static func assigned(to id:String)->PikminSpecies {
        let hash=id.utf8.reduce(UInt64(1469598103934665603)){($0 ^ UInt64($1)) &* 1099511628211}
        return allCases[Int(hash%UInt64(allCases.count))]
    }
}
enum PikminMood:String,CaseIterable,Sendable { case calm,working,attention,question,happy,sleeping,disconnected }
enum PikminGrowth:String,CaseIterable,Codable,Sendable {
    case reference,leaf,bud,flower
    var title:String {self == .reference ? "Default":rawValue.capitalized}
}
struct PikminTopProfile {
    var offset:Double
    var tipX:Double
    var stemWidth:Double
    var stemHex:String
    var leafLength:Double
    var budWidth:Double
    var budHeight:Double
    var canvasHeight:Double {120+offset}
}

struct PikminHead:View {
    var species:PikminSpecies
    var mood:PikminMood = .calm
    var growth:PikminGrowth = .reference
    var animated:Bool = true
    var tracksCursor:Bool = true
    var phase:Double = 0
    var focusGaze:PikminGaze?
    var idleEvent:PikminIdleEvent?
    var appearance:PikminLook?
    @State private var cursorProbe=PikminCursorProbe()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.islandContentActive) private var contentActive
    var body:some View {
        Group {
            if (animated || tracksCursor) && !reduceMotion && mood != .disconnected {
                TimelineView(.animation(minimumInterval:1/30,paused:!contentActive)) { context in
                    PikminDrawing(species:species,mood:mood,growth:growth,time:animated ? context.date.timeIntervalSinceReferenceDate+phase:0,gaze:focusGaze ?? (tracksCursor ? cursorProbe.gaze(profile:appearance?.top ?? species.top):.zero),idle:animated ? idleEvent?.pose(at:context.date) ?? .rest:.rest,appearance:appearance)
                }
            } else { PikminDrawing(species:species,mood:mood,growth:growth,time:0,gaze:focusGaze ?? .zero,appearance:appearance) }
        }
        .aspectRatio(100/120,contentMode:.fit)
        .background(PikminCursorAnchor(probe:cursorProbe))
        .saturation(mood == .disconnected ? 0.25 : 1)
        .opacity(mood == .disconnected ? 0.6 : 1)
        .accessibilityLabel("\(appearance?.name ?? species.name) Pikmin, \(mood.rawValue)")
    }
}
struct PikminDrawing:View {
    let species:PikminSpecies
    let mood:PikminMood
    let growth:PikminGrowth
    var time:Double
    var gaze:PikminGaze = .zero
    var idle:PikminIdlePose = .rest
    var appearance:PikminLook?
    var body:some View {
        Canvas { original,size in
            var c=original
            let profile=appearance?.top ?? species.top
            let drawingHeight=profile.canvasHeight
            let scale=min(size.width/100,size.height/drawingHeight)
            c.translateBy(x:(size.width-100*scale)/2,y:(size.height-drawingHeight*scale)/2)
            c.scaleBy(x:scale,y:scale)
            let lively=mood == .working || mood == .attention || mood == .question
            let cycle=time.truncatingRemainder(dividingBy:4.8)/4.8*2*Double.pi
            let sway=time==0 ? 0 : sin(cycle*(lively ? 2:1))*2.1
            let breathe=time==0 ? 0 : sin(cycle*2)*0.65
            let question=mood == .question
            let beat=time.truncatingRemainder(dividingBy:4.8)/4.8
            let hop=question && time != 0 ? (beat<0.13 ? sin(beat/0.13*Double.pi)*8:beat>0.15 && beat<0.28 ? sin((beat-0.15)/0.13*Double.pi)*5:0):0
            c.translateBy(x:0,y:profile.offset+breathe-hop+idle.y)
            let tilt=(question && time != 0 ? sin(cycle)*8.5:0)+gaze.x*3+idle.tilt
            c.translateBy(x:50,y:82);c.rotate(by:.degrees(tilt));c.translateBy(x:-50,y:-82)
            c.translateBy(x:50,y:82);c.scaleBy(x:idle.scaleX,y:idle.scaleY);c.translateBy(x:-50,y:-82)
            let bodyHex=appearance?.bodyHex ?? species.hex
            let outlineHex=PikminSpecies.darkened(bodyHex)
            let flowerHex=appearance?.flowerHex ?? species.flowerHex
            let flowerOutlineHex=PikminSpecies.darkened(flowerHex,by:0.43)
            let leafHex=appearance?.leafHex ?? "78AF38"
            let leafOutlineHex=appearance == nil ? "2B4916":PikminSpecies.darkened(leafHex)
            let color=Color(islandHex:bodyHex)
            func facet(_ original:String,_ factor:Double)->Color {Color(islandHex:appearance == nil ? original:PikminPalette.shaded(bodyHex,by:factor))}
            var outlinePaths:[(path:Path,hex:String)]=[]
            func recordOutline(_ path:Path,hex:String?=nil) {outlinePaths.append((path,hex ?? outlineHex))}
            func fill(_ points:[CGPoint],_ color:Color,outline:Bool=false) {
                var p=Path();p.addLines(points);p.closeSubpath();c.fill(p,with:.color(color));if outline {recordOutline(p)}
            }
            func ellipse(_ rect:CGRect,_ color:Color,outline:Bool=false) {let p=Path(ellipseIn:rect);c.fill(p,with:.color(color));if outline {recordOutline(p)}}
            func stroke(_ p:Path,_ color:Color,_ width:Double) {
                c.stroke(p,with:.color(color),style:StrokeStyle(lineWidth:width,lineCap:.round,lineJoin:.round))
            }
            // Small translucent wings belong behind the pink head, never pasted over its eyes.
            if species == .winged {
                var wing=Path();wing.move(to:CGPoint(x:30,y:79))
                wing.addCurve(to:CGPoint(x:13,y:71),control1:CGPoint(x:4,y:59),control2:CGPoint(x:1,y:70))
                wing.addCurve(to:CGPoint(x:32,y:89),control1:CGPoint(x:12,y:82),control2:CGPoint(x:26,y:91))
                c.fill(wing,with:.color(.white.opacity(0.82)))
                recordOutline(wing)
                var right=Path();right.move(to:CGPoint(x:70,y:79))
                right.addCurve(to:CGPoint(x:87,y:70),control1:CGPoint(x:96,y:58),control2:CGPoint(x:100,y:69))
                right.addCurve(to:CGPoint(x:68,y:89),control1:CGPoint(x:88,y:84),control2:CGPoint(x:76,y:91))
                c.fill(right,with:.color(.white.opacity(0.82)))
                recordOutline(right)
            }
            let chosenGrowth=appearance?.growth == .reference || appearance == nil ? growth:appearance?.growth ?? growth
            let actualGrowth=mood == .happy ? PikminGrowth.flower:(chosenGrowth == .reference ? species.referenceGrowth:chosenGrowth)
            let base:Double=species == .rock ? 48:50
            let tip=actualGrowth == .leaf && species != .glow && appearance == nil ? min(54,profile.tipX):profile.tipX
            let terminalX=(appearance == nil ? tip:max(actualGrowth == .leaf ? 18:28,min(actualGrowth == .leaf ? 54:72,tip)))+sway
            let terminalY=(actualGrowth == .leaf ? 34.0:actualGrowth == .bud ? 35.0:30.0)-profile.offset
            let half=profile.stemWidth/2
            var stem=Path();stem.move(to:CGPoint(x:base-half,y:72))
            stem.addCurve(to:CGPoint(x:terminalX,y:terminalY),control1:CGPoint(x:base-half-2,y:30),control2:CGPoint(x:terminalX+half-3,y:terminalY+22))
            stem.addCurve(to:CGPoint(x:base+half,y:72),control1:CGPoint(x:terminalX+half+3,y:terminalY+22),control2:CGPoint(x:base+half+2,y:35))
            stem.closeSubpath();c.fill(stem,with:.color(Color(islandHex:profile.stemHex)))
            recordOutline(stem,hex:PikminSpecies.darkened(profile.stemHex))
            var plant=c;plant.translateBy(x:terminalX,y:terminalY)
            plant.rotate(by:.degrees(sway*1.6+idle.leaf))
            func plantOutline(_ path:Path,angle:Double=0,hex:String) {
                let rotated=path.applying(CGAffineTransform(rotationAngle:(sway*1.6+idle.leaf+angle)*Double.pi/180))
                recordOutline(rotated.applying(CGAffineTransform(translationX:terminalX,y:terminalY)),hex:hex)
            }
            switch actualGrowth {
            case .reference:break
            case .leaf:
                let length=profile.leafLength
                var leaf=Path();leaf.move(to:.zero)
                leaf.addCurve(to:CGPoint(x:length,y:-19),control1:CGPoint(x:4,y:-28),control2:CGPoint(x:length*0.68,y:-30))
                leaf.addCurve(to:.zero,control1:CGPoint(x:length*0.72,y:-11),control2:CGPoint(x:10,y:-2))
                plant.fill(leaf,with:.color(Color(islandHex:leafHex)));plantOutline(leaf,hex:leafOutlineHex)
                var vein=Path();vein.move(to:CGPoint(x:2,y:-2));vein.addQuadCurve(to:CGPoint(x:length-5,y:-19),control:CGPoint(x:length*0.4,y:-16))
                plant.stroke(vein,with:.color(Color(islandHex:appearance == nil ? "B0D96E":PikminPalette.shaded(leafHex,by:1.35))),style:StrokeStyle(lineWidth:1.1,lineCap:.round))
            case .bud:
                let width=profile.budWidth,height=profile.budHeight
                var bud=Path();bud.move(to:CGPoint(x:0,y:4))
                bud.addCurve(to:CGPoint(x:0,y:-height),control1:CGPoint(x:-width,y:-3),control2:CGPoint(x:-width*0.7,y:-height*0.9))
                bud.addCurve(to:CGPoint(x:0,y:4),control1:CGPoint(x:width*0.7,y:-height*0.9),control2:CGPoint(x:width,y:-3))
                plant.fill(bud,with:.color(Color(islandHex:flowerHex)));plantOutline(bud,hex:flowerOutlineHex)
                var calyx=Path();calyx.addLines([.init(x:-8,y:-1),.init(x:-5,y:5),.init(x:0,y:2),.init(x:5,y:5),.init(x:8,y:-1),.init(x:3,y:1),.init(x:0,y:-3),.init(x:-3,y:1)]);calyx.closeSubpath()
                plant.fill(calyx,with:.color(Color(islandHex:appearance == nil ? "74AC3A":leafHex)));plantOutline(calyx,hex:leafOutlineHex)
            case .flower:
                let angle = -7+(time==0 ? 0:sin(cycle)*2)
                var flower=plant;flower.rotate(by:.degrees(angle))
                for index in 0..<5 {
                    var petal=flower;petal.rotate(by:.degrees(Double(index)*72))
                    let petalPath:Path
                    if species == .glow {
                        var pointed=Path();pointed.move(to:CGPoint(x:-3.6,y:-2))
                        pointed.addQuadCurve(to:CGPoint(x:0,y:-25),control:CGPoint(x:-10,y:-15))
                        pointed.addQuadCurve(to:CGPoint(x:4,y:-2),control:CGPoint(x:10,y:-13))
                        pointed.closeSubpath();petalPath=pointed
                    } else {petalPath=Path(ellipseIn:CGRect(x:-7,y:-21,width:14,height:19))}
                    petal.fill(petalPath,with:.color(Color(islandHex:flowerHex)))
                    plantOutline(petalPath,angle:angle+Double(index)*72,hex:flowerOutlineHex)
                }
                let center=Path(ellipseIn:CGRect(x:-5,y:-5,width:10,height:10))
                flower.fill(center,with:.color(Color(islandHex:"F2CC33")));plantOutline(center,hex:"947415")
            }
            // Each species keeps its own silhouette and defining features.
            switch species {
            case .yellow:
                var head=Path();head.move(to:CGPoint(x:26,y:64))
                head.addCurve(to:CGPoint(x:76,y:65),control1:CGPoint(x:38,y:52),control2:CGPoint(x:62,y:54))
                head.addLine(to:CGPoint(x:96,y:60))
                head.addCurve(to:CGPoint(x:76,y:83),control1:CGPoint(x:94,y:79),control2:CGPoint(x:86,y:84))
                head.addCurve(to:CGPoint(x:53,y:108),control1:CGPoint(x:73,y:94),control2:CGPoint(x:65,y:103))
                head.addCurve(to:CGPoint(x:27,y:83),control1:CGPoint(x:39,y:104),control2:CGPoint(x:30,y:95))
                head.addCurve(to:CGPoint(x:7,y:59),control1:CGPoint(x:12,y:83),control2:CGPoint(x:8,y:74))
                head.closeSubpath();c.fill(head,with:.color(color));recordOutline(head)
            case .purple:
                ellipse(CGRect(x:16,y:57,width:70,height:50),color,outline:true)
                for side in [-1.0,1.0] {
                    for i in 0..<3 {
                        let y=61.0+Double(i)*5
                        var hair=Path();hair.move(to:CGPoint(x:50+side*27,y:y))
                        hair.addQuadCurve(to:CGPoint(x:50+side*(36+Double(i)*2),y:y-10+Double(i)*3),control:CGPoint(x:50+side*32,y:y-8))
                        stroke(hair,color,1.8)
                    }
                }
            case .rock:
                fill([.init(x:25,y:58),.init(x:65,y:54),.init(x:83,y:74),.init(x:79,y:101),.init(x:55,y:112),.init(x:25,y:106),.init(x:15,y:81)],color,outline:true)
                fill([.init(x:25,y:58),.init(x:49,y:76),.init(x:48,y:107),.init(x:25,y:106),.init(x:15,y:81)],facet("263A43",0.77))
                fill([.init(x:49,y:76),.init(x:65,y:54),.init(x:83,y:74),.init(x:68,y:87)],facet("425960",1.2))
            case .ice:
                fill([.init(x:29,y:59),.init(x:58,y:54),.init(x:76,y:64),.init(x:84,y:85),.init(x:74,y:105),.init(x:47,y:111),.init(x:21,y:97),.init(x:17,y:77)],color,outline:true)
                fill([.init(x:29,y:59),.init(x:38,y:80),.init(x:17,y:77)],facet("C5F3EE",1.32))
                fill([.init(x:38,y:80),.init(x:74,y:67),.init(x:70,y:94),.init(x:47,y:111)],facet("63C7D5",0.86))
                fill([.init(x:21,y:97),.init(x:38,y:80),.init(x:47,y:111)],facet("A2E9E7",1.13))
            case .white:
                var head=Path();head.move(to:CGPoint(x:49,y:56))
                head.addCurve(to:CGPoint(x:72,y:76),control1:CGPoint(x:62,y:56),control2:CGPoint(x:73,y:64))
                head.addCurve(to:CGPoint(x:50,y:107),control1:CGPoint(x:72,y:90),control2:CGPoint(x:58,y:102))
                head.addCurve(to:CGPoint(x:28,y:76),control1:CGPoint(x:39,y:103),control2:CGPoint(x:28,y:91))
                head.addCurve(to:CGPoint(x:49,y:56),control1:CGPoint(x:28,y:64),control2:CGPoint(x:36,y:57))
                c.fill(head,with:.color(color));recordOutline(head)
            case .winged:
                ellipse(CGRect(x:20,y:63,width:62,height:40),color,outline:true)
            case .glow:
                // The head is a rounded teardrop. The ghost tail belongs to its body.
                var head=Path();head.move(to:CGPoint(x:51,y:54))
                head.addCurve(to:CGPoint(x:81,y:85),control1:CGPoint(x:60,y:62),control2:CGPoint(x:79,y:71))
                head.addCurve(to:CGPoint(x:53,y:105),control1:CGPoint(x:85,y:102),control2:CGPoint(x:68,y:106))
                head.addCurve(to:CGPoint(x:23,y:85),control1:CGPoint(x:36,y:106),control2:CGPoint(x:20,y:102))
                head.addCurve(to:CGPoint(x:51,y:54),control1:CGPoint(x:22,y:72),control2:CGPoint(x:43,y:62))
                head.closeSubpath()
                c.fill(head,with:.color(color));recordOutline(head)
            default:
                var head=Path();head.move(to:CGPoint(x:48,y:55))
                head.addCurve(to:CGPoint(x:75,y:77),control1:CGPoint(x:64,y:55),control2:CGPoint(x:75,y:63))
                head.addCurve(to:CGPoint(x:52,y:110),control1:CGPoint(x:75,y:92),control2:CGPoint(x:62,y:103))
                head.addCurve(to:CGPoint(x:25,y:78),control1:CGPoint(x:37,y:103),control2:CGPoint(x:24,y:90))
                head.addCurve(to:CGPoint(x:48,y:55),control1:CGPoint(x:24,y:64),control2:CGPoint(x:35,y:57))
                c.fill(head,with:.color(color));recordOutline(head)
                if species == .red {
                    // Red Pikmin's long pointed nose projects to the left of its face.
                    var nose=Path();nose.move(to:CGPoint(x:41,y:82));nose.addLine(to:CGPoint(x:11,y:85))
                    nose.addQuadCurve(to:CGPoint(x:42,y:92),control:CGPoint(x:26,y:90));nose.closeSubpath()
                    c.fill(nose,with:.color(color));recordOutline(nose)
                }
            }
            // Sparse, round eyes keep the expression close to Nintendo's flat silhouettes.
            let blinkPhase=(time+Double(PikminSpecies.allCases.firstIndex(of:species) ?? 0)*0.31).truncatingRemainder(dividingBy:4.8)
            let blink=time != 0 && blinkPhase>4.48 ? min(1,max(0.08,abs(blinkPhase-4.59)/0.11)) : 1
            let eyeOpen=mood == .sleeping ? 0.12 : min(blink,idle.blink)
            let eyeX=max(-1,min(1,gaze.x+idle.lookX)),eyeVertical=max(-1,min(1,gaze.y+idle.lookY))
            let look=(time==0 ? 0:sin(cycle)*0.45)+eyeX*2
            let lookY=eyeVertical*1.8
            let eyeY:Double=species == .winged ? 68 : species == .rock ? 72 : species == .purple ? 75 : 76
            let eyeXs:[Double]=species == .white ? [31,66] : species == .purple ? [24,77] : species == .winged ? [34,66] : species == .glow ? [36,67] : [31,68]
            for x in eyeXs {
                if species == .white {
                    ellipse(CGRect(x:x-6.3+eyeX*1.2,y:eyeY-6.3*eyeOpen+lookY*0.5*eyeOpen,width:12.6,height:12.6*eyeOpen),Color(islandHex:appearance?.eyeHex ?? "F0444E"))
                } else if species == .winged {
                    ellipse(CGRect(x:x-9.3,y:eyeY-9.3*eyeOpen,width:18.6,height:18.6*eyeOpen),Color(islandHex:appearance?.eyeHex ?? "2BA8C7"))
                    ellipse(CGRect(x:x-6.8+look,y:eyeY-7*eyeOpen+lookY*eyeOpen,width:10,height:10*eyeOpen),Color(islandHex:appearance?.eyeHex.map{PikminPalette.shaded($0,by:1.2)} ?? "39B8CF"))
                } else if species == .glow {
                    let radius:Double=x<50 ? 9.8:6.3
                    ellipse(CGRect(x:x-radius,y:eyeY-radius*eyeOpen,width:radius*2,height:radius*2*eyeOpen),Color(islandHex:appearance?.eyeHex ?? "3B2BE8"))
                    if x<50 {ellipse(CGRect(x:x-5.3+look,y:eyeY-5.3*eyeOpen+lookY*eyeOpen,width:10.6,height:10.6*eyeOpen),Color(islandHex:appearance?.eyeHex.map{PikminPalette.shaded($0,by:1.55)} ?? "4AE7EE"))}
                } else {
                    let radius:Double=species == .rock ? 6.7 : 6.15
                    ellipse(CGRect(x:x-radius,y:eyeY-radius*eyeOpen,width:radius*2,height:radius*2*eyeOpen),Color(islandHex:"FCFDF3"))
                    ellipse(CGRect(x:x-3+look,y:eyeY-3.2*eyeOpen+lookY*eyeOpen,width:6.2,height:6.4*eyeOpen),Color(islandHex:appearance?.eyeHex ?? "172629"))
                }
            }
            if species == .blue {
                var mouth=Path();mouth.move(to:CGPoint(x:45,y:94));mouth.addQuadCurve(to:CGPoint(x:59,y:96),control:CGPoint(x:52,y:89))
                mouth.addQuadCurve(to:CGPoint(x:45,y:94),control:CGPoint(x:52,y:93));c.fill(mouth,with:.color(Color(islandHex:"E88E9D")))
            }
            // All fills already exist. Outlines behind them produce one continuous edge
            // without expensive path-boolean operations on every animation frame.
            var border=c;border.blendMode = .destinationOver
            for item in outlinePaths {
                border.stroke(item.path,with:.color(Color(islandHex:item.hex)),style:StrokeStyle(lineWidth:max(7.2,1.5/scale),lineCap:.round,lineJoin:.round))
            }
            if question {
                let radius=max(7,4.7/scale)
                let center=CGPoint(x:82,y:35+(time==0 ? 0:sin(cycle*2)*4))
                let badge=Path(ellipseIn:CGRect(x:center.x-radius,y:center.y-radius,width:radius*2,height:radius*2))
                c.fill(badge,with:.color(Color(islandHex:outlineHex)))
                c.stroke(badge,with:.color(Color(islandHex:"FAF8E8")),lineWidth:0.7/scale)
                c.draw(Text("?").font(.system(size:radius*1.5,weight:.bold,design:.rounded)).foregroundStyle(.white),at:center)
            }
        }
    }
}

struct PikminGaze:Equatable,Sendable {
    var x:Double
    var y:Double
    static let zero=PikminGaze(x:0,y:0)
    static func towardBubble(_ bubble:CGRect,from anchor:CGRect)->PikminGaze {
        .init(x:max(-1,min(1,((bubble.midX-anchor.midX)/120).rounded())),y:abs(bubble.midY-anchor.midY)<30 ? 0:bubble.midY>=anchor.midY ? -1:1)
    }
    static func toward(_ pointer:CGPoint,from face:CGPoint,radius:Double)->PikminGaze {
        let dx=pointer.x-face.x,dy=face.y-pointer.y,distance=hypot(dx,dy)
        guard distance<radius else{return .zero}
        let t=max(0,min(1,(distance-radius*0.5)/(radius*0.5)))
        let strength=1-t*t*(3-2*t)
        return PikminGaze(x:max(-1,min(1,dx/35))*strength,y:max(-1,min(1,dy/35))*strength)
    }
}

/// Reads only the current local pointer position; no global event hook, retained
/// pointer history, permission, or source/host message is involved.
@MainActor private final class PikminCursorProbe {
    weak var view:NSView?
    func gaze(profile:PikminTopProfile)->PikminGaze {
        guard let view,let window=view.window,window.isVisible else{return .zero}
        let frame=window.convertToScreen(view.convert(view.bounds,to:nil))
        let scale=min(frame.width/100,frame.height/profile.canvasHeight)
        let face=CGPoint(x:frame.midX,y:frame.maxY-(frame.height-profile.canvasHeight*scale)/2-(profile.offset+82)*scale)
        return .toward(NSEvent.mouseLocation,from:face,radius:min(190,max(100,frame.width*2.4)))
    }
}

enum PikminPalette {
    static func shaded(_ hex:String,by factor:Double)->String {
        let value=UInt32(hex,radix:16) ?? 0
        func channel(_ shift:UInt32)->Int {Int(min(255,max(0,Double((value>>shift)&255)*factor)))}
        return String(format:"%02X%02X%02X",channel(16),channel(8),channel(0))
    }
}
private struct PikminCursorAnchor:NSViewRepresentable {
    let probe:PikminCursorProbe
    final class Anchor:NSView {override func hitTest(_ point:NSPoint)->NSView? {nil}}
    func makeNSView(context:Context)->Anchor {let view=Anchor();view.setAccessibilityElement(false);probe.view=view;return view}
    func updateNSView(_ view:Anchor,context:Context) {probe.view=view}
}
