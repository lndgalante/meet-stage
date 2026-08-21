import AppKit
import SwiftUI
import Testing
@testable import MeetStage

@Suite("Annotations")
struct AnnotationTests {
    @Test("Normalizes canvas points and clamps pointer overshoot")
    func normalizesCanvasPoints() {
        #expect(
            AnnotationGeometry.normalizedPoint(
                for: CGPoint(x: 320, y: 90),
                in: CGSize(width: 640, height: 360)
            ) == NormalizedWindowPoint(x: 0.5, y: 0.25)
        )
        #expect(
            AnnotationGeometry.normalizedPoint(
                for: CGPoint(x: -20, y: 400),
                in: CGSize(width: 640, height: 360)
            ) == NormalizedWindowPoint(x: 0, y: 1)
        )
        #expect(
            AnnotationGeometry.normalizedPoint(
                for: .zero,
                in: .zero
            ) == nil
        )
    }

    @Test("Converts Quartz source bounds into AppKit overlay coordinates")
    func resolvesSourceOverlayFrame() {
        let frame = AnnotationGeometry.appKitOverlayFrame(
            sourceFrame: CGRect(x: 100, y: 200, width: 300, height: 200),
            primaryScreenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )

        #expect(frame == CGRect(x: 100, y: 500, width: 300, height: 200))
    }

    @Test("Selected-window drawing stays above its source and below the controller")
    @MainActor
    func configuresSourceDrawingWindow() {
        let panel = AnnotationPanel(
            contentRect: CGRect(x: 0, y: 0, width: 640, height: 360),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        AnnotationWindowPolicy.configure(panel)

        #expect(panel.level.rawValue > NSWindow.Level.normal.rawValue)
        #expect(panel.level.rawValue < NSWindow.Level.floating.rawValue)
        #expect(!panel.ignoresMouseEvents)
        #expect(panel.acceptsMouseMovedEvents)
        #expect(!panel.becomesKeyOnlyIfNeeded)
        #expect(panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
    }

    @Test("Source overlay waits for engagement before taking key focus")
    @MainActor
    func capturesSourcePointerDrag() async throws {
        let session = AnnotationSession(lifetimeSeconds: 10)
        let panel = AnnotationPanel(
            contentRect: CGRect(x: 0, y: 0, width: 640, height: 360),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        AnnotationWindowPolicy.configure(panel)
        panel.contentView = NSHostingView(
            rootView: SourceAnnotationSurface(
                session: session,
                onFinish: {}
            )
            .frame(width: 640, height: 360)
        )
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.orderFrontRegardless()
        #expect(!panel.isKeyWindow)
        // Window Server makes a non-activating panel key on the user's first
        // interaction. Synthetic events do not perform that transition.
        panel.makeKey()
        defer {
            session.clear()
            panel.close()
        }

        let mouseDown = try #require(
            pointerEvent(
                type: .leftMouseDown,
                at: CGPoint(x: 100, y: 100),
                in: panel,
                eventNumber: 1
            )
        )
        let mouseDragged = try #require(
            pointerEvent(
                type: .leftMouseDragged,
                at: CGPoint(x: 220, y: 180),
                in: panel,
                eventNumber: 2
            )
        )
        let mouseUp = try #require(
            pointerEvent(
                type: .leftMouseUp,
                at: CGPoint(x: 220, y: 180),
                in: panel,
                eventNumber: 3
            )
        )

        panel.sendEvent(mouseDown)
        panel.sendEvent(mouseDragged)
        panel.sendEvent(mouseUp)

        await waitUntil { !session.strokes.isEmpty }
        #expect(session.strokes.count == 1)
        #expect((session.strokes.first?.points.count ?? 0) >= 2)
    }

    @Test("Drops sub-pixel duplicate points")
    func coalescesDensePointerEvents() {
        let origin = NormalizedWindowPoint(x: 0.5, y: 0.5)

        #expect(
            !AnnotationGeometry.shouldAppend(
                NormalizedWindowPoint(x: 0.500_1, y: 0.500_1),
                after: origin
            )
        )
        #expect(
            AnnotationGeometry.shouldAppend(
                NormalizedWindowPoint(x: 0.51, y: 0.5),
                after: origin
            )
        )
    }

    @Test("Uses the nearest supported drawing lifetime")
    func normalizesLifetime() {
        #expect(AnnotationTiming.normalizedLifetimeSeconds(1) == 2)
        #expect(AnnotationTiming.normalizedLifetimeSeconds(5) == 4)
        #expect(AnnotationTiming.normalizedLifetimeSeconds(9) == 10)
    }

    @Test("Builds and clears a shared stroke session")
    @MainActor
    func managesStrokeSession() {
        let session = AnnotationSession(lifetimeSeconds: 6)
        let start = NormalizedWindowPoint(x: 0.1, y: 0.2)
        let end = NormalizedWindowPoint(x: 0.8, y: 0.9)

        let id = session.beginStroke(at: start)
        session.append(end, to: id)

        #expect(session.lifetimeSeconds == 6)
        #expect(
            session.strokes == [
                AnnotationStroke(
                    id: id,
                    points: [start, end],
                    color: .orange,
                    opacity: 1,
                    fadeDuration: AnnotationTiming.standardFadeDuration
                )
            ])

        session.clear()
        #expect(session.isEmpty)
    }

    @Test("Applies a changed pen color to new strokes")
    @MainActor
    func appliesChangedPenColor() {
        let session = AnnotationSession(inkColor: .orange)
        let orangeStrokeID = session.beginStroke(
            at: NormalizedWindowPoint(x: 0.1, y: 0.2)
        )

        session.setInkColor(.blue)
        let blueStrokeID = session.beginStroke(
            at: NormalizedWindowPoint(x: 0.3, y: 0.4)
        )

        #expect(session.strokes.first(where: { $0.id == orangeStrokeID })?.color == .orange)
        #expect(session.strokes.first(where: { $0.id == blueStrokeID })?.color == .blue)
    }

    @Test("Arms annotations without a live source")
    @MainActor
    func armsAnnotationsWhileIdle() throws {
        let suiteName = "AnnotationArmingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = CaptureManager(defaults: defaults)

        manager.toggleAnnotations()

        #expect(manager.annotationsEnabled)
        #expect(!manager.isAnnotating)

        manager.finishAnnotations()

        #expect(!manager.annotationsEnabled)
        #expect(!manager.isAnnotating)
    }

    @Test("Fades and removes each completed stroke independently")
    @MainActor
    func fadesCompletedStrokesIndependently() async {
        let sleeper = ControlledAnnotationSleeper()
        let session = AnnotationSession(
            lifetimeSeconds: 2,
            sleep: { duration in
                try await sleeper.sleep(for: duration)
            }
        )
        let fadingStrokeID = session.beginStroke(
            at: NormalizedWindowPoint(x: 0.1, y: 0.1)
        )
        session.endStroke(fadingStrokeID, reducesMotion: true)

        let activeStrokeID = session.beginStroke(
            at: NormalizedWindowPoint(x: 0.8, y: 0.8)
        )

        await waitUntil { sleeper.nextDuration != nil }
        #expect(sleeper.nextDuration == .seconds(2))
        sleeper.resumeNext()

        await waitUntil {
            session.strokes.first(where: { $0.id == fadingStrokeID })?.opacity == 0
        }
        await waitUntil { sleeper.nextDuration != nil }
        #expect(
            sleeper.nextDuration == .seconds(AnnotationTiming.reducedMotionFadeDuration)
        )
        #expect(session.strokes.first(where: { $0.id == activeStrokeID })?.opacity == 1)
        sleeper.resumeNext()

        await waitUntil {
            !session.strokes.contains(where: { $0.id == fadingStrokeID })
        }
        #expect(session.strokes.map(\.id) == [activeStrokeID])

        session.clear()
    }

    @MainActor
    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<1_000 {
            if condition() { return }
            await Task.yield()
        }
        #expect(condition())
    }

    @MainActor
    private func pointerEvent(
        type: NSEvent.EventType,
        at location: CGPoint,
        in window: NSWindow,
        eventNumber: Int
    ) -> NSEvent? {
        NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: [],
            timestamp: TimeInterval(eventNumber) / 100,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: eventNumber,
            clickCount: 1,
            pressure: type == .leftMouseUp ? 0 : 1
        )
    }
}

private final class ControlledAnnotationSleeper: @unchecked Sendable {
    private struct Request {
        let duration: Duration
        let continuation: CheckedContinuation<Void, any Error>
    }

    private let lock = NSLock()
    private var requests: [Request] = []

    var nextDuration: Duration? {
        lock.withLock { requests.first?.duration }
    }

    func sleep(for duration: Duration) async throws {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                requests.append(Request(duration: duration, continuation: continuation))
            }
        }
    }

    func resumeNext() {
        let continuation = lock.withLock {
            requests.isEmpty ? nil : requests.removeFirst().continuation
        }
        continuation?.resume()
    }
}
