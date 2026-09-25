import AppKit
import SwiftUI

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WorkspaceWindowProbe() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    @MainActor
    static func configure(_ window: NSWindow) {
        window.identifier = BetterMeetsWindowID.stage
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = false
        window.contentMinSize = WorkspaceMetrics.minimumSize
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.setFrameAutosaveName("BetterMeets.Workspace")
    }
}

private final class WorkspaceWindowProbe: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        WindowConfigurator.configure(window)
    }
}
