import Testing
@testable import MeetStage

@Suite("Demo Mode text matching")
struct DemoTextMatchingTests {
    @Test("Transcript tokenization strips punctuation and keeps spoken words")
    func tokenizesTranscript() {
        let tokenized = DemoText.tokenizeTranscript("If we click the Discover button!")

        #expect(tokenized.tokens == ["if", "we", "click", "the", "discover", "button"])
        #expect(tokenized.words == ["If", "we", "click", "the", "Discover", "button"])
    }

    @Test("Spoken and written numbers normalize to the same token")
    func normalizesNumbers() {
        #expect(DemoText.normalize("2") == "two")
        #expect(DemoText.normalize("Two") == "two")
        #expect(DemoText.normalize("HYPE") == "hype")
    }

    @Test("Labels split camelCase, snake_case, and acronym boundaries")
    func splitsLabelIdentifiers() {
        #expect(DemoText.tokenizeLabel("SignIn") == ["sign", "in"])
        #expect(DemoText.tokenizeLabel("trade_with_leverage") == ["trade", "with", "leverage"])
        #expect(DemoText.tokenizeLabel("USBPort") == ["usb", "port"])
        #expect(DemoText.tokenizeLabel("View quotes") == ["view", "quotes"])
    }

    @Test("Similarity scores exact matches highest and unrelated words low")
    func scoresSimilarity() {
        #expect(DemoSimilarity.score("discover", "discover") == 1)
        #expect(DemoSimilarity.score("discover", "discovr") > 0.9)
        #expect(DemoSimilarity.score("discover", "banana") < 0.6)
    }

    @Test("Label matcher finds the best contiguous window in a transcript")
    func matchesLabelWindow() {
        let match = DemoLabelMatcher.bestMatch(
            labelTokens: ["view", "quotes"],
            transcriptTokens: ["please", "click", "view", "quotes", "now"]
        )

        #expect(match?.tokenRange == 2..<4)
        #expect(match?.score == 1)
    }

    @Test("Label matcher rejects windows below the per-token floor")
    func rejectsWeakWindows() {
        let match = DemoLabelMatcher.bestMatch(
            labelTokens: ["discover"],
            transcriptTokens: ["the", "banana", "stand"]
        )

        #expect(match == nil)
    }
}
