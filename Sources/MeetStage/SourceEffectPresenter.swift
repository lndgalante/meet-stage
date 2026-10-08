import AppKit
import SwiftUI

@MainActor
final class SourceEffectPresenter {
    private(set) var panel: SourceEffectPanel?
    private var hostingView: NSHostingView<AnyView>?
    private let frameTracker = SourceOverlayFrameTracker()
    private var sourceWindowID: CGWindowID?

    func show(
        content: some View,
        sourceWindowID: CGWindowID,
        fallbackSourceFrame: CGRect
    ) {
        if let hostingView, panel != nil, self.sourceWindowID == sourceWindowID {
            hostingView.rootView = AnyView(content)
            return
        }
        dismiss()

        self.sourceWindowID = sourceWindowID

        let panel = SourceEffectPanel(
            contentRect: SourceOverlayGeometry.currentAppKitFrame(
                for: sourceWindowID,
                fallbackSourceFrame: fallbackSourceFrame
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        SourceEffectWindowPolicy.configure(panel)
        let hostingView = NSHostingView(rootView: AnyView(content))
        self.hostingView = hostingView
        panel.contentView = hostingView
        self.panel = panel
        panel.orderFrontRegardless()

        frameTracker.start(
            sourceWindowID: sourceWindowID,
            fallbackSourceFrame: fallbackSourceFrame
        ) { [weak panel] frame in
            guard let panel, panel.frame != frame else { return }
            panel.setFrame(frame, display: true)
        }
    }

    func dismiss() {
        frameTracker.stop()
        sourceWindowID = nil
        panel?.close()
        panel = nil
        hostingView = nil
    }
}

enum SourceEffectWindowPolicy {
    static let sourceOverlayLevel = NSWindow.Level(
        rawValue: NSWindow.Level.normal.rawValue + 1
    )

    @MainActor
    static func configure(_ panel: SourceEffectPanel) {
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.ignoresMouseEvents = true
        panel.level = sourceOverlayLevel
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .transient
        ]
    }
}

final class SourceEffectPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
