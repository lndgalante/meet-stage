import AppKit
import SwiftUI
import Testing
@testable import MeetStage

@Suite("Annotations")
struct AnnotationTests {
    @Test("Normalizes canvas points and clamps pointer overshoot")
    func normalizesCanvasPoints() {
        #expect(
            WindowCoordinateGeometry.normalizedPoint(
                clamping: CGPoint(x: 320, y: 90),
                in: CGSize(width: 640, height: 360)
            ) == NormalizedWindowPoint(x: 0.5, y: 0.25)
        )
        #expect(
            WindowCoordinateGeometry.normalizedPoint(
                clamping: CGPoint(x: -20, y: 400),
                in: CGSize(width: 640, height: 360)
            ) == NormalizedWindowPoint(x: 0, y: 1)
        )
        #expect(
            WindowCoordinateGeometry.normalizedPoint(
                clamping: .zero,
                in: .zero
            ) == nil
        )
    }

    @Test("Converts Quartz source bounds into AppKit overlay coordinates")
    func resolvesSourceOverlayFrame() {
        let frame = SourceOverlayGeometry.appKitFrame(
            forQuartzFrame: CGRect(x: 100, y: 200, width: 300, height: 200),
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
        panel.orderFrontRegardless()
        defer { panel.close() }

        #expect(panel.level.rawValue > NSWindow.Level.normal.rawValue)
        #expect(panel.level.rawValue < NSWindow.Level.floating.rawValue)
        #expect(!panel.ignoresMouseEvents)
        #expect(panel.acceptsMouseMovedEvents)
        #expect(!panel.becomesKeyOnlyIfNeeded)
        #expect(panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(!panel.isKeyWindow)
    }

    @Test("Source pointer drags create one normalized stroke")
    @MainActor
    func capturesSourcePointerDrag() {
        let session = AnnotationSession(lifetimeSeconds: 10)
        var inputController = AnnotationInputController()
        let canvasSize = CGSize(width: 640, height: 360)

        inputController.update(
            location: CGPoint(x: 100, y: 100),
            canvasSize: canvasSize,
            session: session
        )
        inputController.update(
            location: CGPoint(x: 220, y: 180),
            canvasSize: canvasSize,
            session: session
        )
        inputController.finish(
            session: session,
            reducesMotion: false
        )

        #expect(session.strokes.count == 1)
        #expect(
            session.strokes.first?.points == [
                NormalizedWindowPoint(x: 0.156_25, y: 0.277_777_777_777_777_8),
                NormalizedWindowPoint(x: 0.343_75, y: 0.5)
            ]
        )
        #expect(inputController.activeStrokeID == nil)

        session.clear()
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
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(condition())
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
