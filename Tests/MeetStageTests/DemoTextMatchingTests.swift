import CoreGraphics
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

@Suite("Demo Mode brain parsing")
struct ClaudeDemoBrainParsingTests {
    @Test("Parses an element-id click decision from noisy model text")
    func parsesElementIdClick() throws {
        let text = "Sure! {\"action\":\"click\",\"element_id\":3,\"point\":null,\"label\":\"Discover\"}"
        let decision = try #require(
            ClaudeDemoBrain.parseDecision(from: text, allowsClicking: true)
        )
        #expect(decision.action == .click)
        #expect(decision.elementID == 3)
        #expect(decision.label == "Discover")
    }

    @Test("Parses a coordinate fallback decision")
    func parsesPointFallback() throws {
        let text = "{\"action\":\"highlight\",\"element_id\":null,\"point\":[120,44],\"label\":\"sync\"}"
        let decision = try #require(
            ClaudeDemoBrain.parseDecision(from: text, allowsClicking: true)
        )
        #expect(decision.action == .highlight)
        #expect(decision.elementID == nil)
        #expect(decision.point == CGPoint(x: 120, y: 44))
    }

    @Test("Downgrades a click to a highlight when clicking is disabled")
    func downgradesClickWhenDisabled() throws {
        let text = "{\"action\":\"click\",\"element_id\":1,\"point\":null,\"label\":\"Send\"}"
        let decision = try #require(
            ClaudeDemoBrain.parseDecision(from: text, allowsClicking: false)
        )
        #expect(decision.action == .highlight)
    }

    @Test("Returns nil for a none action or ungrounded decision")
    func rejectsUngrounded() {
        #expect(
            ClaudeDemoBrain.parseDecision(
                from: "{\"action\":\"none\",\"element_id\":null,\"point\":null,\"label\":\"\"}",
                allowsClicking: true
            ) == nil
        )
        #expect(
            ClaudeDemoBrain.parseDecision(
                from: "{\"action\":\"click\",\"element_id\":null,\"point\":null,\"label\":\"x\"}",
                allowsClicking: true
            ) == nil
        )
        #expect(ClaudeDemoBrain.parseDecision(from: "no json here", allowsClicking: true) == nil)
    }
}
