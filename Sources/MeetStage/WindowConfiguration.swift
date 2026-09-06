import AppKit
import SwiftUI

enum ControlWindowSizing {
    static let panelWidth: CGFloat = 360
    static let panelCornerRadius: CGFloat = 16
    static let sourceRegionHeight: CGFloat = 104
    static let guidanceHeight: CGFloat = 24
    static let sourceRailInset: CGFloat = 8
    static let sourceAreaWidth = panelWidth - sourceRailInset * 2
    static let contentWidth = sourceAreaWidth
    static let size = NSSize(
        width: panelWidth,
        height: sourceRegionHeight + guidanceHeight
    )
}

/// Applies AppKit-only window behavior that SwiftUI scenes cannot express.
struct WindowConfigurator: NSViewRepresentable {
    static let stageStyleMask: NSWindow.StyleMask = [
        .titled,
        .closable,
        .miniaturizable,
        .resizable,
        .fullSizeContentView
    ]

    enum Kind {
        case stage(aspectRatio: CGFloat)
    }

    let kind: Kind

    @MainActor
    final class Coordinator {
        var lastStageAspectRatio: CGFloat?
        var stageDragView: WindowDragView?
        let stageActionTarget = StageWindowActionTarget()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(view.window, coordinator: context.coordinator)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(nsView.window, coordinator: context.coordinator)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stageDragView?.removeFromSuperview()
        coordinator.stageDragView = nil
    }

    private func configure(_ window: NSWindow?, coordinator: Coordinator) {
        guard let window else { return }

        switch kind {
        case let .stage(aspectRatio):
            configureStage(window, aspectRatio: aspectRatio, coordinator: coordinator)
        }
    }

    private func configureStage(
        _ window: NSWindow,
        aspectRatio: CGFloat,
        coordinator: Coordinator
    ) {
        let safeAspectRatio = StageWindowSizing.normalizedAspectRatio(aspectRatio)
        window.identifier = BetterMeetsWindowID.stage
        window.setFrameAutosaveName("BetterMeets.StageWindow")
        window.isReleasedWhenClosed = false
        // Keep the shared window's capture bounds stable from the empty state
        // through live presentation. Any stage frame or shadow can be flattened
        // onto black by meeting apps that do not carry window alpha.
        if window.styleMask != Self.stageStyleMask {
            window.styleMask = Self.stageStyleMask
        }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbar = nil
        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].forEach {
            window.standardWindowButton($0)?.isHidden = true
        }
        window.isMovable = true
        window.isMovableByWindowBackground = true
        window.contentAspectRatio = NSSize(width: safeAspectRatio, height: 1)
        window.collectionBehavior.remove(.fullScreenAuxiliary)
        window.collectionBehavior.formUnion([.canJoinAllSpaces, .fullScreenPrimary])
        coordinator.stageActionTarget.window = window
        installStageDragSurface(in: window, coordinator: coordinator)
        BetterMeetsWindowState.shared.refresh()

        guard let previousAspectRatio = coordinator.lastStageAspectRatio else {
            coordinator.lastStageAspectRatio = safeAspectRatio
            return
        }
        guard abs(previousAspectRatio - safeAspectRatio) > 0.001 else {
            return
        }

        let previousCenter = NSPoint(x: window.frame.midX, y: window.frame.midY)
        let screen = window.screen ?? NSScreen.main
        let currentContentSize = window.contentView?.bounds.size ?? window.contentLayoutRect.size
        let contentSize = StageWindowSizing.resizedContentSize(
            preserving: currentContentSize,
            aspectRatio: safeAspectRatio,
            fitting: screen?.visibleFrame.size ?? currentContentSize
        )
        window.setContentSize(contentSize)

        if let visibleFrame = screen?.visibleFrame {
            window.setFrameOrigin(
                Self.origin(centeredAt: previousCenter, windowSize: window.frame.size, within: visibleFrame)
            )
        }
        coordinator.lastStageAspectRatio = safeAspectRatio
    }

    private func installStageDragSurface(
        in window: NSWindow,
        coordinator: Coordinator
    ) {
        guard let contentView = window.contentView,
            let frameView = contentView.superview
        else { return }

        let dragView: WindowDragView
        if let existingDragView = coordinator.stageDragView,
            existingDragView.superview === frameView
        {
            dragView = existingDragView
        } else {
            coordinator.stageDragView?.removeFromSuperview()
            dragView = WindowDragView()
            dragView.autoresizingMask = [.width, .height]
            frameView.addSubview(dragView, positioned: .above, relativeTo: contentView)
            coordinator.stageDragView = dragView
        }
        dragView.actionTarget = coordinator.stageActionTarget

        // Keep native resize hit regions reachable around the stage perimeter.
        dragView.frame = contentView.frame.insetBy(dx: 6, dy: 6)
    }

    private static func origin(
        centeredAt center: NSPoint,
        windowSize: NSSize,
        within visibleFrame: NSRect
    ) -> NSPoint {
        let desiredOrigin = NSPoint(
            x: center.x - windowSize.width / 2,
            y: center.y - windowSize.height / 2
        )
        return NSPoint(
            x: min(max(desiredOrigin.x, visibleFrame.minX), visibleFrame.maxX - windowSize.width),
            y: min(max(desiredOrigin.y, visibleFrame.minY), visibleFrame.maxY - windowSize.height)
        )
    }
}

@MainActor
protocol WindowMenuProviding: AnyObject {
    func makeMenu() -> NSMenu
}

final class WindowDragView: NSView {
    private var dragStartPointerLocation: NSPoint?
    private var dragStartWindowOrigin: NSPoint?
    weak var actionTarget: (any WindowMenuProviding)?

    // Keep AppKit from consuming the gesture as a background-window drag.
    // This view tracks the pointer itself so movement stays 1:1 and testable.
    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .openHand)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.openHand.set()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        actionTarget?.makeMenu()
    }

    override func mouseDown(with event: NSEvent) {
        guard let window,
            let pointerLocation = pointerLocationOnScreen(for: event)
        else {
            super.mouseDown(with: event)
            return
        }

        dragStartPointerLocation = pointerLocation
        dragStartWindowOrigin = window.frame.origin
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window,
            let dragStartPointerLocation,
            let dragStartWindowOrigin,
            let pointerLocation = pointerLocationOnScreen(for: event)
        else {
            super.mouseDragged(with: event)
            return
        }

        window.setFrameOrigin(
            NSPoint(
                x: dragStartWindowOrigin.x + pointerLocation.x - dragStartPointerLocation.x,
                y: dragStartWindowOrigin.y + pointerLocation.y - dragStartPointerLocation.y
            )
        )
    }

    override func mouseUp(with event: NSEvent) {
        dragStartPointerLocation = nil
        dragStartWindowOrigin = nil
        NSCursor.openHand.set()
    }

    private func pointerLocationOnScreen(for event: NSEvent) -> NSPoint? {
        window?.convertPoint(toScreen: event.locationInWindow)
    }
}
