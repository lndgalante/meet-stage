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

    @Test("The bottom grabber owns its complete visible hit region")
    @MainActor
    func bottomGrabberWinsHitTesting() {
        let hostingView = NSHostingView(
            rootView: BottomDragHandle()
        )
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: ControlWindowSizing.dragHandleHitWidth,
                height: ControlWindowSizing.dragHandleAreaHeight
            ),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.contentView?.layoutSubtreeIfNeeded()

        #expect(hostingView.bounds.width == ControlWindowSizing.dragHandleHitWidth)
        #expect(hostingView.bounds.height == ControlWindowSizing.dragHandleAreaHeight)
        #expect(hostingView.hitTest(NSPoint(x: 1, y: 1)) != nil)
        #expect(
            hostingView.hitTest(
                NSPoint(x: hostingView.bounds.midX, y: hostingView.bounds.midY)
            ) != nil
        )
        #expect(
            hostingView.hitTest(
                NSPoint(x: hostingView.bounds.maxX - 1, y: hostingView.bounds.maxY - 1)
            ) != nil
        )
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
