// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Foundation

struct PikminLook:Codable,Identifiable,Equatable,Sendable {
    var id=UUID().uuidString
    var name:String
    var species:PikminSpecies
    var bodyHex:String
    var stemHex:String
    var flowerHex:String
    var leafHex="78AF38"
    var eyeHex:String?
    var stemLength=1.0
    var stemCurve=0.0
    var growth:PikminGrowth = .reference
    init(name:String,species:PikminSpecies) {
        self.name=name;self.species=species;bodyHex=species.hex;stemHex=species.top.stemHex;flowerHex=species.flowerHex
    }
    static func validHex(_ value:String)->Bool {value.count==6 && value.utf8.allSatisfy{(48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)}}
    var isValid:Bool {
        !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && name.count<=80 && [bodyHex,stemHex,flowerHex,leafHex].allSatisfy(Self.validHex) && (eyeHex.map(Self.validHex) ?? true) && stemLength.isFinite && (0.65...1.5).contains(stemLength) && stemCurve.isFinite && (-1...1).contains(stemCurve)
    }
    var assetKey:String {
        let values=[species.rawValue,bodyHex,stemHex,flowerHex,leafHex,eyeHex ?? "default",String(format:"%.3f",stemLength),String(format:"%.3f",stemCurve),growth.rawValue]
        let hash=values.joined(separator:"|").utf8.reduce(UInt64(1469598103934665603)){($0 ^ UInt64($1)) &* 1099511628211}
        return String(hash,radix:16)
    }
    var defaultEyeHex:String {
        switch species {case .white:"F0444E";case .winged:"2BA8C7";case .glow:"3B2BE8";default:"172629"}
    }
    var top:PikminTopProfile {
        var result=species.top
        result.offset += (stemLength-1)*42
        result.tipX += stemCurve*22
        result.stemHex=stemHex
        return result
    }
}
struct PikminLookEditorRequest:Identifiable {
    let id=UUID()
    var look:PikminLook
    var agentID:String?
}
