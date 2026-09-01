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
struct DemoBrainDecodingTests {
    @Test("Parses an element-id click decision from noisy model text")
    func parsesElementIdClick() throws {
        let text = "Sure! {\"action\":\"click\",\"element_id\":3,\"point\":null,\"label\":\"Discover\"}"
        let decision = try #require(
            DemoBrainDecoding.parse(from: text, allowsClicking: true)
        )
        #expect(decision.action == .click)
        #expect(decision.elementID == 3)
        #expect(decision.label == "Discover")
    }

    @Test("Parses a coordinate fallback decision")
    func parsesPointFallback() throws {
        let text = "{\"action\":\"highlight\",\"element_id\":null,\"point\":[120,44],\"label\":\"sync\"}"
        let decision = try #require(
            DemoBrainDecoding.parse(from: text, allowsClicking: true)
        )
        #expect(decision.action == .highlight)
        #expect(decision.elementID == nil)
        #expect(decision.point == CGPoint(x: 120, y: 44))
    }

    @Test("Downgrades a click to a highlight when clicking is disabled")
    func downgradesClickWhenDisabled() throws {
        let text = "{\"action\":\"click\",\"element_id\":1,\"point\":null,\"label\":\"Send\"}"
        let decision = try #require(
            DemoBrainDecoding.parse(from: text, allowsClicking: false)
        )
        #expect(decision.action == .highlight)
    }

    @Test("Returns nil for a none action or ungrounded decision")
    func rejectsUngrounded() {
        #expect(
            DemoBrainDecoding.parse(
                from: "{\"action\":\"none\",\"element_id\":null,\"point\":null,\"label\":\"\"}",
                allowsClicking: true
            ) == nil
        )
        #expect(
            DemoBrainDecoding.parse(
                from: "{\"action\":\"click\",\"element_id\":null,\"point\":null,\"label\":\"x\"}",
                allowsClicking: true
            ) == nil
        )
        #expect(DemoBrainDecoding.parse(from: "no json here", allowsClicking: true) == nil)
    }

    @Test("Parses a type decision with text")
    func parsesType() throws {
        let text =
            "{\"action\":\"type\",\"element_id\":2,\"point\":null,\"text\":\"subtis.io\",\"label\":\"Search\"}"
        let decision = try #require(
            DemoBrainDecoding.parse(from: text, allowsClicking: true)
        )
        #expect(decision.action == .type)
        #expect(decision.text == "subtis.io")
    }

    @Test("A type without text is rejected")
    func rejectsTypeWithoutText() {
        #expect(
            DemoBrainDecoding.parse(
                from: "{\"action\":\"type\",\"element_id\":2,\"point\":null,\"text\":null,\"label\":\"Search\"}",
                allowsClicking: true
            ) == nil
        )
    }

    @Test("A type downgrades to highlight when clicking is disabled")
    func typeDowngradesWhenDisabled() throws {
        let text =
            "{\"action\":\"type\",\"element_id\":2,\"point\":null,\"text\":\"hi\",\"label\":\"Search\"}"
        let decision = try #require(
            DemoBrainDecoding.parse(from: text, allowsClicking: false)
        )
        #expect(decision.action == .highlight)
    }

    @Test("Typed text is capped to the max length")
    func capsTypedText() throws {
        let long = String(repeating: "a", count: 500)
        let text =
            "{\"action\":\"type\",\"element_id\":2,\"point\":null,\"text\":\"\(long)\",\"label\":\"F\"}"
        let decision = try #require(
            DemoBrainDecoding.parse(from: text, allowsClicking: true)
        )
        #expect(decision.text?.count == DemoBrainDecoding.maxTypeLength)
    }

    @Test("Parses the effect actions (circle, spotlight, zoom)")
    func parsesEffectActions() throws {
        for (raw, expected) in [
            ("circle", DemoBrainAction.circle),
            ("spotlight", .spotlight),
            ("zoom", .zoom)
        ] {
            let text = "{\"action\":\"\(raw)\",\"element_id\":5,\"point\":null,\"label\":\"X\"}"
            let decision = try #require(
                DemoBrainDecoding.parse(from: text, allowsClicking: true)
            )
            #expect(decision.action == expected)
        }
    }

    @Test("Handles a code-fenced JSON reply")
    func parsesCodeFence() throws {
        let text = "```json\n{\"action\":\"click\",\"element_id\":1,\"point\":null,\"label\":\"Go\"}\n```"
        let decision = try #require(
            DemoBrainDecoding.parse(from: text, allowsClicking: true)
        )
        #expect(decision.action == .click)
        #expect(decision.elementID == 1)
    }
}

@Suite("Demo Mode brain errors")
struct DemoBrainErrorTests {
    @Test("A 401 is a persistent key error")
    func authIsPersistent() {
        let error = DemoBrainError.http(status: 401, detail: "")
        #expect(error.isPersistent)
        #expect(error.userMessage == "Check your API key")
    }

    @Test("A 429 is a transient rate-limit error")
    func rateLimitIsTransient() {
        let error = DemoBrainError.http(status: 429, detail: "")
        #expect(!error.isPersistent)
        #expect(error.userMessage.contains("Rate limited"))
    }

    @Test("Transport failures are transient")
    func transportIsTransient() {
        #expect(!DemoBrainError.transport("offline").isPersistent)
    }
}

@Suite("Demo Mode gate covers every action")
struct DemoCommandGateActionTests {
    @Test("A repeated type is debounced but a different action on the same label fires")
    func debouncesPerAction() {
        var gate = DemoCommandGate()
        let first = gate.admit(label: "Search", action: "type", at: 0)
        let dupe = gate.admit(label: "Search", action: "type", at: 0.5)
        let otherAction = gate.admit(label: "Search", action: "circle", at: 0.5)
        let afterCooldown = gate.admit(label: "Search", action: "type", at: 3)

        #expect(first)
        #expect(!dupe)
        #expect(otherAction)
        #expect(afterCooldown)
    }
}
