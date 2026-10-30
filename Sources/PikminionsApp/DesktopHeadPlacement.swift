// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Foundation

enum DesktopHeadPlacement {
    static let gap:CGFloat=12

    /// Keep a free saved position; otherwise stack upward, then into columns
    /// to the left. Actual panel bounds include room for stems and hover labels.
    static func frame(size:CGSize,preferred:CGPoint?=nil,screen:CGRect,occupied:[CGRect])->CGRect {
        func bounded(_ point:CGPoint)->CGRect {
            CGRect(x:max(screen.minX,min(max(screen.minX,screen.maxX-size.width),point.x)),
                   y:max(screen.minY,min(max(screen.minY,screen.maxY-size.height),point.y)),width:size.width,height:size.height)
        }
        let home=bounded(CGPoint(x:screen.maxX-19-size.width,y:screen.minY+30))
        let initial=preferred.flatMap{$0.x.isFinite && $0.y.isFinite ? bounded($0):nil} ?? home
        let obstacles=occupied.filter{$0.intersects(screen)}.map{$0.insetBy(dx:-gap,dy:-gap)}
        func overlap(_ candidate:CGRect)->CGFloat {
            obstacles.reduce(0) {area,obstacle in
                let intersection=candidate.intersection(obstacle)
                return area+(intersection.isNull ? 0:intersection.width*intersection.height)
            }
        }
        var best=initial,bestOverlap=overlap(initial)
        if bestOverlap==0 {return initial}
        let leftEdges=Array(Set(obstacles.map{$0.minX-size.width})).sorted(by:>)
        let topEdges=Array(Set(obstacles.map(\.maxY))).sorted()
        let xs=[initial.minX,home.minX]+leftEdges+[screen.minX]
        let ys=[initial.minY]+topEdges.filter{$0>=initial.minY}+[home.minY,screen.minY]+topEdges.filter{$0<initial.minY}
        for x in xs {
            for y in ys {
                let candidate=CGRect(origin:CGPoint(x:x,y:y),size:size)
                guard screen.contains(candidate) else {continue}
                let area=overlap(candidate)
                if area==0 {return candidate}
                // A fully occupied or unusually small display still gets a
                // bounded, least-obscured position without moving other heads.
                if area<bestOverlap {best=candidate;bestOverlap=area}
            }
        }
        return best
    }
}
