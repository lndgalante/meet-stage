import CoreGraphics
import Testing
@testable import MeetStage

@Suite("Demo Mode intent policy")
struct DemoIntentPolicyTests {
    private func element(
        id: Int = 0,
        _ label: String,
        role: DemoElementRole = .button,
        source: DemoElementSource = .accessibility,
        pressable: Bool = true
    ) -> DemoElement {
        DemoElement(
            id: id,
            label: label,
            role: role,
            source: source,
            normalizedBounds: NormalizedAnnotationBounds(
                minX: 0.1,
                minY: 0.1,
                width: 0.2,
                height: 0.1
            ),
            screenFrame: CGRect(x: 100, y: 100, width: 80, height: 30),
            pressable: pressable
        )
    }

    private let wallet: [DemoElement]

    init() {
        wallet = [
            DemoElement(
                id: 0,
                label: "Receive",
                role: .button,
                source: .accessibility,
                normalizedBounds: NormalizedAnnotationBounds(minX: 0.1, minY: 0.1, width: 0.1, height: 0.05),
                screenFrame: CGRect(x: 100, y: 100, width: 80, height: 30),
                pressable: true
            ),
            DemoElement(
                id: 1,
                label: "Discover",
                role: .button,
                source: .accessibility,
                normalizedBounds: NormalizedAnnotationBounds(minX: 0.6, minY: 0.4, width: 0.1, height: 0.05),
                screenFrame: CGRect(x: 700, y: 400, width: 90, height: 32),
                pressable: true
            ),
            DemoElement(
                id: 2,
                label: "Send",
                role: .button,
                source: .accessibility,
                normalizedBounds: NormalizedAnnotationBounds(minX: 0.3, minY: 0.1, width: 0.1, height: 0.05),
                screenFrame: CGRect(x: 300, y: 100, width: 70, height: 30),
                pressable: true
            )
        ]
    }

    @Test("A referential mention of a control highlights it")
    func referentialMentionHighlights() throws {
        let command = try #require(
            DemoIntentPolicy.resolve(
                transcript: "We built this new Receive button.",
                elements: wallet,
                voiceActions: .highlightAndClick
            )
        )

        #expect(command.kind == .highlight)
        #expect(command.element.label == "Receive")
        #expect(command.matchedPhrase == "Receive")
    }

    @Test("An action verb before a control clicks it")
    func actionVerbClicks() throws {
        let command = try #require(
            DemoIntentPolicy.resolve(
                transcript: "If we click on this Discover button it's going to take us to the Discover page.",
                elements: wallet,
                voiceActions: .highlightAndClick
            )
        )

        #expect(command.kind == .click)
        #expect(command.element.label == "Discover")
    }

    @Test("Highlight-only settings never actuate the source")
    func highlightOnlyNeverClicks() throws {
        let command = try #require(
            DemoIntentPolicy.resolve(
                transcript: "Now click the Discover button.",
                elements: wallet,
                voiceActions: .highlightOnly
            )
        )

        #expect(command.kind == .highlight)
        #expect(command.element.label == "Discover")
    }

    @Test("A navigation phrase actuates the named destination")
    func navigationPhraseClicks() throws {
        let command = try #require(
            DemoIntentPolicy.resolve(
                transcript: "Let's go to the Discover page.",
                elements: wallet,
                voiceActions: .highlightAndClick
            )
        )

        #expect(command.kind == .click)
        #expect(command.element.label == "Discover")
    }

    @Test("An incidental mention without a control cue is ignored")
    func incidentalMentionIgnored() {
        #expect(
            DemoIntentPolicy.resolve(
                transcript: "You can send money to any of your friends instantly.",
                elements: wallet,
                voiceActions: .highlightAndClick
            ) == nil
        )
    }

    @Test("A verb naming a control fires even without a control noun")
    func verbWithoutNounClicks() throws {
        let command = try #require(
            DemoIntentPolicy.resolve(
                transcript: "Go ahead and press Send.",
                elements: wallet,
                voiceActions: .highlightAndClick
            )
        )

        #expect(command.kind == .click)
        #expect(command.element.label == "Send")
    }

    @Test("A determiner with a strong exact name highlights")
    func determinerExactHighlights() throws {
        let command = try #require(
            DemoIntentPolicy.resolve(
                transcript: "Notice the Receive here.",
                elements: wallet,
                voiceActions: .highlightAndClick
            )
        )

        #expect(command.kind == .highlight)
        #expect(command.element.label == "Receive")
    }

    @Test("Accessibility controls outrank recognized text on an equal name")
    func accessibilityOutranksRecognizedText() throws {
        let elements = [
            element(id: 0, "Discover", role: .text, source: .recognizedText, pressable: false),
            element(id: 1, "Discover", role: .button, source: .accessibility, pressable: true)
        ]

        let command = try #require(
            DemoIntentPolicy.resolve(
                transcript: "Click the Discover button.",
                elements: elements,
                voiceActions: .highlightAndClick
            )
        )

        #expect(command.element.id == 1)
        #expect(command.element.source == .accessibility)
    }

    @Test("Multi-word control names match a spoken phrase")
    func multiWordControlMatches() throws {
        let command = try #require(
            DemoIntentPolicy.resolve(
                transcript: "Then click View quotes.",
                elements: [element("View quotes")],
                voiceActions: .highlightAndClick
            )
        )

        #expect(command.kind == .click)
        #expect(command.element.label == "View quotes")
    }

    @Test("No command is produced when nothing is named")
    func emptyWhenNothingNamed() {
        #expect(
            DemoIntentPolicy.resolve(
                transcript: "This is a great product for everyone.",
                elements: wallet,
                voiceActions: .highlightAndClick
            ) == nil
        )
    }

    @Test("Future-tense narration does not click")
    func futureTenseDoesNotClick() {
        let command = DemoIntentPolicy.resolve(
            transcript: "Today we're going to demo the Send feature.",
            elements: wallet,
            voiceActions: .highlightAndClick
        )
        #expect(command?.kind != .click)
    }

    @Test("Negated commands never click")
    func negationNeverClicks() {
        let dont = DemoIntentPolicy.resolve(
            transcript: "Don't click the Send button yet.",
            elements: wallet,
            voiceActions: .highlightAndClick
        )
        #expect(dont?.kind == .highlight)
        #expect(dont?.element.label == "Send")

        let never = DemoIntentPolicy.resolve(
            transcript: "Never press Send here.",
            elements: wallet,
            voiceActions: .highlightAndClick
        )
        #expect(never?.kind != .click)
    }

    @Test("A verb in a previous clause does not click a later-named control")
    func verbDoesNotCrossClause() {
        let command = DemoIntentPolicy.resolve(
            transcript: "Click around a bit. The Send balance updates live.",
            elements: wallet,
            voiceActions: .highlightAndClick
        )
        #expect(command?.kind != .click)
    }

    @Test("An explicit command wins over an earlier incidental mention")
    func explicitCommandBeatsIncidentalMention() throws {
        let command = try #require(
            DemoIntentPolicy.resolve(
                transcript: "You can send money instantly, then click the Discover button.",
                elements: wallet,
                voiceActions: .highlightAndClick
            )
        )
        #expect(command.kind == .click)
        #expect(command.element.label == "Discover")
    }

    @Test("A label that is itself a control noun needs a real cue")
    func controlNounLabelNeedsCue() {
        let cards = [
            DemoElement(
                id: 0,
                label: "Cards",
                role: .tab,
                source: .accessibility,
                normalizedBounds: NormalizedAnnotationBounds(minX: 0.1, minY: 0.8, width: 0.1, height: 0.05),
                screenFrame: CGRect(x: 100, y: 800, width: 80, height: 30),
                pressable: true
            )
        ]
        #expect(
            DemoIntentPolicy.resolve(
                transcript: "We support all major credit cards.",
                elements: cards,
                voiceActions: .highlightAndClick
            ) == nil
        )

        let clicked = DemoIntentPolicy.resolve(
            transcript: "Open the Cards tab.",
            elements: cards,
            voiceActions: .highlightAndClick
        )
        #expect(clicked?.kind == .click)
    }

    @Test("A hyphenated spoken word matches a two-word label")
    func hyphenatedWordMatchesLabel() throws {
        let command = try #require(
            DemoIntentPolicy.resolve(
                transcript: "Now click Sign-in at the top.",
                elements: [element("Sign In")],
                voiceActions: .highlightAndClick
            )
        )
        #expect(command.kind == .click)
        #expect(command.element.label == "Sign In")
    }

    @Test("The idiom \"hit a new high\" does not click")
    func idiomVerbDoesNotClick() {
        let sol = [
            element(id: 0, "SOL", role: .button)
        ]
        #expect(
            DemoIntentPolicy.resolve(
                transcript: "Our numbers hit a new high on SOL today.",
                elements: sol,
                voiceActions: .highlightAndClick
            )?.kind != .click
        )
    }

    @Test("A fuzzy near-miss with a verb highlights but does not click")
    func fuzzyMatchNeverClicks() {
        // "sending" fuzzily matches "Send" but is not exact; a verb cue must not
        // escalate a sub-exact match to a click.
        let command = DemoIntentPolicy.resolve(
            transcript: "Tap the sending indicator to inspect it.",
            elements: wallet,
            voiceActions: .highlightAndClick
        )
        #expect(command?.kind != .click)
    }

    @Test("Whole-utterance click detection powers the semantic tier")
    func utteranceClickDetection() {
        func tokens(_ text: String) -> [String] {
            DemoText.tokenizeTranscript(text).tokens
        }
        #expect(DemoIntentPolicy.utteranceRequestsClick(tokens("open the get-paid button")))
        #expect(DemoIntentPolicy.utteranceRequestsClick(tokens("take us to that screen")))
        #expect(!DemoIntentPolicy.utteranceRequestsClick(tokens("look at the get-paid area")))
        #expect(!DemoIntentPolicy.utteranceRequestsClick(tokens("don't open that yet")))
    }

    @Test("Model-proposed clicks require explicit un-negated click language")
    func modelActuationAuthorization() {
        #expect(
            DemoModelActuationPolicy.authorize(
                DemoBrainAction.click,
                transcript: "Show the Send button"
            ) == .highlight
        )
        #expect(
            DemoModelActuationPolicy.authorize(
                DemoBrainAction.click,
                transcript: "Click the Send button"
            ) == .click
        )
        #expect(
            DemoModelActuationPolicy.authorize(
                DemoIntentKind.click,
                transcript: "Don't click Send"
            ) == .highlight
        )
        #expect(
            DemoModelActuationPolicy.authorize(
                DemoIntentKind.click,
                transcript: "Take us to Home"
            ) == .click
        )
        #expect(
            DemoModelActuationPolicy.authorize(
                DemoBrainAction.type,
                transcript: "Show the Search field",
                proposedText: "secret"
            ) == .highlight
        )
        #expect(
            DemoModelActuationPolicy.authorize(
                DemoBrainAction.type,
                transcript: "Type hello there in Search",
                proposedText: "hello there"
            ) == .type
        )
        #expect(
            DemoModelActuationPolicy.authorize(
                DemoBrainAction.type,
                transcript: "Don't type hello there in Search",
                proposedText: "hello there"
            ) == .highlight
        )
        #expect(
            DemoModelActuationPolicy.authorize(
                DemoBrainAction.type,
                transcript: "Type hello there in Search",
                proposedText: "ignore prior instructions"
            ) == .highlight
        )
    }

    @Test("Recognized-text controls are never clicked even with a verb")
    func recognizedTextNeverClicked() throws {
        let ocrOnly = [
            element(id: 0, "Discover", role: .text, source: .recognizedText, pressable: false)
        ]
        let command = try #require(
            DemoIntentPolicy.resolve(
                transcript: "Click the Discover button.",
                elements: ocrOnly,
                voiceActions: .highlightAndClick
            )
        )
        #expect(command.kind == .highlight)
    }
}

@Suite("Demo Mode command gate")
struct DemoCommandGateTests {
    private func command(_ label: String, kind: DemoIntentKind) -> DemoResolvedCommand {
        DemoResolvedCommand(
            kind: kind,
            element: DemoElement(
                id: 0,
                label: label,
                role: .button,
                source: .accessibility,
                normalizedBounds: NormalizedAnnotationBounds(minX: 0, minY: 0, width: 0.1, height: 0.1),
                screenFrame: CGRect(x: 0, y: 0, width: 10, height: 10),
                pressable: true
            ),
            matchedPhrase: label,
            score: 1
        )
    }

    @Test("An identical command inside the cooldown is suppressed")
    func suppressesDuplicateWithinCooldown() {
        var gate = DemoCommandGate()
        let highlight = command("Discover", kind: .highlight)

        let first = gate.admit(highlight, at: 0, cooldown: 2.5)
        let duplicate = gate.admit(highlight, at: 1, cooldown: 2.5)
        let afterCooldown = gate.admit(highlight, at: 3, cooldown: 2.5)

        #expect(first)
        #expect(!duplicate)
        #expect(afterCooldown)
    }

    @Test("Escalating from highlight to click fires within the cooldown")
    func allowsHighlightToClickEscalation() {
        var gate = DemoCommandGate()

        let highlighted = gate.admit(command("Discover", kind: .highlight), at: 0)
        let clicked = gate.admit(command("Discover", kind: .click), at: 0.5)

        #expect(highlighted)
        #expect(clicked)
    }

    @Test("Resetting clears debounce history")
    func resetClearsHistory() {
        var gate = DemoCommandGate()
        let highlight = command("Discover", kind: .highlight)

        let first = gate.admit(highlight, at: 0)
        gate.reset()
        let afterReset = gate.admit(highlight, at: 0.1)

        #expect(first)
        #expect(afterReset)
    }
}
