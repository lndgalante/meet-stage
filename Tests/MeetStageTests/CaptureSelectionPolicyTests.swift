import Testing
@testable import MeetStage

@Suite("Capture selection policy")
struct CaptureSelectionPolicyTests {
    @Test("Repeating the live source keeps the stage running")
    func repeatLiveSourceKeepsCurrent() {
        #expect(
            CaptureSelectionPolicy.action(
                for: 4,
                selectedWindowID: 4,
                state: .capturing
            ) == .keepCurrent
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

    @Test("An unavailable switch restores the previous live source")
    func unavailableSwitchRestoresPreviousSource() {
        #expect(
            UnavailableSelectionRecoveryPolicy.action(
                failedSourceID: 5,
                selectedWindowID: 4,
                availableWindowIDs: [4, 6]
            ) == .restore(4)
        )
    }

    @Test("An unavailable first or repeated selection fails safely")
    func unavailableSelectionWithoutFallbackFails() {
        #expect(
            UnavailableSelectionRecoveryPolicy.action(
                failedSourceID: 5,
                selectedWindowID: nil,
                availableWindowIDs: [6]
            ) == .fail
        )
        #expect(
            UnavailableSelectionRecoveryPolicy.action(
                failedSourceID: 5,
                selectedWindowID: 5,
                availableWindowIDs: [5, 6]
            ) == .fail
        )
    }
}
