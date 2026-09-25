import Testing
@testable import MeetStageCore

@Suite("Capture safety policy")
struct CaptureSafetyPolicyTests {
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

}
