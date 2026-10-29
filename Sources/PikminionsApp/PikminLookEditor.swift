// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import AppKit
import SwiftUI
import Antille

struct PikminLookEditor:View {
    @Bindable var model:SquadModel
    let request:PikminLookEditorRequest
    @State private var draft:PikminLook
    init(model:SquadModel,request:PikminLookEditorRequest) {self.model=model;self.request=request;_draft=State(initialValue:request.look)}
    private var usage:Int {model.lookAssignments.values.filter{$0==draft.id}.count}
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Custom Pikmin").font(.title2.weight(.semibold))
            HStack(spacing:22) {
                PikminHead(species:draft.species,mood:.calm,growth:model.growth,animated:false,appearance:draft).frame(width:112,height:140)
                VStack(alignment:.leading,spacing:12) {
                    TextField("Look name",text:$draft.name).textFieldStyle(.roundedBorder)
                    Picker("Head shape",selection:$draft.species) {ForEach(PikminSpecies.allCases) {species in Text(species.name).tag(species)}}
                    Picker("Top",selection:$draft.growth) {ForEach(PikminGrowth.allCases,id:\.self) {Text($0.title).tag($0)}}
                    if usage>1 {Text("Used by \(usage) Pikmin. Saving updates their shared look.").font(.caption).foregroundStyle(.secondary)}
                }
            }
            Form {
                Section("Colors") {
                    colorRow("Body",\.bodyHex)
                    colorRow("Stem",\.stemHex)
                    colorRow("Flower",\.flowerHex)
                    HStack {
                        ColorPicker("Eyes",selection:Binding(get:{Color(islandHex:draft.eyeHex ?? draft.defaultEyeHex)},set:{draft.eyeHex=hex($0,fallback:draft.defaultEyeHex)}),supportsOpacity:false)
                        TextField("Eye hex color",text:Binding(get:{draft.eyeHex ?? draft.defaultEyeHex},set:{draft.eyeHex=String($0.prefix(6)).uppercased()})).labelsHidden().textFieldStyle(.roundedBorder).font(.system(.caption,design:.monospaced)).frame(width:72).accessibilityLabel("Eye hex color")
                    }
                    colorRow("Leaf",\.leafHex)
                }
                Section("Stem") {
                    LabeledContent("Length") {
                        HStack {Slider(value:$draft.stemLength,in:0.65...1.5,step:0.01).labelsHidden().accessibilityLabel("Stem length");Text(draft.stemLength,format:.number.precision(.fractionLength(2))).monospacedDigit().frame(width:36)}
                    }
                    LabeledContent("Curve") {
                        HStack {Slider(value:$draft.stemCurve,in:-1...1,step:0.05).labelsHidden().accessibilityLabel("Stem curve");Text(draft.stemCurve,format:.number.precision(.fractionLength(2))).monospacedDigit().frame(width:36)}
                    }
                }
            }.formStyle(.grouped)
            HStack {
                Button("Use species colors") {let fresh=PikminLook(name:draft.name,species:draft.species);draft.bodyHex=fresh.bodyHex;draft.stemHex=fresh.stemHex;draft.flowerHex=fresh.flowerHex;draft.leafHex=fresh.leafHex;draft.eyeHex=nil}
                Spacer()
                Button("Cancel") {model.lookEditor=nil}.keyboardShortcut(.cancelAction)
                Button("Save look") {model.saveLook(draft,for:request.agentID)}.keyboardShortcut(.defaultAction).disabled(!draft.isValid)
            }
        }.padding(22).frame(width:540,height:650)
    }
    private func colorRow(_ label:String,_ key:WritableKeyPath<PikminLook,String>)->some View {
        HStack {
            ColorPicker(label,selection:color(key),supportsOpacity:false)
            TextField(label+" hex color",text:Binding(get:{draft[keyPath:key]},set:{draft[keyPath:key]=String($0.prefix(6)).uppercased()})).labelsHidden().textFieldStyle(.roundedBorder).font(.system(.caption,design:.monospaced)).frame(width:72).accessibilityLabel(label+" hex color")
        }
    }
    private func color(_ key:WritableKeyPath<PikminLook,String>)->Binding<Color> {Binding(get:{Color(islandHex:draft[keyPath:key])},set:{draft[keyPath:key]=hex($0,fallback:draft[keyPath:key])})}
    private func hex(_ color:Color,fallback:String)->String {
        guard let value=NSColor(color).usingColorSpace(.sRGB) else{return fallback}
        return String(format:"%02X%02X%02X",Int((value.redComponent*255).rounded()),Int((value.greenComponent*255).rounded()),Int((value.blueComponent*255).rounded()))
    }
}
