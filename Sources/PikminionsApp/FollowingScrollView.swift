// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import SwiftUI
import AppKit

/// Follows arriving output, while leaving an intentional scroll-back undisturbed.
struct FollowingScrollView<Revision:Equatable,Content:View>:View {
    let revision:Revision
    @ViewBuilder let content:()->Content
    @State private var following=true
    @State private var contentSize=CGSize.zero
    @State private var viewportSize=CGSize.zero
    var body:some View {
        ScrollViewReader { reader in
            VStack(spacing:0) {
                ScrollView {
                    VStack(alignment:.leading,spacing:0) {
                        content()
                        Color.clear.frame(height:1).id("following-output-end")
                    }.background(ConversationScrollObserver {atEnd in
                        if following != atEnd {following=atEnd}
                    }).background(GeometryReader {geometry in Color.clear.preference(key:FollowingContentSize.self,value:geometry.size)})
                }.modifier(LatestInitialAnchor()).accessibilityIdentifier("conversation-output")
                    .background(GeometryReader {geometry in Color.clear.preference(key:FollowingViewportSize.self,value:geometry.size)})
                    .onPreferenceChange(FollowingContentSize.self) {contentSize=$0}
                    .onPreferenceChange(FollowingViewportSize.self) {viewportSize=$0}
                HStack {
                    Spacer()
                    Button {
                        following=true
                        reader.scrollTo("following-output-end",anchor:.bottom)
                    } label:{Label("Latest",systemImage:"arrow.down")}
                        .buttonStyle(.plain).font(.system(size:10)).foregroundStyle(.secondary)
                        .accessibilityLabel("Follow latest output")
                        .opacity(following ? 0:1).allowsHitTesting(!following).accessibilityHidden(following)
                }.frame(height:16).padding(.horizontal,12)
            }
            .task(id:FollowingLayoutRevision(revision:revision,content:contentSize,viewport:viewportSize)) {
                guard following else{return}
                await Task.yield()
                guard !Task.isCancelled,following else{return}
                reader.scrollTo("following-output-end",anchor:.bottom)
            }
        }
    }
}

private struct FollowingLayoutRevision<Revision:Equatable>:Equatable {var revision:Revision;var content:CGSize;var viewport:CGSize}
private struct FollowingContentSize:PreferenceKey {static let defaultValue=CGSize.zero;static func reduce(value:inout CGSize,nextValue:()->CGSize) {value=nextValue()}}
private struct FollowingViewportSize:PreferenceKey {static let defaultValue=CGSize.zero;static func reduce(value:inout CGSize,nextValue:()->CGSize) {value=nextValue()}}
private struct LatestInitialAnchor:ViewModifier {
    @ViewBuilder func body(content:Content)->some View {
        if #available(macOS 15,*) {content.defaultScrollAnchor(.bottom,for:.initialOffset)}
        else {content.defaultScrollAnchor(.bottom)}
    }
}

/// AppKit's clip-view notifications cover wheel, keyboard and scrollbar input on
/// macOS 14 as well as current systems. Layout growth alone does not pause follow.
private struct ConversationScrollObserver:NSViewRepresentable {
    let changed:(Bool)->Void
    final class Probe:NSView {
        var changed:((Bool)->Void)?
        private weak var clip:NSClipView?
        private var observer:Any?
        private var previousOffset:Double?
        private var previousDocumentHeight:CGFloat?
        override func hitTest(_ point:NSPoint)->NSView? {nil}
        override func viewDidMoveToWindow() {super.viewDidMoveToWindow();install()}
        override func viewDidMoveToSuperview() {super.viewDidMoveToSuperview();install()}
        override func layout() {super.layout();install()}
        func install() {
            guard window != nil,let current=enclosingScrollView?.contentView else {detach();return}
            guard current !== clip else{return}
            detach();clip=current;current.postsBoundsChangedNotifications=true
            previousOffset=current.documentVisibleRect.minY
            previousDocumentHeight=current.documentView?.bounds.height
            observer=NotificationCenter.default.addObserver(forName:NSView.boundsDidChangeNotification,object:current,queue:.main) { [weak self] _ in
                MainActor.assumeIsolated {self?.observePosition()}
            }
        }
        private func observePosition() {
            guard let clip,let document=clip.documentView else{return}
            let visible=clip.documentVisibleRect
            let atEnd=isAtEnd(clip:clip,document:document)
            let offset=visible.minY
            let towardStart=previousOffset.map{document.isFlipped ? offset<$0-1:offset>$0+1} ?? false
            let contentResized=previousDocumentHeight.map{abs(document.bounds.height-$0)>1} ?? false
            previousOffset=offset
            previousDocumentHeight=document.bounds.height
            guard atEnd || (towardStart && !contentResized) else{return}
            DispatchQueue.main.async { [weak self,weak clip] in
                guard let self,let clip,self.clip===clip,let document=clip.documentView else{return}
                // Content can shrink between the bounds notification and this
                // callback, for example when a question replaces vocal output.
                self.changed?(self.isAtEnd(clip:clip,document:document))
            }
        }
        private func isAtEnd(clip:NSClipView,document:NSView)->Bool {
            let visible=clip.documentVisibleRect
            if document.bounds.height<=visible.height+14 {return true}
            return document.isFlipped ? visible.maxY>=document.bounds.maxY-14:visible.minY<=document.bounds.minY+14
        }
        func detach() {if let observer {NotificationCenter.default.removeObserver(observer)};observer=nil;clip=nil;previousOffset=nil;previousDocumentHeight=nil}
    }
    func makeNSView(context:Context)->Probe {let view=Probe();view.changed=changed;view.setAccessibilityElement(false);return view}
    func updateNSView(_ view:Probe,context:Context) {view.changed=changed}
    static func dismantleNSView(_ view:Probe,coordinator:()) {view.detach()}
}
