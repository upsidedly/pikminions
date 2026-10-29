// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import SwiftUI

/// Matches the light tile and generous inset of Matthew's Tuck/Snap icons.
struct PikminionsAppIcon:View {
    var body:some View {
        ZStack {
            RoundedRectangle(cornerRadius:205).fill(Color(white:0.94)).frame(width:904,height:904)
            PikminionsIconArtwork()
                .frame(width:780,height:780).rotationEffect(.degrees(-11)).offset(x:10,y:34)
        }.frame(width:1024,height:1024)
    }
}

private struct PikminionsIconArtwork:View {
    var body:some View {
        Canvas { context,size in
            var c=context
            let scale=min(size.width/100,size.height/120)
            c.translateBy(x:(size.width-100*scale)/2,y:(size.height-120*scale)/2)
            c.scaleBy(x:scale,y:scale)
            c.translateBy(x:0,y:-4)
            let edge=StrokeStyle(lineWidth:7.2,lineCap:.round,lineJoin:.round)
            let red=Color(islandHex:PikminSpecies.red.hex)
            let redEdge=Color(islandHex:PikminSpecies.red.outlineHex)

            // One contour gives the stem, head and nose a continuous outside edge.
            // The stem tip extends inside the leaf so its cap is fully concealed.
            var head=Path();head.move(to:CGPoint(x:53.5,y:32))
            head.addCurve(to:CGPoint(x:44.5,y:55.4),control1:CGPoint(x:51,y:40.5),control2:CGPoint(x:49,y:54.7))
            head.addCurve(to:CGPoint(x:25,y:78),control1:CGPoint(x:33,y:57),control2:CGPoint(x:24,y:65))
            head.addQuadCurve(to:CGPoint(x:25.5,y:83.55),control:CGPoint(x:24.8,y:80.5))
            head.addLine(to:CGPoint(x:11,y:85))
            head.addQuadCurve(to:CGPoint(x:29.2,y:89.9),control:CGPoint(x:19.5,y:88.5))
            head.addCurve(to:CGPoint(x:52,y:110),control1:CGPoint(x:34,y:98),control2:CGPoint(x:43,y:106))
            head.addCurve(to:CGPoint(x:75,y:77),control1:CGPoint(x:62,y:103),control2:CGPoint(x:75,y:92))
            head.addCurve(to:CGPoint(x:57,y:56.2),control1:CGPoint(x:75,y:64),control2:CGPoint(x:67,y:57))
            head.addCurve(to:CGPoint(x:57.5,y:32),control1:CGPoint(x:51.5,y:55.8),control2:CGPoint(x:55,y:40.5))
            head.closeSubpath()
            c.stroke(head,with:.color(redEdge),style:edge)
            c.fill(head,with:.color(red))

            // Paint the complete leaf above the stem, including its own border.
            var plant=c;plant.translateBy(x:52,y:38)
            var leaf=Path();leaf.move(to:.zero)
            leaf.addCurve(to:CGPoint(x:39,y:-19),control1:CGPoint(x:4,y:-28),control2:CGPoint(x:26.52,y:-30))
            leaf.addCurve(to:.zero,control1:CGPoint(x:28.08,y:-11),control2:CGPoint(x:10,y:-2))
            plant.stroke(leaf,with:.color(Color(islandHex:"2B4916")),style:edge)
            plant.fill(leaf,with:.color(Color(islandHex:"78AF38")))
            var vein=Path();vein.move(to:CGPoint(x:2,y:-2))
            vein.addQuadCurve(to:CGPoint(x:34,y:-19),control:CGPoint(x:15.6,y:-16))
            plant.stroke(vein,with:.color(Color(islandHex:"B0D96E")),style:StrokeStyle(lineWidth:1.1,lineCap:.round))

            c.fill(Path(ellipseIn:CGRect(x:24.85,y:69.85,width:12.3,height:12.3)),with:.color(Color(islandHex:"FCFDF3")))
            c.fill(Path(ellipseIn:CGRect(x:28,y:72.8,width:6.2,height:6.4)),with:.color(Color(islandHex:"172629")))
            var wink=Path();wink.move(to:CGPoint(x:69,y:73))
            wink.addLine(to:CGPoint(x:63,y:76));wink.addLine(to:CGPoint(x:69,y:79))
            c.stroke(wink,with:.color(redEdge),style:StrokeStyle(lineWidth:3.4,lineCap:.round,lineJoin:.round))
        }
    }
}
