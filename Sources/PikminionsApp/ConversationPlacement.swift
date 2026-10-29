// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Foundation

enum ConversationPlacement {
    static func frame(anchor:CGRect,screen:CGRect,preferred:CGSize)->CGRect {
        let safe=screen.insetBy(dx:10,dy:10)
        // Includes the six-point attention shift and breathing room for the stem.
        let head=anchor.insetBy(dx:-12,dy:-12)
        let width=min(preferred.width,safe.width),height=min(preferred.height,safe.height)
        func clamp(_ value:Double,_ low:Double,_ high:Double)->Double {max(low,min(high,value))}
        let x=clamp(anchor.midX-width/2,safe.minX,safe.maxX-width)
        let above=max(0,safe.maxY-head.maxY),below=max(0,head.minY-safe.minY)
        if above>=height {return CGRect(x:x,y:head.maxY,width:width,height:height)}
        if below>=height {return CGRect(x:x,y:head.minY-height,width:width,height:height)}
        if max(above,below)>=280 {
            let h=min(height,max(above,below))
            return CGRect(x:x,y:above>=below ? head.maxY:head.minY-h,width:width,height:h)
        }
        let left=max(0,head.minX-safe.minX),right=max(0,safe.maxX-head.maxX)
        let y=clamp(anchor.midY-height/2,safe.minY,safe.maxY-height)
        if max(left,right)>=min(320,width) {
            let w=min(width,max(left,right))
            return CGRect(x:right>=left ? head.maxX:head.minX-w,y:y,width:w,height:height)
        }
        // A very small display still gets the largest unobscured vertical region.
        let h=min(height,max(above,below))
        return CGRect(x:x,y:above>=below ? head.maxY:head.minY-h,width:width,height:h)
    }
}
