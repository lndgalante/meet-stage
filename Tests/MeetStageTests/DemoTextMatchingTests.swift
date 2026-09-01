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

    @Test("Rejects ambiguous, negative, or malformed grounding")
    func rejectsMalformedGrounding() {
        let invalidDecisions = [
            #"{"action":"click","element_id":1,"point":[10,20],"label":"Send"}"#,
            #"{"action":"click","element_id":-1,"point":null,"label":"Send"}"#,
            #"{"action":"click","element_id":null,"point":[10],"label":"Send"}"#,
            #"{"action":"click","element_id":null,"point":[-1,20],"label":"Send"}"#
        ]

        for text in invalidDecisions {
            #expect(DemoBrainDecoding.parse(from: text, allowsClicking: true) == nil)
        }
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

    @Test("Typed text cannot contain synthesized control keys")
    func sanitizesTypedControlCharacters() throws {
        let text =
            #"{"action":"type","element_id":2,"point":null,"text":"hello\nworld\t\u001B!","label":"Search"}"#
        let decision = try #require(
            DemoBrainDecoding.parse(from: text, allowsClicking: true)
        )

        #expect(decision.text == "hello world !")
        #expect(
            DemoBrainDecoding.parse(
                from:
                    #"{"action":"type","element_id":2,"point":null,"text":"\n\t\u001B","label":"Search"}"#,
                allowsClicking: true
            ) == nil
        )
    }

    @Test("Coordinate fallbacks must remain inside the captured image")
    func validatesCoordinateBounds() {
        let valid = DemoBrainDecision(
            action: .highlight,
            elementID: nil,
            point: CGPoint(x: 50, y: 25),
            label: "Send",
            text: nil
        )
        let outOfBounds = DemoBrainDecision(
            action: .highlight,
            elementID: nil,
            point: CGPoint(x: 101, y: 25),
            label: "Send",
            text: nil
        )

        #expect(valid.normalizedPoint(in: CGSize(width: 100, height: 50)) == CGPoint(x: 0.5, y: 0.5))
        #expect(valid.normalizedPoint(in: .zero) == nil)
        #expect(outOfBounds.normalizedPoint(in: CGSize(width: 100, height: 50)) == nil)
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

    @Test("Handles braces and escaped quotes inside JSON strings")
    func parsesBracesInsideStrings() throws {
        let text =
            #"{"action":"type","element_id":2,"point":null,"text":"Use {account} and \"confirm\"","label":"Search"}"#
        let decision = try #require(
            DemoBrainDecoding.parse(from: text, allowsClicking: true)
        )

        #expect(decision.action == .type)
        #expect(decision.text == #"Use {account} and "confirm""#)
    }

    @Test("Skips an unrelated object before the decision")
    func skipsUnrelatedObject() throws {
        let text =
            #"metadata {"latency":120} answer {"action":"click","element_id":4,"point":null,"text":null,"label":"Continue"}"#
        let decision = try #require(
            DemoBrainDecoding.parse(from: text, allowsClicking: true)
        )

        #expect(decision.action == .click)
        #expect(decision.elementID == 4)
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

@Suite("Demo Mode cloud request policy")
struct DemoCloudRequestContextTests {
    private let context = DemoCloudRequestContext(provider: .openai, windowID: 42)

    @Test("Allows only the unchanged, explicitly consented source and provider")
    func requiresUnchangedAuthorization() {
        #expect(
            context.remainsAuthorized(
                isDemoModeEnabled: true,
                isLive: true,
                isSourceFocused: true,
                hasCloudConsent: true,
                selectedProvider: .openai,
                selectedWindowID: 42
            )
        )

        #expect(
            !context.remainsAuthorized(
                isDemoModeEnabled: true,
                isLive: true,
                isSourceFocused: true,
                hasCloudConsent: false,
                selectedProvider: .openai,
                selectedWindowID: 42
            )
        )
        #expect(
            !context.remainsAuthorized(
                isDemoModeEnabled: true,
                isLive: true,
                isSourceFocused: true,
                hasCloudConsent: true,
                selectedProvider: .claude,
                selectedWindowID: 42
            )
        )
        #expect(
            !context.remainsAuthorized(
                isDemoModeEnabled: true,
                isLive: true,
                isSourceFocused: true,
                hasCloudConsent: true,
                selectedProvider: .openai,
                selectedWindowID: 99
            )
        )
        #expect(
            !context.remainsAuthorized(
                isDemoModeEnabled: true,
                isLive: true,
                isSourceFocused: false,
                hasCloudConsent: true,
                selectedProvider: .openai,
                selectedWindowID: 42
            )
        )
    }
}

@Suite("Demo Mode conversation")
struct DemoConversationTests {
    @Test("Keeps a bounded rolling history and resets it")
    func boundsAndResetsHistory() {
        var conversation = DemoConversation()
        for index in 0...DemoConversation.maxTurns {
            conversation.record(user: "user-\(index)", assistant: "assistant-\(index)")
        }

        #expect(conversation.turns.count == DemoConversation.maxTurns)
        #expect(conversation.turns.first?.user == "user-1")
        #expect(
            conversation.turns.last?.assistant
                == "assistant-\(DemoConversation.maxTurns)"
        )

        conversation.reset()
        #expect(conversation.turns.isEmpty)
    }
}

@Suite("Demo Mode brain request gate")
struct DemoBrainRequestGateTests {
    @Test("Debounces only the same transcript, provider, and source")
    func scopesDuplicatesToProviderAndSource() {
        var gate = DemoBrainRequestGate()

        let first = gate.admit(transcript: "open it", provider: .claude, windowID: 1, at: 0)
        let duplicate = gate.admit(
            transcript: "open it",
            provider: .claude,
            windowID: 1,
            at: 1
        )
        let differentProvider = gate.admit(
            transcript: "open it",
            provider: .openai,
            windowID: 1,
            at: 1
        )
        let differentSource = gate.admit(
            transcript: "open it",
            provider: .openai,
            windowID: 2,
            at: 1
        )
        let afterCooldown = gate.admit(
            transcript: "open it",
            provider: .openai,
            windowID: 2,
            at: 4
        )

        #expect(first)
        #expect(!duplicate)
        #expect(differentProvider)
        #expect(differentSource)
        #expect(afterCooldown)
    }

    @Test("Reset clears the duplicate history")
    func resetsHistory() {
        var gate = DemoBrainRequestGate()
        let first = gate.admit(
            transcript: "open it",
            provider: .claude,
            windowID: 1,
            at: 0
        )

        gate.reset()
        let afterReset = gate.admit(
            transcript: "open it",
            provider: .claude,
            windowID: 1,
            at: 0.1
        )

        #expect(first)
        #expect(afterReset)
    }
}

@Suite("Demo Mode cloud transport")
struct DemoBrainTransportTests {
    @Test("Uses an ephemeral session for screenshot requests")
    func usesEphemeralSession() {
        let session = DemoBrainTransport.makeEphemeralSession()

        #expect(session.configuration.urlCache == nil)
        #expect(session.configuration.httpCookieStorage == nil)
        #expect(session.configuration.urlCredentialStorage == nil)
        #expect(session.configuration.timeoutIntervalForRequest == 15)
        #expect(session.configuration.timeoutIntervalForResource == 15)
    }
}
