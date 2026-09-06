import AppKit
import SwiftUI

@MainActor
final class ControlWindowController {
    static let shared = ControlWindowController()
    private var window: ControlWindow?

    func show(manager: CaptureManager, openSettings: @escaping () -> Void) {
        if window == nil {
            let window = ControlWindow()
            window.openSettingsAction = openSettings
            window.contentView = NSHostingView(
                rootView: ControlView(manager: manager, openSettings: openSettings)
            )
            window.restorePosition()
            window.installDragSurface()
            self.window = window
        }
        BetterMeetsWindowActions.showController()
    }
}

final class ControlWindow: NSWindow, WindowMenuProviding {
    var openSettingsAction: (() -> Void)?
    private let dragSurface = WindowDragView()

    // Borderless NSWindow defaults reject focus, including Full Keyboard Access.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performClose(_ sender: Any?) {
        close()
    }

    override func performMiniaturize(_ sender: Any?) {
        miniaturize(sender)
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(performClose(_:)) || menuItem.action == #selector(performMiniaturize(_:)) {
            return isVisible && !isMiniaturized
        }
        return super.validateMenuItem(menuItem)
    }

    init() {
        super.init(
            contentRect: CGRect(origin: .zero, size: ControlWindowSizing.size),
            styleMask: [.borderless, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        title = "BetterMeets"
        identifier = BetterMeetsWindowID.control
        isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = true
        isMovableByWindowBackground = true
        minSize = ControlWindowSizing.size
        maxSize = ControlWindowSizing.size
    }

    func restorePosition() {
        let restored = setFrameUsingName("BetterMeets.ControlWindow")
        setContentSize(ControlWindowSizing.size)
        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(frame) } ?? NSScreen.main
        if let bounds = screen?.visibleFrame {
            let origin = restored ? frame.origin : CGPoint(x: bounds.maxX - frame.width - 24, y: bounds.minY + 24)
            setFrameOrigin(
                CGPoint(
                    x: min(max(origin.x, bounds.minX), bounds.maxX - frame.width),
                    y: min(max(origin.y, bounds.minY), bounds.maxY - frame.height)
                )
            )
        }
        setFrameAutosaveName("BetterMeets.ControlWindow")
    }

    func installDragSurface() {
        guard let contentView, let frameView = contentView.superview else { return }
        dragSurface.actionTarget = self
        dragSurface.frame = NSRect(
            x: contentView.frame.minX,
            y: contentView.frame.minY,
            width: contentView.frame.width,
            height: ControlWindowSizing.guidanceHeight
        )
        dragSurface.autoresizingMask = [.width, .maxYMargin]
        // SwiftUI's hosting view consumes background drags; the footer's native surface must sit above it.
        frameView.addSubview(dragSurface, positioned: .above, relativeTo: contentView)
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Minimize Controller", action: #selector(performMiniaturize(_:)), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "Hide Controller", action: #selector(hideController), keyEquivalent: "").target = self
        return menu
    }

    @objc private func showSettings() { openSettingsAction?() }

    @objc private func hideController() { BetterMeetsWindowActions.hideController() }
}
