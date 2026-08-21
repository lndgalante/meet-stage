import AppKit
import SwiftUI
import Testing
@testable import MeetStage

@Suite("Stage interaction")
struct StageInteractionTests {
    @Test("The topmost stage surface starts a native window drag")
    @MainActor
    func renderingSurfaceStartsWindowDrag() throws {
        let window = DragTrackingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 360),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        let surface = WindowDragView(frame: window.contentView?.bounds ?? .zero)
        window.contentView = surface

        let event = try #require(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: NSPoint(x: 320, y: 180),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            )
        )

        surface.mouseDown(with: event)

        #expect(surface.mouseDownCanMoveWindow)
        #expect(window.didPerformDrag)
    }

    @Test("A SwiftUI drag handle keeps the native drag surface interactive")
    @MainActor
    func swiftUIDragHandleWinsHitTesting() throws {
        let hostingView = NSHostingView(
            rootView: WindowDragSurface()
                .frame(width: ControlWindowSizing.dragHandleWidth, height: 44)
        )
        let window = DragTrackingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 44),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.contentView?.layoutSubtreeIfNeeded()

        let dragSurface = try #require(
            hostingView.firstDescendant(ofType: WindowDragView.self)
        )
        let center = dragSurface.convert(
            NSPoint(x: dragSurface.bounds.midX, y: dragSurface.bounds.midY),
            to: hostingView
        )

        #expect(dragSurface.bounds.width == ControlWindowSizing.dragHandleWidth)
        #expect(dragSurface.bounds.height == 44)
        #expect(hostingView.hitTest(center) === dragSurface)
    }

    @Test("The stage keeps standard macOS window semantics")
    @MainActor
    func stageUsesStandardWindowStyle() {
        #expect(WindowConfigurator.stageStyleMask.contains(.titled))
        #expect(WindowConfigurator.stageStyleMask.contains(.resizable))
        #expect(WindowConfigurator.stageStyleMask.contains(.fullSizeContentView))
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
}

@MainActor
private final class DragTrackingWindow: NSWindow {
    private(set) var didPerformDrag = false

    override func performDrag(with event: NSEvent) {
        didPerformDrag = true
    }
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
