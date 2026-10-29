// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Foundation

enum PikminSize:String,CaseIterable,Codable,Identifiable,Sendable {
    case small,medium,large,xl
    var id:String {rawValue}
    var title:String {self == .xl ? "XL":rawValue.capitalized}
    var scale:Double {panelWidth/86}
    private var panelWidth:Double {switch self {case .small:64;case .medium:86;case .large:112;case .xl:142}}
    var panelSize:CGSize {CGSize(width:panelWidth,height:ceil(116*scale))}
    var artSize:CGSize {CGSize(width:74*scale,height:89*scale)}
    static func artCenter(in frame:CGRect)->CGPoint {
        CGPoint(x:frame.midX,y:frame.maxY-89*(frame.width/86)/2)
    }
    func resizedFrame(from frame:CGRect,within screen:CGRect)->CGRect {
        let center=Self.artCenter(in:frame),size=panelSize
        let origin=CGPoint(x:center.x-size.width/2,y:center.y-size.height+artSize.height/2)
        return CGRect(x:max(screen.minX,min(screen.maxX-size.width,origin.x)),
                      y:max(screen.minY,min(screen.maxY-size.height,origin.y)),width:size.width,height:size.height)
    }
}
