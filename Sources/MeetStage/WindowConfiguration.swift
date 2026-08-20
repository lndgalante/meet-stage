import AppKit
import SwiftUI

enum ControlWindowSizing {
    static let captureSurfaceSize = NSSize(width: 206, height: 54)
    static let controlBarWidth: CGFloat = 184
    static let controlBarHeight: CGFloat = 36
    static let controlBarOverlap: CGFloat = 6
    static let size = NSSize(
        width: captureSurfaceSize.width,
        height: captureSurfaceSize.height + controlBarHeight - controlBarOverlap
    )
    static let contentWidth: CGFloat = 196
    static let sourceAreaWidth: CGFloat = 196
}

/// Applies AppKit-only window behavior that SwiftUI scenes cannot express.
struct WindowConfigurator: NSViewRepresentable {
    enum Kind {
        case control
        case stage(aspectRatio: CGFloat)
    }

    let kind: Kind

    final class Coordinator {
        var lastStageAspectRatio: CGFloat?
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
            window.hasShadow = true
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
        let stageStyle: NSWindow.StyleMask = [.borderless, .resizable]
        if window.styleMask != stageStyle {
            window.styleMask = stageStyle
        }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbar = nil
        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].forEach {
            window.standardWindowButton($0)?.isHidden = true
        }
        window.isMovableByWindowBackground = true
        window.contentAspectRatio = NSSize(width: safeAspectRatio, height: 1)
        window.collectionBehavior.formUnion([.canJoinAllSpaces, .fullScreenAuxiliary])

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
