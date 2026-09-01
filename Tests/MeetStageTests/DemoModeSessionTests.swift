import Foundation
import Testing
@testable import MeetStage

@Suite("Demo Mode presentation session")
struct DemoModeSessionTests {
    @Test("A transient caption returns to listening after its hold")
    @MainActor
    func revertsTransientCaption() async {
        let sleeper = ControlledDemoModeSleeper()
        let session = DemoModeSession(sleep: sleeper.sleep)

        session.setListening(true)
        session.setCaption(.highlighting("Receive"))

        await waitUntil { sleeper.nextDuration != nil }
        #expect(sleeper.nextDuration == .seconds(2.6))
        sleeper.resumeNext()

        await waitUntil { session.caption?.status == .listening }
        #expect(session.caption?.status == .listening)
    }

    @Test("A superseded caption cannot overwrite the newer status")
    @MainActor
    func cancelsSupersededCaptionRevert() async {
        let sleeper = ControlledDemoModeSleeper()
        let session = DemoModeSession(sleep: sleeper.sleep)

        session.setListening(true)
        session.setCaption(.highlighting("Receive"))
        await waitUntil { sleeper.pendingCount == 1 }

        session.setCaption(.clicking("Discover"))
        await waitUntil { sleeper.pendingCount == 2 }

        sleeper.resumeNext()
        await Task.yield()
        #expect(session.caption?.status == .clicking("Discover"))

        sleeper.resumeNext()
        await waitUntil { session.caption?.status == .listening }
        #expect(session.caption?.status == .listening)
    }

    @Test("Each highlight leaves after its own presentation duration")
    @MainActor
    func dismissesHighlight() async {
        let sleeper = ControlledDemoModeSleeper()
        let session = DemoModeSession(sleep: sleeper.sleep)
        let presentation = DemoHighlightPresentation(
            bounds: NormalizedAnnotationBounds(minX: 0.1, minY: 0.2, width: 0.3, height: 0.1),
            color: .blue,
            kind: .highlight
        )

        session.showHighlight(presentation)

        await waitUntil { sleeper.nextDuration != nil }
        #expect(sleeper.nextDuration == presentation.duration)
        sleeper.resumeNext()

        await waitUntil { session.highlights.isEmpty }
        #expect(session.highlights.isEmpty)
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

private final class ControlledDemoModeSleeper: @unchecked Sendable {
    private struct Request {
        let duration: Duration
        let continuation: CheckedContinuation<Void, any Error>
    }

    private let lock = NSLock()
    private var requests: [Request] = []

    var nextDuration: Duration? {
        lock.withLock { requests.first?.duration }
    }

    var pendingCount: Int {
        lock.withLock { requests.count }
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
