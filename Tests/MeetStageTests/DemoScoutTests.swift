import Foundation
import Testing

@testable import MeetStage

@Suite("Demo scouting")
@MainActor
struct DemoScoutTests {
    private func makeDemo(_ prompt: String) -> RealTimeDemo {
        RealTimeDemo(
            prompt: prompt, app: DemoAppKey(bundleID: "com.example.app", appName: "Example", engine: .chromium, isBrowser: true),
            title: "Demo", status: .draft(ScoutDraft()))
    }

    private func makeScout(_ app: FakeApp, _ model: ScriptedModel, prompt: String) throws -> DemoScout {
        var limits = fastScoutLimits()
        limits.beatPreview = .milliseconds(1)
        return try DemoScout(
            demo: makeDemo(prompt), source: app.demoSource, driver: app, model: model, key: "key", limits: limits,
            check: {}, onUpdate: { _, _ in })
    }

    @Test("Records a search, a result and highlights from what was really on screen")
    func recordsSearchFlow() async throws {
        let app = subtisApp()
        let model = ScriptedModel([
            reply(
                .typeText(elementID: 1, text: "The Matrix", submit: true, title: "Search The Matrix", script: ""),
                outline: ["Search", "Open the result", "Show the page"]),
            reply(.click(elementID: 2, title: "Open the first result", script: "")),
            reply(
                .present([
                    ScoutBeat(effect: .spotlight, elementIDs: [0, 1], title: "Show the title", script: "Here's the movie."),
                    ScoutBeat(effect: .draw, elementIDs: [2], title: "Point at download", script: "This gets the subtitle."),
                ])),
            reply(.finish(title: "Find The Matrix", startDescription: "Subtis home", closingScript: "That's it.")),
        ])
        let scout = try makeScout(app, model, prompt: "Search for The Matrix and open the result")

        #expect(try await scout.run() == .finished)

        let steps = ScoutCompaction.compact(scout.demo.draft?.records ?? [])
        #expect(steps.map(\.title) == ["Search The Matrix", "Open the first result", "Show the title", "Point at download"])
        #expect(app.log == ["type The Matrix ⏎", "click The Matrix (1999)"])
        guard case .click(let result) = steps[1].action else {
            Issue.record("Expected a click")
            return
        }
        // A result title is data, so it is found again by position, never by text.
        #expect(!result.labelIsStable)
        #expect(result.label.isEmpty)
        #expect(result.visualIndex == 0)
        #expect(scout.demo.start?.url?.absoluteString == "https://subtis.io/")
        #expect(scout.demo.start?.description == "Subtis home")
        #expect(scout.demo.outline == ["Search", "Open the result", "Show the page"])
        #expect(model.facts[1].last?.contains("screen changed") == true)
        #expect(steps[0].pre.urlKey == "subtis.io/")
        #expect(steps[1].pre.urlKey == "subtis.io/search/the-matrix")
    }

    @Test("Rejects elements that aren't on screen instead of inventing them")
    func rejectsInventedElements() async throws {
        let app = subtisApp()
        let model = ScriptedModel([
            reply(.click(elementID: 99, title: "Open blue theme", script: "")),
            reply(.blocked(reason: "There is no theme setting here.", alternative: "Search for a movie")),
        ])
        let scout = try makeScout(app, model, prompt: "Make the theme blue")

        #expect(try await scout.run() == .stopped(.blocked(reason: "There is no theme setting here.", alternative: "Search for a movie")))
        #expect(app.log.isEmpty)
        #expect(model.facts[1].last?.contains("rejected") == true)
    }

    @Test("Asks before typing text the presenter didn't write, then records the approval")
    func approvalForTyping() async throws {
        let app = subtisApp()
        let model = ScriptedModel([
            reply(.typeText(elementID: 1, text: "Inception", submit: true, title: "Search", script: "")),
            reply(.finish(title: "Search", startDescription: "Home", closingScript: "")),
        ])
        let scout = try makeScout(app, model, prompt: "Show how search works")

        guard case .stopped(.needsApproval(let pending)) = try await scout.run() else {
            Issue.record("Expected an approval request")
            return
        }
        #expect(pending.message.contains("Inception"))
        #expect(app.log.isEmpty)

        #expect(try await scout.run(approved: pending) == .finished)
        #expect(app.log == ["type Inception ⏎"])
        let steps = ScoutCompaction.compact(scout.demo.draft?.records ?? [])
        #expect(steps.first?.approved == true)
    }

    @Test("Clicking the text inside a link clicks the link")
    func textResolvesToLink() async throws {
        let app = FakeApp(
            screens: [
                "home": FakeScreen(
                    url: "https://example.com/",
                    elements: [
                        FakeElement(role: "AXLink", label: "Pricing", rect: rect(0.1, 0.1), opens: "pricing"),
                        FakeElement(role: "AXStaticText", label: "Pricing", rect: rect(0.1, 0.1)),
                    ]),
                "pricing": FakeScreen(
                    url: "https://example.com/pricing",
                    elements: [FakeElement(role: "AXHeading", label: "Plans", rect: rect(0.1, 0.05))]),
            ], start: "home")
        app.interactiveParents = [1: 0]
        let model = ScriptedModel([
            reply(.click(elementID: 1, title: "Open Pricing", script: "")),
            reply(.finish(title: "Pricing", startDescription: "Home", closingScript: "")),
        ])
        let scout = try makeScout(app, model, prompt: "Show pricing")
        #expect(try await scout.run() == .finished)
        guard case .click(let locator) = scout.demo.draft?.records.first?.steps.first?.action else {
            Issue.record("Expected a click")
            return
        }
        #expect(locator.role == "AXLink")
    }

    @Test("An approval covers only the question the presenter answered")
    func approvalsAreSpecific() {
        let link = AXNode(
            id: 0, role: "AXLink", subrole: nil, roleClass: .link, label: "Send", identifier: nil, placeholder: nil,
            help: nil, rect: rect(0.1, 0.1), isVisible: true, isSelected: false, isFocused: false, isEnabled: true,
            isSecure: false, textLength: nil, toggleValue: nil, containerID: nil, isContainer: false, inWebArea: true,
            url: nil)
        let locator = DemoElementLocator(role: "AXLink", label: "Send", labelIsStable: true, rect: rect(0.1, 0.1))
        let question = "Open “Send”? It mentions “send”."
        #expect(
            DemoScout.policy(
                for: .click(locator), node: link, prompt: "", startHost: nil, approved: true, approvedReason: question)
                == .allow)
        guard
            case .needsApproval = DemoScout.policy(
                for: .click(locator), node: link, prompt: "", startHost: nil, approved: true,
                approvedReason: "Click an unlabelled control?")
        else {
            Issue.record("A different approval must not apply")
            return
        }
    }

    @Test("A close button isn't judged by the text of the panel around it")
    func ignoresContainerText() {
        let panel = AXNode(
            id: 0, role: "AXGroup", subrole: nil, roleClass: .group, label: "Fees · Status · Confirmed (516673)",
            identifier: nil, placeholder: nil, help: nil, rect: rect(0.7, 0, 0.3, 1), isVisible: true,
            isSelected: false, isFocused: false, isEnabled: true, isSecure: false, textLength: nil, toggleValue: nil,
            containerID: nil, isContainer: true, inWebArea: true, url: nil)
        let close = AXNode(
            id: 1, role: "AXButton", subrole: nil, roleClass: .button, label: "Close", identifier: nil,
            placeholder: nil, help: nil, rect: rect(0.97, 0.02, 0.01, 0.01), isVisible: true, isSelected: false,
            isFocused: false, isEnabled: true, isSecure: false, textLength: nil, toggleValue: nil, containerID: 0,
            isContainer: false, inWebArea: true, url: nil)
        let scene = AXSnapshot(
            generation: 1, windowFrame: CGRect(x: 0, y: 0, width: 1200, height: 800), nodes: [panel, close],
            webURL: nil, dialogOpen: false, webContent: nil)
        let locator = DemoElementLocator(role: "AXButton", label: "Close", labelIsStable: true, rect: close.rect)
        #expect(
            DemoScout.policy(for: .click(locator), node: close, snapshot: scene, prompt: "", startHost: nil, approved: false)
                == .allow)
    }

    @Test("Never clicks destructive controls")
    func deniesDestructiveClicks() async throws {
        let app = FakeApp(
            screens: [
                "home": FakeScreen(
                    url: "https://example.com/",
                    elements: [FakeElement(role: "AXButton", label: "Delete account", rect: rect(0.1, 0.1))])
            ], start: "home")
        let model = ScriptedModel([
            reply(.click(elementID: 0, title: "Delete", script: "")),
            reply(.present([ScoutBeat(effect: .draw, elementIDs: [0], title: "Point at delete", script: "")])),
            reply(.finish(title: "Account", startDescription: "Home", closingScript: "")),
        ])
        let scout = try makeScout(app, model, prompt: "Show how to delete an account")

        #expect(try await scout.run() == .finished)
        #expect(app.log.isEmpty)
        #expect(model.facts[1].last?.contains("Pointing at") == true)
    }

    @Test("Refuses to repeat an action that just did nothing, and stops when stuck")
    func noProgressGuard() async throws {
        let app = subtisApp()
        let model = ScriptedModel([
            reply(.click(elementID: 2, title: "Search", script: "")),
            reply(.click(elementID: 2, title: "Search again", script: "")),
            reply(.press(.tab, title: "Tab", script: "")),
            reply(.press(.tab, title: "Tab", script: "")),
        ])
        let scout = try makeScout(app, model, prompt: "Search")

        #expect(try await scout.run() == .stopped(.limit(.stuck)))
        // A click that changed nothing gets one real-click retry before Claude hears it failed.
        #expect(app.log == ["click Buscar", "click Buscar", "press tab"])
        #expect(model.facts[1].last?.contains("no visible change") == true)
        #expect(model.facts[2].last?.contains("rejected") == true)
    }

    @Test("An interrupted build keeps dispatched actions and drops undispatched ones")
    func interruption() async throws {
        let app = subtisApp()
        let model = ScriptedModel([reply(.click(elementID: 2, title: "Search", script: ""))])
        let scout = try makeScout(app, model, prompt: "Search")
        app.failNextInput = .focusChanged
        await #expect(throws: DemoError.focusChanged) { try await scout.run() }
        scout.interrupt(byUserInput: true)
        #expect(scout.demo.draft?.records.isEmpty == true)
    }
}

@Suite("Demo compaction")
struct ScoutCompactionTests {
    private func click(_ label: String, outcome: ActOutcome, turn: Int) -> ScoutRecord {
        let locator = DemoElementLocator(
            role: "AXButton", label: label, labelIsStable: true, rect: rect(0.1, 0.1))
        let step = DemoStep(
            title: label, script: "", holdSeconds: 0.4, action: .click(locator),
            pre: ScreenSignature(selected: [], headings: [], dialogOpen: false))
        return ScoutRecord(turn: turn, steps: [step], outcome: outcome, fact: "")
    }

    private func toggle(_ outcome: ActOutcome, turn: Int) -> ScoutRecord {
        var record = click("Discreet mode", outcome: outcome, turn: turn)
        record.steps[0].action = .click(
            DemoElementLocator(role: "AXCheckBox", label: "Discreet mode", labelIsStable: true, rect: rect(0.9, 0.05)))
        return record
    }

    @Test("Keeps only the retry of an action that changed nothing")
    func dropsRetries() {
        let steps = ScoutCompaction.compact([
            click("Buscar", outcome: .noEffect, turn: 1),
            click("Buscar", outcome: .changed, turn: 2),
            click("Open", outcome: .changed, turn: 3),
        ])
        #expect(steps.map(\.title) == ["Buscar", "Open"])
    }

    @Test("Drops rejected, never-dispatched and unobserved records")
    func dropsUnusable() {
        let steps = ScoutCompaction.compact([
            click("A", outcome: .rejected, turn: 1),
            click("B", outcome: .pending, turn: 2),
            click("C", outcome: .changed, turn: 3),
            click("D", outcome: .unobserved, turn: 4),
        ])
        #expect(steps.map(\.title) == ["C"])
    }

    @Test("Drops a toggle switched and switched back with nothing shown between")
    func dropsTogglePairs() {
        let steps = ScoutCompaction.compact([
            toggle(.changed, turn: 1), toggle(.changed, turn: 2), click("Next", outcome: .changed, turn: 3),
        ])
        #expect(steps.map(\.title) == ["Next"])
    }

    @Test("Turns a scroll into a reveal hint on the next step")
    func scrollBecomesReveal() {
        let scroll = ScoutRecord(
            turn: 1, steps: [], scroll: RevealHint(container: nil, directionDown: true), outcome: .changed, fact: "")
        let steps = ScoutCompaction.compact([scroll, click("Row", outcome: .changed, turn: 2)])
        #expect(steps.count == 1)
        #expect(steps[0].reveal?.directionDown == true)
    }
}
