// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Foundation

struct HeadPendulum {
    private(set) var angle=0.0
    private var angularVelocity=0.0
    mutating func step(cursorVelocity:Double,anchorX:Double,dt:Double)->Double {
        let step=min(0.035,max(0.001,dt))
        let speed=cursorVelocity.isFinite ? max(-1800,min(1800,cursorVelocity)):0
        let rest=(max(0,min(1,anchorX))-0.5)*0.16
        let target=rest+max(-0.24,min(0.24,speed*0.00017))
        angularVelocity+=(95*(target-angle)-13*angularVelocity)*step
        angle=max(-0.34,min(0.34,angle+angularVelocity*step))
        return angle*180/Double.pi
    }
}
