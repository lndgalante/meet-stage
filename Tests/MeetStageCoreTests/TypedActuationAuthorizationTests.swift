import Testing
@testable import MeetStageCore

@Suite("Typed actuation authorization")
struct TypedActuationAuthorizationTests {
    @Test("Accepts only an explicit spoken payload")
    func acceptsExplicitPayload() {
        #expect(
            TypedActuationAuthorization.authorizedText(
                proposedText: "hello there",
                transcript: "Write hello there in the search field"
            ) == "hello there"
        )
        #expect(
            TypedActuationAuthorization.authorizedText(
                proposedText: "subtis.io",
                transcript: "Type subtis.io in the address field"
            ) == "subtis.io"
        )
    }

    @Test("Rejects mentions, negation, and model-only payloads")
    func rejectsUnsafePayloads() {
        #expect(
            TypedActuationAuthorization.authorizedText(
                proposedText: "secret",
                transcript: "Show the Search field"
            ) == nil
        )
        #expect(
            TypedActuationAuthorization.authorizedText(
                proposedText: "secret",
                transcript: "Don't type secret in Search"
            ) == nil
        )
        #expect(
            TypedActuationAuthorization.authorizedText(
                proposedText: "search",
                transcript: "Type in the Search field"
            ) == nil
        )
        #expect(
            TypedActuationAuthorization.authorizedText(
                proposedText: "different text",
                transcript: "Type hello in Search"
            ) == nil
        )
        #expect(
            TypedActuationAuthorization.authorizedText(
                proposedText: "rm -rf",
                transcript: "Type rm rf in Terminal"
            ) == nil
        )
        #expect(
            TypedActuationAuthorization.authorizedText(
                proposedText: "hello in the search",
                transcript: "Type hello in the Search field"
            ) == nil
        )
    }
}
