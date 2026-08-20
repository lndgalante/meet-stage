import Testing
@testable import MeetStage

@Suite("Capture selection policy")
struct CaptureSelectionPolicyTests {
    @Test("Repeating the live source pauses sharing")
    func repeatLiveSourcePauses() {
        #expect(
            CaptureSelectionPolicy.action(
                for: 4,
                selectedWindowID: 4,
                state: .capturing
            ) == .pause
        )
    }

    @Test("Repeating a paused source resumes sharing")
    func repeatPausedSourceStarts() {
        #expect(
            CaptureSelectionPolicy.action(
                for: 4,
                selectedWindowID: 4,
                state: .paused
            ) == .start
        )
    }

    @Test("Selecting another live source switches directly")
    func differentLiveSourceStarts() {
        #expect(
            CaptureSelectionPolicy.action(
                for: 5,
                selectedWindowID: 4,
                state: .capturing
            ) == .start
        )
    }
}
