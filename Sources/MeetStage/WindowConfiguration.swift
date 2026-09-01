import AppKit
import SwiftUI

enum ControlWindowSizing {
    // The controller is one cohesive panel: a top drag grip, the source row, a
    // hairline divider, then the six effect toggles split three-per-side around
    // a center notch. The Demo Mode voice control is a circular hero button the
    // panel bottom cradles and that protrudes just below it — the headline
    // "talk to your demo" action, unmistakable and part of the whole.
    static let panelWidth: CGFloat = 262
    static let panelCornerRadius: CGFloat = 15

    // Vertical bands that stack inside the panel — kept trim so the widget reads
    // slim rather than chunky.
    static let grabRegionHeight: CGFloat = 10
    static let sourceRegionHeight: CGFloat = 58
    static let effectBarHeight: CGFloat = 32
    static let panelBodyHeight =
        grabRegionHeight + sourceRegionHeight + effectBarHeight

    /// Widths retained by the source picker and effect groups. The source row
    /// sits just 6pt inside each panel edge so the tiles read as filling the
    /// widget rather than floating in a margin.
    static let sourceAreaWidth: CGFloat = 250
    static let contentWidth = sourceAreaWidth
    static let controlBarWidth: CGFloat = 244

    /// Hero (Demo Mode) geometry. Its center sits on the panel's bottom edge; the
    /// panel bottom scoops UP in a concave semicircle the disc seats into — top
    /// half embedded, bottom half protruding — so there is a single clean edge,
    /// not a disc floating inside an oversized hole.
    static let heroDiameter: CGFloat = 44
    static let heroGap: CGFloat = 60
    /// Slightly smaller than the disc so the disc covers the cut: one visible edge.
    static let heroNotchRadius: CGFloat = heroDiameter / 2 - 0.5
    /// How far the disc center sits ABOVE the panel's bottom edge, so the disc is
    /// mostly embedded and only its lower ~third protrudes (feels part of the UI).
    static let heroRise: CGFloat = 9
    /// Center/bottom of the hero, measured from the panel's top edge.
    static let heroCenterY = panelBodyHeight - heroRise
    static let heroBottomInPanel = heroCenterY + heroDiameter / 2

    /// Transparent margin around the panel — wider than the shadow's reach so the
    /// soft shadow fades to nothing (a rounded halo) well before the window's
    /// rectangular edge, instead of saturating the margin into a light rectangle.
    static let shadowMargin: CGFloat = 30
    static let size = NSSize(
        width: panelWidth + shadowMargin * 2,
        height: heroBottomInPanel + shadowMargin * 2
    )

    // Absolute positions inside the window (panel is inset by the shadow margin).
    static let panelTop = shadowMargin
    static let heroCenterYAbsolute = shadowMargin + heroCenterY

    // Legacy accessors kept for the source-picker layout math.
    static let captureSurfaceSize = NSSize(width: panelWidth, height: sourceRegionHeight)
    static let dragHandleHitWidth: CGFloat = 96
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
        case control
        case stage(aspectRatio: CGFloat)
    }

    let kind: Kind

    final class Coordinator {
        var lastStageAspectRatio: CGFloat?
        var stageDragView: WindowDragView?
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
        case .control:
            let compactSize = ControlWindowSizing.size
            window.level = .floating
            window.collectionBehavior.formUnion([.canJoinAllSpaces, .fullScreenAuxiliary])
            window.styleMask = [.borderless]
            window.isOpaque = false
            window.backgroundColor = .clear
            // The panel draws its own soft SwiftUI shadow; the native window
            // shadow would trace the notched silhouette as a crisp dark line.
            window.hasShadow = false
            window.isMovable = true
            window.isMovableByWindowBackground = true
            window.setContentSize(compactSize)
            window.minSize = compactSize
            window.maxSize = compactSize
            if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(window.frame) }) {
                window.center()
            }

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
        window.collectionBehavior.formUnion([.canJoinAllSpaces, .fullScreenAuxiliary])
        installStageDragSurface(in: window, coordinator: coordinator)

        guard coordinator.lastStageAspectRatio.map({ abs($0 - safeAspectRatio) > 0.001 }) ?? true else {
            return
        }

        let previousCenter = NSPoint(x: window.frame.midX, y: window.frame.midY)
        let screen = window.screen ?? NSScreen.main
        let contentSize = StageWindowSizing.defaultWindowContentSize(
            aspectRatio: safeAspectRatio,
            on: screen
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

final class WindowDragView: NSView {
    private var dragStartPointerLocation: NSPoint?
    private var dragStartWindowOrigin: NSPoint?

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
