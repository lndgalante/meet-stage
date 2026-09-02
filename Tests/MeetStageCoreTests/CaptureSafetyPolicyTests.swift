import Testing
@testable import MeetStageCore

@Suite("Capture safety policy")
struct CaptureSafetyPolicyTests {
    private let source = CaptureWindowBounds(x: 100, y: 200, width: 800, height: 600)

    @Test("Selects one close Accessibility window")
    func selectsUniqueWindow() {
        let candidates = [
            CaptureWindowBounds(x: 0, y: 0, width: 200, height: 100),
            CaptureWindowBounds(x: 101, y: 199, width: 800, height: 600)
        ]

        #expect(ExactWindowFocusPolicy.uniqueBestMatch(source: source, candidates: candidates) == 1)
    }

    @Test("Rejects missing, distant, invalid, and ambiguous matches")
    func rejectsUnsafeWindowMatches() {
        #expect(ExactWindowFocusPolicy.uniqueBestMatch(source: source, candidates: []) == nil)
        #expect(
            ExactWindowFocusPolicy.uniqueBestMatch(
                source: source,
                candidates: [CaptureWindowBounds(x: 120, y: 200, width: 800, height: 600)]
            ) == nil
        )
        #expect(
            ExactWindowFocusPolicy.uniqueBestMatch(
                source: CaptureWindowBounds(x: .nan, y: 0, width: 1, height: 1),
                candidates: [source]
            ) == nil
        )
        #expect(
            ExactWindowFocusPolicy.uniqueBestMatch(
                source: source,
                candidates: [source, source]
            ) == nil
        )
    }

    @Test("Actuation requires one live focused window owned by the source process")
    func requiresExactFocusedWindow() {
        #expect(
            ExactWindowFocusPolicy.allowsActuation(
                sourcePID: 42,
                frontmostPID: 42,
                windowOwnerPID: 42,
                windowIsOnScreen: true,
                matchingWindowIndex: 1,
                focusedWindowIndex: 1
            )
        )

        for unsafeSnapshot in unsafeFocusSnapshots {
            #expect(!unsafeSnapshot())
        }
    }

    @Test("Only the expected render generation confirms a source")
    func rejectsStaleCaptureFrames() {
        #expect(
            CaptureFrameAcceptancePolicy.confirmsSelection(
                expectedGeneration: 8,
                frameGeneration: 8
            )
        )
        #expect(
            !CaptureFrameAcceptancePolicy.confirmsSelection(
                expectedGeneration: 8,
                frameGeneration: 7
            )
        )
        #expect(
            !CaptureFrameAcceptancePolicy.confirmsSelection(
                expectedGeneration: nil,
                frameGeneration: 8
            )
        )
    }

    private var unsafeFocusSnapshots: [() -> Bool] {
        [
            {
                ExactWindowFocusPolicy.allowsActuation(
                    sourcePID: 0, frontmostPID: 0, windowOwnerPID: 0, windowIsOnScreen: true, matchingWindowIndex: 0,
                    focusedWindowIndex: 0)
            },
            {
                ExactWindowFocusPolicy.allowsActuation(
                    sourcePID: 42, frontmostPID: 7, windowOwnerPID: 42, windowIsOnScreen: true, matchingWindowIndex: 0,
                    focusedWindowIndex: 0)
            },
            {
                ExactWindowFocusPolicy.allowsActuation(
                    sourcePID: 42, frontmostPID: 42, windowOwnerPID: 7, windowIsOnScreen: true, matchingWindowIndex: 0,
                    focusedWindowIndex: 0)
            },
            {
                ExactWindowFocusPolicy.allowsActuation(
                    sourcePID: 42, frontmostPID: 42, windowOwnerPID: 42, windowIsOnScreen: false,
                    matchingWindowIndex: 0, focusedWindowIndex: 0)
            },
            {
                ExactWindowFocusPolicy.allowsActuation(
                    sourcePID: 42, frontmostPID: 42, windowOwnerPID: 42, windowIsOnScreen: true,
                    matchingWindowIndex: nil, focusedWindowIndex: 0)
            },
            {
                ExactWindowFocusPolicy.allowsActuation(
                    sourcePID: 42, frontmostPID: 42, windowOwnerPID: 42, windowIsOnScreen: true, matchingWindowIndex: 0,
                    focusedWindowIndex: 1)
            }
        ]
    }
}
