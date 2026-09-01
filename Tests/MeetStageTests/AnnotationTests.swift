import AppKit
import SwiftUI
import Testing
@testable import MeetStage

@Suite("Annotations")
struct AnnotationTests {
    @Test("Normalizes extreme persisted lifetimes without integer overflow")
    func normalizesExtremeLifetimeValues() {
        #expect(AnnotationTiming.normalizedLifetimeSeconds(.min) == 2)
        #expect(AnnotationTiming.normalizedLifetimeSeconds(.max) == 10)
    }

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

    @Test("Drawn annotations participate in Undo and Redo")
    @MainActor
    func undoesAndRedoesDrawnStroke() {
        let session = AnnotationSession(lifetimeSeconds: 10)
        let undoManager = UndoManager()
        var inputController = AnnotationInputController()

        inputController.update(
            location: CGPoint(x: 40, y: 40),
            canvasSize: CGSize(width: 200, height: 100),
            session: session
        )
        inputController.update(
            location: CGPoint(x: 120, y: 70),
            canvasSize: CGSize(width: 200, height: 100),
            session: session
        )
        inputController.finish(
            session: session,
            reducesMotion: false,
            undoManager: undoManager
        )

        #expect(session.strokes.count == 1)
        undoManager.undo()
        #expect(session.strokes.isEmpty)
        undoManager.redo()
        #expect(session.strokes.count == 1)
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

    @Test("Snaps a rough closed circle to a true circle")
    @MainActor
    func recognizesRoughCircle() throws {
        let canvasSize = CGSize(width: 640, height: 480)
        let pixelPoints = (0...48).map { index in
            let angle = CGFloat(index) / 48 * 2 * .pi
            let radius = 96 * (1 + 0.055 * sin(angle * 3) + 0.025 * cos(angle * 5))
            return CGPoint(
                x: 330 + cos(angle) * radius,
                y: 235 + sin(angle) * radius
            )
        }
        let points = normalized(pixelPoints, in: canvasSize)
        let session = AnnotationSession(lifetimeSeconds: 10)
        let id = session.beginStroke(at: try #require(points.first))
        points.dropFirst().forEach { session.append($0, to: id) }

        session.endStroke(id, canvasSize: canvasSize, reducesMotion: false)

        let stroke = try #require(session.strokes.first)
        guard case .circle(let center, let diameter) = stroke.geometry else {
            Issue.record("Expected the rough stroke to become a circle")
            return
        }
        #expect(abs(center.x * canvasSize.width - 330) < 8)
        #expect(abs(center.y * canvasSize.height - 235) < 8)
        #expect(abs(diameter * min(canvasSize.width, canvasSize.height) - 192) < 16)
        session.clear()
    }

    @Test("Snaps a rough four-sided stroke to an axis-aligned rectangle")
    @MainActor
    func recognizesRoughRectangle() throws {
        let canvasSize = CGSize(width: 640, height: 480)
        var pixelPoints: [CGPoint] = []
        for index in 0...12 {
            let progress = CGFloat(index) / 12
            pixelPoints.append(
                CGPoint(x: 145 + 285 * progress, y: 105 + 3 * sin(progress * .pi))
            )
        }
        for index in 1...8 {
            let progress = CGFloat(index) / 8
            pixelPoints.append(
                CGPoint(x: 430 + 3 * sin(progress * .pi), y: 105 + 155 * progress)
            )
        }
        for index in 1...12 {
            let progress = CGFloat(index) / 12
            pixelPoints.append(
                CGPoint(x: 430 - 285 * progress, y: 260 - 4 * sin(progress * .pi))
            )
        }
        for index in 1...8 {
            let progress = CGFloat(index) / 8
            pixelPoints.append(
                CGPoint(x: 145 - 2 * sin(progress * .pi), y: 260 - 153 * progress)
            )
        }

        let points = normalized(pixelPoints, in: canvasSize)
        let session = AnnotationSession(lifetimeSeconds: 10)
        let id = session.beginStroke(at: try #require(points.first))
        points.dropFirst().forEach { session.append($0, to: id) }

        session.endStroke(id, canvasSize: canvasSize, reducesMotion: false)

        let stroke = try #require(session.strokes.first)
        guard case .rectangle(let bounds) = stroke.geometry else {
            Issue.record("Expected the rough stroke to become a rectangle")
            return
        }
        #expect(abs(bounds.minX * canvasSize.width - 145) < 6)
        #expect(abs(bounds.minY * canvasSize.height - 105) < 6)
        #expect(abs(bounds.width * canvasSize.width - 285) < 10)
        #expect(abs(bounds.height * canvasSize.height - 155) < 10)
        session.clear()
    }

    @Test("Snaps a closed trapezoidal outline to a rectangle")
    func recognizesLooseFourSidedRectangle() throws {
        let canvasSize = CGSize(width: 800, height: 500)
        let corners = [
            CGPoint(x: 190, y: 100),
            CGPoint(x: 530, y: 105),
            CGPoint(x: 445, y: 315),
            CGPoint(x: 160, y: 300),
            CGPoint(x: 188, y: 104)
        ]
        var pixelPoints: [CGPoint] = []
        for pair in zip(corners, corners.dropFirst()) {
            for index in 0..<12 {
                let progress = CGFloat(index) / 12
                let wobble = sin(progress * .pi) * 3
                pixelPoints.append(
                    CGPoint(
                        x: pair.0.x + (pair.1.x - pair.0.x) * progress + wobble,
                        y: pair.0.y + (pair.1.y - pair.0.y) * progress - wobble
                    )
                )
            }
        }
        pixelPoints.append(try #require(corners.last))

        let geometry = AnnotationShapeRecognizer.recognize(
            points: normalized(pixelPoints, in: canvasSize),
            in: canvasSize
        )

        guard case .rectangle(let bounds) = geometry else {
            Issue.record("Expected the loose four-sided outline to become a rectangle")
            return
        }
        #expect(abs(bounds.width * canvasSize.width - 370) < 12)
        #expect(abs(bounds.height * canvasSize.height - 215) < 12)
    }

    @Test("Keeps an open curved stroke as freehand ink")
    func preservesOpenFreehandStroke() {
        let canvasSize = CGSize(width: 640, height: 480)
        let pixelPoints = (0...32).map { index in
            let angle = CGFloat(index) / 32 * 1.55 * .pi
            return CGPoint(
                x: 320 + cos(angle) * 100,
                y: 240 + sin(angle) * 100
            )
        }

        #expect(
            AnnotationShapeRecognizer.recognize(
                points: normalized(pixelPoints, in: canvasSize),
                in: canvasSize
            ) == nil
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

    private func normalized(
        _ points: [CGPoint],
        in canvasSize: CGSize
    ) -> [NormalizedWindowPoint] {
        points.map {
            NormalizedWindowPoint(
                x: $0.x / canvasSize.width,
                y: $0.y / canvasSize.height
            )
        }
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
