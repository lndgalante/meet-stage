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

final class ControlWindow: NSWindow, WindowMenuProviding, NSGestureRecognizerDelegate {
    var openSettingsAction: (() -> Void)?
    private let dragSurface = WindowDragView()
    private lazy var dockAttachment = ControlDockAttachment(window: self)
    private lazy var dragGesture = NSPanGestureRecognizer(target: self, action: #selector(dragWidget(_:)))
    private var dragStartOrigin: NSPoint?
    private var dragStartPointer: NSPoint?
    private static let frameName = "BetterMeets.ControlWindow"

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
        isMovableByWindowBackground = false
        minSize = ControlWindowSizing.size
        maxSize = ControlWindowSizing.size
    }

    func restorePosition() {
        // Native restoration clamps to visibleFrame and would lift a saved position above the Dock.
        let origin = ControlWindowPlacement.savedOrigin(
            from: UserDefaults.standard.string(forKey: "NSWindow Frame \(Self.frameName)")
        )
        let screen = origin.flatMap { origin in NSScreen.screens.first { $0.frame.contains(origin) } } ?? NSScreen.main
        position(on: screen, savedOrigin: origin)
        setFrameAutosaveName(Self.frameName)
        dockAttachment.restore()
    }

    @objc func placeBesideDock() {
        if !dockAttachment.attach() {
            position(on: screen ?? NSScreen.main, savedOrigin: nil)
        }
        saveFrame(usingName: Self.frameName)
    }

    private func position(on screen: NSScreen?, savedOrigin: CGPoint?) {
        guard let screen else { return }
        setFrame(
            ControlWindowPlacement.frame(
                size: ControlWindowSizing.size, screen: screen.frame, visibleScreen: screen.visibleFrame,
                dock: DockFrameResolver.currentFrame(), savedOrigin: savedOrigin
            ),
            display: true
        )
    }

    func installDragSurface() {
        guard let contentView, let frameView = contentView.superview else { return }
        dragSurface.actionTarget = self
        dragSurface.dragHandler = dockAttachment
        dragSurface.toolTip = String(
            localized: "Drag anywhere to move. Release near the Dock to attach. Option skips snapping.")
        dragSurface.frame = NSRect(
            x: contentView.frame.minX,
            y: contentView.frame.minY,
            width: contentView.frame.width,
            height: ControlWindowSizing.guidanceHeight
        )
        dragSurface.autoresizingMask = [.width, .maxYMargin]
        // SwiftUI's hosting view consumes background drags; the footer's native surface must sit above it.
        frameView.addSubview(dragSurface, positioned: .above, relativeTo: contentView)
        // Delay clicks until the pan fails so dragging a preview cannot select it.
        dragGesture.delaysPrimaryMouseButtonEvents = true
        dragGesture.delegate = self
        frameView.addGestureRecognizer(dragGesture)
    }

    func gestureRecognizer(
        _ gestureRecognizer: NSGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: NSGestureRecognizer
    ) -> Bool {
        gestureRecognizer === dragGesture
    }

    @objc private func dragWidget(_ gesture: NSPanGestureRecognizer) {
        let pointer = convertPoint(toScreen: gesture.location(in: nil))
        if gesture.state == .began {
            dragStartOrigin = frame.origin
            let translation = gesture.translation(in: nil)
            dragStartPointer = NSPoint(x: pointer.x - translation.x, y: pointer.y - translation.y)
            dockAttachment.beginDragging()
            NSCursor.closedHand.set()
        }
        guard let dragStartOrigin, let dragStartPointer else { return }

        if gesture.state == .began || gesture.state == .changed || gesture.state == .ended {
            let origin = NSPoint(
                x: dragStartOrigin.x + pointer.x - dragStartPointer.x,
                y: dragStartOrigin.y + pointer.y - dragStartPointer.y
            )
            setFrameOrigin(dockAttachment.dragOrigin(for: origin, bypassSnap: gesture.modifierFlags.contains(.option)))
        }

        if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
            if gesture.state != .ended {
                _ = dockAttachment.dragOrigin(for: frame.origin, bypassSnap: true)
            }
            dockAttachment.endDragging()
            self.dragStartOrigin = nil
            self.dragStartPointer = nil
            NSCursor.arrow.set()
        }
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Place Beside Dock", action: #selector(placeBesideDock), keyEquivalent: "").target =
            self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Minimize Controller", action: #selector(performMiniaturize(_:)), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "Hide Controller", action: #selector(hideController), keyEquivalent: "").target = self
        return menu
    }

    @objc private func showSettings() { openSettingsAction?() }

    @objc private func hideController() { BetterMeetsWindowActions.hideController() }
}
