import AppKit
import SwiftUI
import Testing
@testable import MeetStage

@Suite("Stage interaction")
struct StageInteractionTests {
    @Test("The topmost stage surface tracks pointer movement 1:1")
    @MainActor
    func renderingSurfaceStartsWindowDrag() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 640, height: 360),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        let surface = WindowDragView(frame: window.contentView?.bounds ?? .zero)
        window.contentView = surface
        let initialOrigin = window.frame.origin

        surface.mouseDown(
            with: try mouseEvent(
                type: .leftMouseDown,
                location: NSPoint(x: 320, y: 180),
                in: window
            )
        )
        surface.mouseDragged(
            with: try mouseEvent(
                type: .leftMouseDragged,
                location: NSPoint(x: 344, y: 167),
                in: window
            )
        )

        #expect(!surface.mouseDownCanMoveWindow)
        #expect(window.frame.origin.x == initialOrigin.x + 24)
        #expect(window.frame.origin.y == initialOrigin.y - 13)
    }

    @Test("The source rail uses one balanced inset and gap")
    func sourceRailSpacingIsBalanced() {
        let inset = ControlWindowSizing.sourceRailInset

        #expect((ControlWindowSizing.panelWidth - ControlWindowSizing.sourceAreaWidth) / 2 == inset)
        #expect(ControlMetrics.sourceTileSpacing == inset)
        #expect(ControlMetrics.sourceTileVerticalInset == inset)
        #expect(
            ControlMetrics.sourceTileWidth * ControlMetrics.visibleSourceTileCount
                + ControlMetrics.sourceTileSpacing
                * (ControlMetrics.visibleSourceTileCount - 1)
                == ControlWindowSizing.sourceAreaWidth
        )
        #expect(
            ControlMetrics.sourceTileHeight + ControlMetrics.sourceTileVerticalInset * 2
                == ControlWindowSizing.sourceRegionHeight
        )
        #expect(ControlMetrics.sourceTileRadius + inset == ControlWindowSizing.panelCornerRadius)
        #expect(
            ControlMetrics.sourcePreviewHeight + ControlMetrics.sourceLabelSpacing + ControlMetrics.sourceLabelHeight
                == ControlMetrics.sourceTileHeight
        )
    }

    @Test("The stage keeps standard macOS window semantics")
    @MainActor
    func stageUsesStandardWindowStyle() {
        #expect(WindowConfigurator.stageStyleMask.contains(.titled))
        #expect(WindowConfigurator.stageStyleMask.contains(.resizable))
        #expect(WindowConfigurator.stageStyleMask.contains(.fullSizeContentView))
    }

    @Test("The controller has no hidden title bar or transparent shadow margins")
    @MainActor
    func controllerFitsVisibleSurface() async throws {
        let size = ControlWindowSizing.size
        let window = ControlWindow()
        defer { window.close() }
        window.contentView = NSHostingView(
            rootView: SourcePanelBackground().frame(width: size.width, height: size.height)
        )
        window.contentView?.layoutSubtreeIfNeeded()

        #expect(window.canBecomeKey)
        #expect(window.canBecomeMain)
        #expect(!window.styleMask.contains(.titled))
        #expect(window.styleMask.contains(.closable))
        #expect(window.styleMask.contains(.miniaturizable))
        #expect(window.hasShadow)
        #expect(window.frame.size == size)
        #expect(window.contentView?.bounds.size == size)
        #expect(size.width == ControlWindowSizing.panelWidth)
        #expect(size.height == ControlWindowSizing.sourceRegionHeight + ControlWindowSizing.guidanceHeight)
        #expect(window.minSize == window.maxSize)
        #expect(window.responds(to: #selector(NSWindow.performClose(_:))))
    }

    @Test("The borderless controller supports native close and minimize commands")
    @MainActor
    func controllerWindowCommands() {
        let window = ControlWindow()
        window.orderFront(nil)
        let close = NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let minimize = NSMenuItem(
            title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        #expect(window.validateMenuItem(close))
        #expect(window.validateMenuItem(minimize))
        window.performClose(nil)
        #expect(!window.isVisible)
        #expect(!window.validateMenuItem(close))
        window.orderFront(nil)
        #expect(window.isVisible)
        window.close()
    }

    @Test("The native drag surface wins stage hit testing")
    @MainActor
    func dragSurfaceWinsStageHitTesting() async throws {
        let defaultsName = "StageInteractionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        let manager = CaptureManager(defaults: defaults)
        let hostingView = NSHostingView(
            rootView: StageView(manager: manager)
                .frame(width: 640, height: 360)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 360),
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.contentView?.layoutSubtreeIfNeeded()

        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }

        let frameView = try #require(window.contentView?.superview)
        let dragSurface = try #require(
            frameView.firstDescendant(ofType: WindowDragView.self)
        )
        let center = dragSurface.convert(
            NSPoint(x: dragSurface.bounds.midX, y: dragSurface.bounds.midY),
            to: frameView
        )

        #expect(window.titlebarSeparatorStyle == .none)
        #expect(dragSurface.bounds.width > 0)
        #expect(dragSurface.bounds.height > 0)
        #expect(frameView.hitTest(center) === dragSurface)
    }

    @Test("The controller footer routes pointer drags to its native window surface")
    @MainActor
    func controllerFooterDragSurface() async throws {
        let window = ControlWindow()
        defer { window.close() }
        let footer = SourceStatusFooter(
            guidance: SourceSelectionGuidance(
                state: .idle,
                selectedApplication: nil,
                pendingApplication: nil,
                suggestedApplication: nil,
                shortcut: nil
            )
        )
        let host = NSHostingView(rootView: footer.frame(width: ControlWindowSizing.panelWidth))
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        window.installDragSurface()
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        let frameView = try #require(host.superview)
        let surface = try #require(frameView.firstDescendant(ofType: WindowDragView.self))
        let center = surface.convert(NSPoint(x: surface.bounds.midX, y: surface.bounds.midY), to: frameView)
        #expect(surface.bounds.width == ControlWindowSizing.panelWidth)
        #expect(surface.bounds.height == ControlWindowSizing.guidanceHeight)
        #expect(frameView.hitTest(center) === surface)
    }
}

@MainActor
private func mouseEvent(
    type: NSEvent.EventType,
    location: NSPoint,
    in window: NSWindow
) throws -> NSEvent {
    try #require(
        NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        )
    )
}

@MainActor
private extension NSView {
    func firstDescendant<View: NSView>(ofType type: View.Type) -> View? {
        if let match = self as? View {
            return match
        }
        for subview in subviews {
            if let match = subview.firstDescendant(ofType: type) {
                return match
            }
        }
        return nil
    }
}
