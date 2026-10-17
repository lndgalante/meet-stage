import AppKit
import SwiftUI

/// A borderless panel that takes clicks and menus without activating
/// BetterMeets, and stays where it's put, even over the menu bar. The
/// teleprompter and the demo notice are both islands in one.
final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    /// A panel for an island: never activating BetterMeets, on every Space and
    /// over full-screen apps, untouched by hiding BetterMeets, with no shadow,
    /// and left out of screen capture where that's honored. Its owner sizes it
    /// and shows it with `orderFrontRegardless`.
    @MainActor static func make(title: String, rootView: some View) -> IslandPanel {
        let panel = IslandPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = title
        panel.isFloatingPanel = true
        // Above the menu bar (24) and its status items (25), below other apps' menus, Spotlight and notifications.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        // Hiding BetterMeets leaves the island, and showing the island never unhides BetterMeets.
        panel.canHide = false
        // It's used from other apps, so its help tags must show while BetterMeets is inactive.
        panel.allowsToolTipsWhenApplicationIsInactive = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .none
        panel.sharingType = .none
        let host = IslandHostingView(rootView: rootView)
        // The owner sizes the panel; the view never pushes its own size onto it.
        host.sizingOptions = []
        panel.contentView = host
        return panel
    }
}

/// Acts on the first click, so a button works while the source app stays frontmost.
private final class IslandHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
