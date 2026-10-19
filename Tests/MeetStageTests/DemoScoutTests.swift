import Foundation
import MeetStageCore
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

    private func makeScout(
        _ app: FakeApp, _ model: ScriptedModel, prompt: String, trusted: Bool = false,
        lastPresenterInput: @escaping () -> ContinuousClock.Instant? = { nil }
    ) throws -> DemoScout {
        var limits = fastScoutLimits()
        limits.beatPreview = .milliseconds(1)
        return try DemoScout(
            demo: makeDemo(prompt), source: app.demoSource, driver: app, model: model, key: "key", limits: limits,
            trustsApp: trusted, lastPresenterInput: lastPresenterInput, check: {}, onUpdate: { _, _ in })
    }

    @Test("A strip too thin to hold anything, like ChatGPT's toolbar window, never counts as a window the demo opened")
    func thinWindowsDontCount() {
        #expect(!DemoScopeBaseline.counts(CGRect(x: 6, y: 39, width: 66, height: 20)))
        #expect(!DemoScopeBaseline.counts(CGRect(x: 0, y: 0, width: 1_728, height: 33)))
        #expect(DemoScopeBaseline.counts(CGRect(x: 200, y: 200, width: 320, height: 160)))
        #expect(DemoScopeBaseline.counts(CGRect(x: 0, y: 33, width: 1_708, height: 970)))
        #expect(DemoScopeBaseline.counts(.null))
    }

    @Test("A click that opens a separate window is closed and left out, and the build goes on")
    func closesStrayWindow() async throws {
        let app = subtisApp()
        app.nextClickOpensWindow = true
        let model = ScriptedModel([
            reply(.click(elementID: 2, title: "Open search", script: "")),
            reply(.typeText(elementID: 1, text: "The Matrix", submit: true, title: "Search The Matrix", script: "")),
            reply(.finish(title: "Find The Matrix", startDescription: "Subtis home", startLabel: "", closingScript: "")),
        ])
        let scout = try makeScout(app, model, prompt: "Search for The Matrix")

        #expect(try await scout.run() == .finished)
        #expect(app.log == ["click Buscar", "close 1 window", "type The Matrix ⏎"])
        let steps = ScoutCompaction.compact(scout.demo.draft?.records ?? [])
        #expect(steps.map(\.title) == ["Search The Matrix"])
        #expect(model.facts[1].last?.contains("opened a separate window") == true)
    }

    @Test("A window that opens while the presenter is using their Mac may be theirs, so it stays open")
    func leavesThePresentersWindow() async throws {
        let app = subtisApp()
        app.nextClickOpensWindow = true
        let model = ScriptedModel([
            reply(.click(elementID: 2, title: "Open search", script: "")),
            reply(.typeText(elementID: 1, text: "The Matrix", submit: true, title: "Search The Matrix", script: "")),
            reply(.finish(title: "Find The Matrix", startDescription: "Subtis home", startLabel: "", closingScript: ""))
        ])
        let scout = try makeScout(app, model, prompt: "Search for The Matrix", lastPresenterInput: { .now })

        #expect(try await scout.run() == .finished)
        // A window opened, though it may be theirs, so the click is never sent again to open another.
        #expect(app.log == ["click Buscar", "type The Matrix ⏎"])
        #expect(app.openWindows == 1)
        #expect(!model.facts.joined().contains { $0.contains("opened a separate window") })
    }

    @Test("Records a search, a result and highlights from what was really on screen")
    func recordsSearchFlow() async throws {
        let app = subtisApp()
        let longTitle = "Open the first result from the search results"
        let model = ScriptedModel([
            reply(
                .typeText(elementID: 1, text: "The Matrix", submit: true, title: "Search The Matrix", script: ""),
                outline: ["Search", "Open the result", "Show the page"]),
            reply(.click(elementID: 2, title: longTitle, script: "")),
            reply(
                .present([
                    ScoutBeat(effect: .spotlight, elementIDs: [0, 1], title: "Show the title", script: "Here's the movie."),
                    ScoutBeat(effect: .draw, elementIDs: [2], title: "Point at download", script: "This gets the subtitle."),
                ])),
            reply(
                .finish(
                    title: "Find The Matrix", startDescription: "Subtis home",
                    startLabel: "the Subtis home page, with the search field empty", closingScript: "That's it.")),
        ])
        let scout = try makeScout(app, model, prompt: "Search for The Matrix and open the result")

        #expect(try await scout.run() == .finished)

        let steps = ScoutCompaction.compact(scout.demo.draft?.records ?? [])
        // Titles and the start label are clamped to 32 characters.
        #expect(
            steps.map(\.title) == ["Search The Matrix", String(longTitle.prefix(32)), "Show the title", "Point at download"])
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
        #expect(scout.demo.start?.label == "the Subtis home page, with the s")
        #expect(scout.demo.outline == ["Search", "Open the result", "Show the page"])
        #expect(model.facts[1].last?.contains("observed: page subtis.io/search/the-matrix") == true)
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
        // Asked again about the same screen, which spends no turn on it.
        #expect(model.requests[1].correction?.contains("element 99 isn’t in the current list") == true)
        #expect(model.requests[1].turn == 1)
        #expect(model.facts[1].isEmpty)
    }

    @Test("Asks before typing text the presenter didn't write, then records the approval")
    func approvalForTyping() async throws {
        let app = subtisApp()
        let model = ScriptedModel([
            reply(.typeText(elementID: 1, text: "Inception", submit: true, title: "Search", script: "")),
            reply(.finish(title: "Search", startDescription: "Home", startLabel: "", closingScript: "")),
            // Nothing is highlighted, though the request asks to show something: the first finish is turned back.
            reply(.finish(title: "Search", startDescription: "Home", startLabel: "", closingScript: ""))
        ])
        let scout = try makeScout(app, model, prompt: "Show how search works")

        guard case .stopped(.needsApproval(let pending)) = try await scout.run() else {
            Issue.record("Expected an approval request")
            return
        }
        #expect(pending.message.contains("Inception"))
        #expect(app.log.isEmpty)

        #expect(pending.kind == .unrequestedText)
        #expect(try await scout.run(approved: pending) == .finished)
        #expect(app.log == ["type Inception ⏎"])
        let steps = ScoutCompaction.compact(scout.demo.draft?.records ?? [])
        #expect(steps.first?.approved == true)
    }

    @Test("In an app the presenter always allows, an ordinary question doesn't stop the build and is recorded")
    func trustedAppProceeds() async throws {
        let app = subtisApp()
        let model = ScriptedModel([
            reply(.typeText(elementID: 1, text: "Inception", submit: true, title: "Search", script: "")),
            reply(.finish(title: "Search", startDescription: "Home", startLabel: "", closingScript: "")),
            reply(.finish(title: "Search", startDescription: "Home", startLabel: "", closingScript: ""))
        ])
        let scout = try makeScout(app, model, prompt: "Show how search works", trusted: true)

        #expect(try await scout.run() == .finished)
        #expect(app.log == ["type Inception ⏎"])
        let steps = ScoutCompaction.compact(scout.demo.draft?.records ?? [])
        let step = try #require(steps.first)
        // Recorded as if the presenter had chosen Allow.
        #expect(step.approved)
        #expect(step.approvedReason == "Type “Inception” into “Buscar película”?")
    }

    @Test("Even in an app the presenter always allows, a question trust doesn't cover stops the build")
    func trustedAppStillAsks() async throws {
        let app = subtisApp()
        let model = ScriptedModel([
            reply(.openURL("https://evil.example/?q=balance", title: "Open the site", script: ""))
        ])
        let scout = try makeScout(app, model, prompt: "Show how search works", trusted: true)

        guard case .stopped(.needsApproval(let pending)) = try await scout.run() else {
            Issue.record("Expected an approval request")
            return
        }
        #expect(pending.kind == .unknownHost)
        #expect(pending.message == "Open evil.example?")
        #expect(app.log.isEmpty)
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
            reply(.finish(title: "Pricing", startDescription: "Home", startLabel: "", closingScript: "")),
            reply(.finish(title: "Pricing", startDescription: "Home", startLabel: "", closingScript: ""))
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

    @Test("A dialog's button is judged with that dialog's own text, never the page's")
    func judgesDialogText() {
        func node(_ id: Int, _ role: String, _ label: String, dialog: Int?) -> AXNode {
            AXNode(
                id: id, role: role, subrole: nil, roleClass: AXRoleClass(role: role, subrole: nil), label: label,
                identifier: nil, placeholder: nil, help: nil, rect: rect(0.4, 0.4), isVisible: true, isSelected: false,
                isFocused: false, isEnabled: true, isSecure: false, textLength: nil, toggleValue: nil, containerID: nil,
                isContainer: false, inWebArea: true, url: nil, dialog: dialog)
        }
        let page = node(0, "AXStaticText", "Delete old drafts", dialog: nil)
        let ok = node(1, "AXButton", "OK", dialog: 0)
        let locator = DemoElementLocator(role: "AXButton", label: "OK", labelIsStable: true, rect: ok.rect)
        func decision(_ text: [String], trusted: Bool) -> DemoPolicyDecision {
            let scene = AXSnapshot(
                generation: 1, windowFrame: CGRect(x: 0, y: 0, width: 1200, height: 800), nodes: [page, ok],
                webURL: nil, dialogOpen: true, webContent: nil, dialogTexts: [0: text])
            return DemoScout.policy(
                for: .click(locator), node: ok, snapshot: scene, prompt: "", startHost: nil, approved: false,
                trusted: trusted)
        }
        let question = "Click “OK” in this dialog?"
        #expect(decision(["Rename the list"], trusted: false) == .needsApproval(DemoApproval(.dialogButton, question)))
        #expect(decision(["Rename the list"], trusted: true) == .allow)
        #expect(
            decision(["Delete this transaction?"], trusted: true)
                == .needsApproval(DemoApproval(.riskyDialogButton, question)))
        // Without a snapshot there's no dialog text, so trust can't answer for it.
        #expect(
            DemoScout.policy(for: .click(locator), node: ok, prompt: "", startHost: nil, approved: false, trusted: true)
                == .needsApproval(DemoApproval(.riskyDialogButton, question)))
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
            reply(.finish(title: "Account", startDescription: "Home", startLabel: "", closingScript: "")),
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

    @Test("A route that committed and reached nothing hands the step back, so a pause before the next drops it")
    func handedBackStepsAreDropped() async throws {
        let sheet = FakeScreen(elements: [FakeElement(role: "AXButton", label: "Done", rect: rect(0.6, 0.5))])
        let app = FakeApp(screens: ["sheet": sheet], start: "sheet")
        app.isBrowser = false
        app.accessibilityKeys = [.escape]
        // The person pauses the build while the real key waits for them to stop typing.
        app.whileHandedBack = { throw CancellationError() }
        let model = ScriptedModel([reply(.press(.escape, title: "Close the sheet", script: ""))])
        let scout = try makeScout(app, model, prompt: "Close the sheet")
        await #expect(throws: CancellationError.self) { try await scout.run() }
        scout.interrupt(byUserInput: false)
        #expect(app.log == ["press escape (accessibility, unavailable)"])
        #expect(scout.demo.draft?.records.isEmpty == true)

        // Left to go on, the real key commits it again and it's kept.
        let going = FakeApp(screens: app.screens, start: "sheet")
        going.isBrowser = false
        going.accessibilityKeys = [.escape]
        going.whileHandedBack = {}
        let next = ScriptedModel([
            reply(.press(.escape, title: "Close the sheet", script: "")),
            reply(.blocked(reason: "Nothing else to show.", alternative: ""))
        ])
        let kept = try makeScout(going, next, prompt: "Close the sheet")
        #expect(try await kept.run() == .stopped(.blocked(reason: "Nothing else to show.", alternative: "")))
        #expect(going.log == ["press escape (accessibility, unavailable)", "press escape"])
        #expect(kept.demo.draft?.records.first?.outcome == .noEffect)
    }

    @Test("A retry follows the route that had no effect: the page's click, then a real click; the real key")
    func retryLadder() throws {
        let click = DemoAction.click(
            DemoElementLocator(role: "AXButton", label: "Share", labelIsStable: true, rect: rect(0.1, 0.1)))
        let key = DemoAction.press(.escape)
        let open = DemoAction.navigate(try #require(URL(string: "https://subtis.io")))
        #expect(DemoScout.retryRoute(after: .accessibility, for: click) == .pageScript)
        #expect(DemoScout.retryRoute(after: .browser, for: click) == .pointer)
        #expect(DemoScout.retryRoute(after: .borrowedScreen, for: click) == nil)
        #expect(DemoScout.retryRoute(after: .accessibility, for: key) == .realKey)
        #expect(DemoScout.retryRoute(after: .browser, for: key) == nil)
        #expect(DemoScout.retryRoute(after: .borrowedScreen, for: key) == nil)
        // Nothing to do, as Down on a list's last row, is never retried.
        #expect(DemoScout.retryRoute(after: nil, for: key) == nil)
        #expect(DemoScout.retryRoute(after: .accessibility, for: open) == nil)
        #expect(DemoScout.recordedRoute(.browser, for: click) == .pageScript)
        #expect(DemoScout.recordedRoute(.borrowedScreen, for: click) == .pointer)
        #expect(DemoScout.recordedRoute(.borrowedScreen, for: key) == .realKey)
        #expect(DemoScout.recordedRoute(.accessibility, for: key) == .accessibility)
    }
}

extension DemoScoutTests {
    @Test("A settled look stands in for the next turn's only while nothing has happened since it began")
    func settledLookReuse() {
        let frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let since = ContinuousClock.now
        let scope = DemoScopeBaseline(windowNumbers: [1])
        let look = DemoScout.SettledLook(
            snapshot: AXSnapshot(
                generation: 3, windowFrame: frame, nodes: [], webURL: nil, dialogOpen: false, webContent: nil),
            since: since, scope: scope)
        func reuses(input: ContinuousClock.Instant? = nil, scope: DemoScopeBaseline = scope, frame: CGRect? = frame)
            -> Bool
        {
            DemoScout.reuses(look, lastPresenterInput: input, scope: scope, windowFrame: frame)
        }
        #expect(reuses())
        // The presenter's input before the look began already shows in it; any after may not.
        #expect(reuses(input: since - .seconds(1)))
        #expect(!reuses(input: since))
        #expect(!reuses(input: since + .milliseconds(5)))
        // A window of the app opened or closed, or the demo window moved, resized or went away.
        #expect(!reuses(scope: DemoScopeBaseline(windowNumbers: [1, 2])))
        #expect(!reuses(scope: DemoScopeBaseline(windowNumbers: [])))
        #expect(!reuses(frame: frame.offsetBy(dx: 20, dy: 0)))
        #expect(!reuses(frame: CGRect(x: 0, y: 0, width: 1000, height: 800)))
        #expect(!reuses(frame: nil))
    }

    @Test("The next turn starts from the look the last action settled on, unless the presenter did something since")
    func reusesTheSettledLook() async throws {
        func build(lastPresenterInput: @escaping () -> ContinuousClock.Instant?) async throws -> (
            looks: Int, log: [String]
        ) {
            let app = subtisApp()
            let model = ScriptedModel([
                reply(.typeText(elementID: 1, text: "The Matrix", submit: true, title: "Search", script: "")),
                reply(.click(elementID: 2, title: "Open the first result", script: "")),
                reply(.finish(title: "Find The Matrix", startDescription: "Home", startLabel: "", closingScript: ""))
            ])
            let scout = try makeScout(
                app, model, prompt: "Search for The Matrix and open the result", lastPresenterInput: lastPresenterInput)
            #expect(try await scout.run() == .finished)
            return (app.generation, app.log)
        }
        let quiet = try await build { nil }
        let busy = try await build { .now }
        // The click went to an element of the reused look, whose handles still resolve.
        #expect(quiet.log == ["type The Matrix ⏎", "click The Matrix (1999)"])
        #expect(busy.log == quiet.log)
        // Both turns after an action take one look fewer.
        #expect(busy.looks == quiet.looks + 2)
    }

    @Test("A build's timings count its turns, model calls, reused looks, routes and waits for a pause")
    func countsTimings() async throws {
        let app = subtisApp()
        let model = ScriptedModel([
            reply(.typeText(elementID: 1, text: "The Matrix", submit: true, title: "Search", script: "")),
            reply(.click(elementID: 2, title: "Open the first result", script: "")),
            reply(.finish(title: "Find The Matrix", startDescription: "Home", startLabel: "", closingScript: ""))
        ])
        app.beforeInput = { input in
            if case .click = input { app.waitedForPause += .milliseconds(700) }
        }
        let scout = try makeScout(app, model, prompt: "Search for The Matrix and open the result")
        #expect(try await scout.run() == .finished)
        let timings = scout.timings
        #expect(timings.turns == 3)
        #expect(timings.modelCalls == 3)
        // Both turns after an action start from the look it settled on.
        #expect(timings.reusedLooks == 2)
        #expect(timings.routes == ["accessibility": 2])
        #expect(timings.pauseWait == .milliseconds(700))
        #expect(timings.settle > .zero)
    }

    @Test("Settling waits out a spinner the action started, never one already showing, and stops at its cap")
    func settleWaitsWhileBusy() async throws {
        let app = subtisApp()
        let scout = try makeScout(app, ScriptedModel([]), prompt: "Search")
        let idle = try await app.snapshot(app.demoSource, waitForContent: false)
        func settle(after previous: AXSnapshot, maximum: Duration = .seconds(4)) async throws -> (
            snapshot: AXSnapshot, looks: Int
        ) {
            let before = app.generation
            let settled = try await scout.settle(after: previous, maximum: maximum)
            return (settled, app.generation - before)
        }

        // Two looks that agree are enough while nothing spins.
        #expect(try await settle(after: idle).looks == 2)

        // Four looks with a spinner the action started, then a quiet one that agrees with the last.
        app.busyLooks = 4
        let waited = try await settle(after: idle)
        #expect(waited.looks == 5)
        #expect(waited.snapshot.busyIndicators == 0)

        // A spinner that was already there before the action never holds it up.
        app.busyLooks = 1_000
        let spinning = try await app.snapshot(app.demoSource, waitForContent: false)
        let unheld = try await settle(after: spinning)
        #expect(unheld.looks == 2)
        #expect(unheld.snapshot.busyIndicators == 1)

        // One that never stops waits only until the cap.
        app.busyLooks = .max
        let started = ContinuousClock.now
        let capped = try await settle(after: idle, maximum: .milliseconds(60))
        #expect(capped.snapshot.busyIndicators == 1)
        #expect(capped.looks > 2)
        #expect(ContinuousClock.now - started < .seconds(2))
    }

    @Test("An icon button's borrowed name answers the unlabelled question, feeds denials, and keeps old approvals")
    func borrowedNamesInThePolicy() {
        func button(_ label: String, borrowed: Bool = true, inDialog: Bool = false) -> AXNode {
            AXNode(
                id: 0, role: "AXButton", subrole: nil, roleClass: .button, label: label, identifier: nil,
                placeholder: nil, help: nil, rect: rect(0.4, 0.4), isVisible: true, isSelected: false,
                isFocused: false, isEnabled: true, isSecure: false, textLength: nil, toggleValue: nil,
                containerID: nil, isContainer: false, inWebArea: true, url: nil, dialog: inDialog ? 0 : nil,
                labelIsBorrowed: borrowed)
        }
        // Saved before the button borrowed a name, so unlabelled.
        let locator = DemoElementLocator(role: "AXButton", label: "", labelIsStable: false, rect: rect(0.4, 0.4))
        func decision(_ node: AXNode, approvedReason: String? = nil) -> DemoPolicyDecision {
            let scene = AXSnapshot(
                generation: 1, windowFrame: CGRect(x: 0, y: 0, width: 1200, height: 800), nodes: [node], webURL: nil,
                dialogOpen: node.inDialog, webContent: nil, dialogTexts: [0: ["Rename the list"]])
            return DemoScout.policy(
                for: .click(locator), node: node, snapshot: scene, prompt: "", startHost: nil,
                approved: approvedReason != nil, approvedReason: approvedReason)
        }
        #expect(
            decision(button("", borrowed: false))
                == .needsApproval(DemoApproval(.unlabelledControl, "Click an unlabelled control?")))
        #expect(decision(button("Settings")) == .allow)
        #expect(decision(button("Delete draft")) == .deny("Pointing at “Delete draft” instead of clicking it."))

        // The question a demo saved before the name asked of the control unnamed still holds.
        let unnamed = "Click “this control” in this dialog?"
        let named = DemoPolicyDecision.needsApproval(DemoApproval(.dialogButton, "Click “Done” in this dialog?"))
        #expect(decision(button("Done", inDialog: true)) == named)
        #expect(decision(button("Done", inDialog: true), approvedReason: unnamed) == .allow)
        #expect(decision(button("Done", inDialog: true), approvedReason: "Click “Finish” in this dialog?") == named)
        // Only for a borrowed name: a control that names itself was asked about by that name.
        #expect(decision(button("Done", borrowed: false, inDialog: true), approvedReason: unnamed) == named)
        // And never past a denial.
        #expect(
            decision(button("Delete", inDialog: true), approvedReason: unnamed)
                == .deny("Pointing at “Delete” instead of clicking it."))
    }

    @Test("The scout clicks an icon button by the name it borrows, without asking about an unlabelled control")
    func clicksIconButtonsByBorrowedName() async throws {
        func app(_ label: String, borrowed: Bool) -> FakeApp {
            FakeApp(
                screens: [
                    "home": FakeScreen(
                        url: "https://example.com/",
                        elements: [
                            FakeElement(
                                role: "AXButton", label: label, rect: rect(0.9, 0.05, 0.03, 0.04), opens: "settings",
                                borrowsLabel: borrowed)
                        ]),
                    "settings": FakeScreen(
                        url: "https://example.com/settings",
                        elements: [FakeElement(role: "AXHeading", label: "Settings", rect: rect(0.1, 0.05))])
                ], start: "home")
        }
        let replies = [
            reply(.click(elementID: 0, title: "Open settings", script: "")),
            reply(.finish(title: "Settings", startDescription: "Home", startLabel: "", closingScript: ""))
        ]
        let unnamed = app("", borrowed: false)
        let asked = try await makeScout(unnamed, ScriptedModel(replies), prompt: "Open settings").run()
        guard case .stopped(.needsApproval(let pending)) = asked else {
            Issue.record("Expected an approval request")
            return
        }
        #expect(pending.kind == .unlabelledControl)
        #expect(unnamed.log.isEmpty)

        let named = app("Settings", borrowed: true)
        let scout = try makeScout(named, ScriptedModel(replies), prompt: "Open settings")
        #expect(try await scout.run() == .finished)
        #expect(named.log == ["click Settings"])
        let steps = ScoutCompaction.compact(scout.demo.draft?.records ?? [])
        let step = try #require(steps.first)
        #expect(!step.approved)
        guard case .click(let locator) = step.action else {
            Issue.record("Expected a click")
            return
        }
        #expect(locator.labelIsStable)
        #expect(locator.label == "Settings")
    }
}

extension DemoScoutTests {
    @Test("An unlisted element or arguments that can't work are asked about again on the same screen, costing no turn")
    func asksAgainInPlace() async throws {
        let app = subtisApp()
        let model = ScriptedModel([
            reply(.click(elementID: 99, title: "Search", script: "")),
            reply(.click(elementID: 2, title: "Search", script: "")),
            reply(.typeText(elementID: 2, text: "The Matrix", submit: true, title: "Search", script: "")),
            reply(.press(.tab, title: "Next field", script: "")),
            reply(.openURL("not a web address", title: "Open Subtis", script: "")),
            reply(.typeText(elementID: 1, text: "The Matrix", submit: true, title: "Search The Matrix", script: "")),
            reply(.finish(title: "Find The Matrix", startDescription: "Subtis home", startLabel: "", closingScript: ""))
        ])
        let scout = try makeScout(app, model, prompt: "Search for The Matrix")

        // Two turns changed nothing, each after a reply that couldn't be used; had those
        // counted, the build would have stopped as stuck before its search.
        #expect(try await scout.run() == .finished)
        #expect(model.requests.map(\.turn) == [1, 1, 2, 2, 3, 3, 4])
        #expect(scout.demo.draft?.turn == 4)
        #expect(model.requests[1].correction?.contains("element 99 isn’t in the current list") == true)
        #expect(model.requests[3].correction?.contains("type_text needs a text field") == true)
        #expect(model.requests[5].correction?.contains("open_url only works in a browser") == true)
        #expect([0, 2, 4, 6].allSatisfy { model.requests[$0].correction == nil })
        // The same look and facts, so nothing is read again and the cached prefix still matches.
        for retry in [1, 3, 5] {
            #expect(model.requests[retry].elements == model.requests[retry - 1].elements)
            #expect(model.requests[retry].facts == model.requests[retry - 1].facts)
        }
        #expect(!model.facts.joined().contains { $0.contains("rejected") })
        #expect(scout.timings.turns == 4)
        #expect(scout.timings.modelCalls == 7)
        // Every reply is paid for, the ones set aside included.
        #expect(scout.demo.draft?.spentMicroUSD == 7_000)
    }

    @Test("A turn is asked again only once; a second reply that can't be used spends the turn")
    func asksAgainOnlyOnce() async throws {
        let app = subtisApp()
        let model = ScriptedModel([
            reply(.click(elementID: 99, title: "Theme", script: "")),
            reply(.click(elementID: 98, title: "Theme", script: "")),
            reply(.blocked(reason: "There is no theme setting here.", alternative: ""))
        ])
        let scout = try makeScout(app, model, prompt: "Make the theme blue")

        #expect(try await scout.run() == .stopped(.blocked(reason: "There is no theme setting here.", alternative: "")))
        #expect(model.requests.map(\.turn) == [1, 1, 2])
        #expect(model.requests[2].correction == nil)
        #expect(model.facts[2].last == "#1 rejected: element 98 isn’t in the current list; use an ID from it.")
        #expect(scout.progress.unchanged == 1)
        #expect(app.log.isEmpty)
    }

    @Test("A correction answered in prose rejects the reply it corrected and spends the turn, ending nothing")
    func proseAfterACorrectionRejects() async throws {
        let app = subtisApp()
        let model = ScriptedModel([
            reply(.click(elementID: 41, title: "Theme", script: "")),
            .failure(
                DemoModelFailure(
                    underlying: DemoModelError.noToolCall("Sorry, I picked an element that isn't there."),
                    costMicroUSD: 500)),
            reply(.blocked(reason: "There is no theme setting here.", alternative: ""))
        ])
        let scout = try makeScout(app, model, prompt: "Make the theme blue")

        #expect(try await scout.run() == .stopped(.blocked(reason: "There is no theme setting here.", alternative: "")))
        #expect(model.requests.map(\.turn) == [1, 1, 2])
        #expect(model.facts[2].last == "#1 rejected: element 41 isn’t in the current list; use an ID from it.")
        #expect(scout.progress.unchanged == 1)
        // Both replies and the prose are paid for, once each.
        #expect(scout.demo.draft?.spentMicroUSD == 2_500)
    }

    @Test("Actions the policy turns down count toward their own stop, never toward the stuck one")
    func denialsStopOnTheirOwn() async throws {
        let app = subtisApp()
        app.screens["home"]?.elements.append(
            FakeElement(role: "AXButton", label: "Delete account", rect: rect(0.1, 0.5)))
        let delete = reply(.click(elementID: 3, title: "Delete", script: ""))
        let model = ScriptedModel([
            reply(.click(elementID: 2, title: "Search", script: "")), delete,
            reply(.press(.tab, title: "Next field", script: "")), delete, delete, delete,
            reply(.finish(title: "Account", startDescription: "Home", startLabel: "", closingScript: ""))
        ])
        let scout = try makeScout(app, model, prompt: "Show how to delete an account")

        // Two turns without change and four denials: the build stops for the denials in a row.
        #expect(try await scout.run() == .stopped(.limit(.denied)))
        #expect(model.requests.count == 6)
        #expect(scout.progress.unchanged == 2)
        #expect(model.facts[2].last?.contains("rejected: Pointing at “Delete account” instead of clicking it.") == true)
        #expect(app.log == ["click Buscar", "click Buscar", "press tab"])
        #expect(
            ScoutStop.limit(.denied).message == "Stopped because Claude kept choosing actions BetterMeets won’t do.")
    }

    @Test("A change Claude says went the wrong way counts toward the stuck limit, and the demo still keeps the step")
    func wrongTurnsCountAsNoChange() async throws {
        let app = subtisApp()
        let wrong = ScoutJudgement(verdict: .wrongTurn, reason: "  Opened the results,\n not   the settings ")
        let model = ScriptedModel([
            reply(.click(elementID: 2, title: "Search", script: "")),
            reply(.press(.tab, title: "Next field", script: "")),
            reply(.typeText(elementID: 1, text: "The Matrix", submit: true, title: "Search The Matrix", script: "")),
            reply(.press(.escape, title: "Back", script: ""), previous: wrong),
            reply(.finish(title: "Find The Matrix", startDescription: "Subtis home", startLabel: "", closingScript: ""))
        ])
        let scout = try makeScout(app, model, prompt: "Search for The Matrix")

        // Two turns without change, the search, then Escape doing nothing: the search
        // counts as the third without change, so the build stops instead of finishing.
        #expect(try await scout.run() == .stopped(.limit(.stuck)))
        #expect(model.requests.count == 4)
        let records = scout.demo.draft?.records ?? []
        let search = try #require(records.first { $0.turn == 3 })
        #expect(search.outcome == .changed)
        #expect(search.judgement == ScoutJudgement(verdict: .wrongTurn, reason: "Opened the results, not the settings"))
        #expect(ScoutCompaction.compact(records).map(\.title).contains("Search The Matrix"))
        // Something did change, so the stop never says nothing did.
        #expect(
            ScoutStop.limit(.stuck).message == "Stopped because the last few actions didn’t get the demo anywhere.")
    }

    @Test("Each fact says what Claude expected and what was observed, and targets keep Claude's cleaned notes")
    func recordsExpectationsAndTargets() async throws {
        let app = subtisApp()
        let model = ScriptedModel([
            reply(
                .click(elementID: 2, title: "Search", script: ""), expect: "  the results\n list opens ",
                target: "button right of the search field"),
            reply(
                .typeText(elementID: 1, text: "The Matrix", submit: true, title: "Search The Matrix", script: ""),
                expect: "results for The Matrix appear", target: "wide field near the top, 2nd from the left"),
            reply(
                .present([
                    ScoutBeat(
                        effect: .spotlight, elementIDs: [2, 3], title: "The results", script: "",
                        target: "the list of results below the heading")
                ]), expect: "ignored for a highlight"),
            reply(.finish(title: "Find The Matrix", startDescription: "Subtis home", startLabel: "", closingScript: ""))
        ])
        let scout = try makeScout(app, model, prompt: "Search for The Matrix")
        #expect(try await scout.run() == .finished)

        #expect(
            model.facts[1].last
                == "#1 clicked button “Buscar” → expected: the results list opens / "
                + "observed: no visible change; don’t repeat it")
        #expect(
            model.facts[2].last?.hasPrefix(
                "#2 typed “The Matrix” into “Buscar película” + Return → expected: results for The Matrix appear / "
                    + "observed: page subtis.io/search/the-matrix; heading “Resultados”") == true)
        #expect(model.facts[3].last?.contains("expected:") == false)
        let records = scout.demo.draft?.records ?? []
        #expect(records.map(\.expected) == ["the results list opens", "results for The Matrix appear", nil])
        let locators = records.flatMap(\.steps).flatMap(\.action.locators)
        // Numbers are live data, so the note loses them.
        let notes = locators.map(\.note)
        #expect(
            notes == [
                "button right of the search field", "wide field near the top, from the left",
                "the list of results below the heading", nil
            ])
    }
}

extension DemoScoutTests {
    /// A bank's home with Overview and Activity tabs, each tab opening its own page.
    private func tabsApp() -> FakeApp {
        func page(_ name: String, selected: String, heading: String) -> FakeScreen {
            let tabs = ["Overview", "Activity"].enumerated().map { index, label in
                FakeElement(
                    role: "AXRadioButton", label: label, rect: rect(0.1 + Double(index) * 0.15, 0.05),
                    subrole: "AXTabButton", selected: label == selected,
                    opens: label == selected ? nil : label == "Overview" ? "home" : "activity")
            }
            return FakeScreen(
                url: "https://bank.example/\(name)",
                elements: tabs + [FakeElement(role: "AXHeading", label: heading, rect: rect(0.1, 0.2))])
        }
        return FakeApp(
            screens: [
                "home": page("home", selected: "Overview", heading: "Balance"),
                "activity": page("activity", selected: "Activity", heading: "Recent activity")
            ], start: "home")
    }

    @Test("A detour that comes back to where it began is left out of the demo, unless the finish cites it")
    func leavesOutDetours() async throws {
        func build(outline: [String], coverage: [ScoutBeatCoverage]) async throws -> ScoutDraft {
            let app = tabsApp()
            let model = ScriptedModel([
                reply(.click(elementID: 1, title: "Open Activity", script: ""), outline: outline),
                reply(.click(elementID: 0, title: "Back to Overview", script: "")),
                reply(.present([ScoutBeat(effect: .spotlight, elementIDs: [2], title: "The balance", script: "")])),
                reply(
                    .finish(title: "Balance", startDescription: "Overview", startLabel: "", closingScript: ""),
                    coverage: coverage)
            ])
            let scout = try makeScout(app, model, prompt: "Highlight the balance")
            #expect(try await scout.run() == .finished)
            #expect(app.log == ["click Activity", "click Overview"])
            return try #require(scout.demo.draft)
        }
        let wandered = try await build(outline: ["The balance"], coverage: [ScoutBeatCoverage(beat: 1, steps: [3])])
        #expect(wandered.coverage == [ScoutBeatCoverage(beat: 1, steps: [3])])
        #expect(ScoutCompaction.compact(wandered).map(\.title) == ["The balance"])
        // Every record is kept as the scout made it, so the demo compiles again without pruning.
        #expect(
            ScoutCompaction.compact(wandered, pruning: false).map(\.title)
                == ["Open Activity", "Back to Overview", "The balance"])

        let cited = try await build(
            outline: ["The activity", "The balance"],
            coverage: [ScoutBeatCoverage(beat: 1, steps: [1]), ScoutBeatCoverage(beat: 2, steps: [3])])
        #expect(ScoutCompaction.compact(cited).map(\.title) == ["Open Activity", "Back to Overview", "The balance"])
    }

    @Test("The first finish is turned back once when a beat has no step, without counting toward the stuck limit")
    func finishCoversTheOutline() async throws {
        let app = subtisApp()
        let finish = ScoutDecision.finish(
            title: "Find The Matrix", startDescription: "Subtis home", startLabel: "", closingScript: "")
        let model = ScriptedModel([
            reply(
                .typeText(elementID: 1, text: "The Matrix", submit: true, title: "Search The Matrix", script: ""),
                outline: ["Search", "Open the result", "Show the page"]),
            reply(.click(elementID: 2, title: "Open the first result", script: "")),
            reply(
                finish,
                coverage: [
                    ScoutBeatCoverage(beat: 1, steps: [1]), ScoutBeatCoverage(beat: 2, steps: [2]),
                    ScoutBeatCoverage(beat: 3, steps: [])
                ]),
            reply(.present([ScoutBeat(effect: .spotlight, elementIDs: [0], title: "The title", script: "")])),
            reply(
                finish,
                coverage: [
                    ScoutBeatCoverage(beat: 1, steps: [1]), ScoutBeatCoverage(beat: 2, steps: [2]),
                    ScoutBeatCoverage(beat: 3, steps: [4])
                ])
        ])
        let scout = try makeScout(app, model, prompt: "Search for The Matrix and open the result")

        #expect(try await scout.run() == .finished)
        #expect(
            model.facts[3].last
                == "#3 rejected finish: beat 3 “Show the page” has no step in the demo that shows it. Show what’s "
                + "missing, or call finish again if it can’t be shown.")
        #expect(scout.progress.unchanged == 0)
        let draft = try #require(scout.demo.draft)
        #expect(draft.finishTurnedBack == true)
        #expect(draft.coverage?.last == ScoutBeatCoverage(beat: 3, steps: [4]))
        #expect(
            ScoutCompaction.compact(draft).map(\.title) == ["Search The Matrix", "Open the first result", "The title"])
    }

    @Test("A finish is turned back only once per build, and never when no turn is left to act on it")
    func turnsBackOnlyOnce() async throws {
        let search = reply(.typeText(elementID: 1, text: "The Matrix", submit: true, title: "Search", script: ""))
        let finish = reply(
            .finish(title: "Search", startDescription: "Subtis home", startLabel: "", closingScript: ""),
            coverage: [ScoutBeatCoverage(beat: 1, steps: [])])
        func build(_ replies: [Result<ScoutReply, Error>], maxTurns: Int = 24) async throws -> (
            ScoutResult, ScriptedModel
        ) {
            let app = subtisApp()
            let model = ScriptedModel(replies)
            var limits = fastScoutLimits()
            limits.maxTurns = maxTurns
            let scout = try DemoScout(
                demo: makeDemo("Show how to search for The Matrix"), source: app.demoSource, driver: app,
                model: model, key: "key", limits: limits, check: {}, onUpdate: { _, _ in })
            return (try await scout.run(), model)
        }
        let outlined = reply(
            .typeText(elementID: 1, text: "The Matrix", submit: true, title: "Search", script: ""), outline: ["Search"])
        let (twice, model) = try await build([outlined, finish, finish])
        #expect(twice == .finished)
        #expect(model.requests.count == 3)
        #expect(
            model.facts[2].last?.hasPrefix(
                "#2 rejected finish: beat 1 “Search” has no step in the demo that shows it, and nothing is "
                    + "highlighted, though the request asks to show something.") == true)

        // On the last turn there's no turn left to cover anything, so the finish stands.
        let (last, lastModel) = try await build([search, finish], maxTurns: 2)
        #expect(last == .finished)
        #expect(lastModel.requests.count == 2)
    }
}

extension DemoScoutTests {
    /// A native view with a button, and nothing a scroll or a key visibly changes.
    private func nativeApp(_ elements: [FakeElement]) -> FakeApp {
        let app = FakeApp(screens: ["main": FakeScreen(elements: elements)], start: "main")
        app.isBrowser = false
        app.engine = .native
        return app
    }

    @Test("A scroll or a key whose effect Accessibility read back counts as done, and is never sent again")
    func confirmedStandInsAreDone() async throws {
        // A text view: the scroll bar moved, but its elements read the same afterwards.
        let app = nativeApp([FakeElement(role: "AXTextArea", label: "Note", rect: rect(0.1, 0.1, 0.8, 0.8))])
        app.accessibilityScrolls = true
        app.accessibilityKeys = [.pageDown]
        app.ignoresStandIns = true
        app.accessibilityDelivery = .confirmed
        let model = ScriptedModel([
            reply(.scroll(containerID: nil, down: true)), reply(.scroll(containerID: nil, down: true)),
            reply(.press(.pageDown, title: "Next page", script: "")), reply(.scroll(containerID: nil, down: true)),
            reply(.blocked(reason: "That's the whole note.", alternative: ""))
        ])
        let scout = try makeScout(app, model, prompt: "Read the note")

        // Four of them, none counting as stuck.
        #expect(try await scout.run() == .stopped(.blocked(reason: "That's the whole note.", alternative: "")))
        #expect(
            app.log == [
                "scroll down (accessibility, ignored)", "scroll down (accessibility, ignored)",
                "press page_down (accessibility, ignored)", "scroll down (accessibility, ignored)"
            ])
        #expect(scout.progress.unchanged == 0)
        let facts = try #require(model.facts.last)
        #expect(facts[0] == "#1 scrolled down → more content is visible")
        #expect(facts[2].hasSuffix("observed: the screen changed in place"))
        let records = scout.demo.draft?.records ?? []
        #expect(records.allSatisfy { $0.scroll?.route == nil && $0.steps.first?.route != .realKey })
    }

    @Test("Input that may already have acted is never sent again by another route")
    func uncertainInputIsNotRepeated() async throws {
        let app = nativeApp([
            FakeElement(role: "AXButton", label: "Open details", rect: rect(0.1, 0.1), ignoresPress: true)
        ])
        app.accessibilityKeys = [.escape]
        app.ignoresStandIns = true
        app.accessibilityDelivery = .uncertain
        let model = ScriptedModel([
            reply(.press(.escape, title: "Close", script: "")),
            reply(.click(elementID: 0, title: "Details", script: "")),
            reply(.blocked(reason: "Nothing opens.", alternative: ""))
        ])
        let scout = try makeScout(app, model, prompt: "Open the details")
        #expect(try await scout.run() == .stopped(.blocked(reason: "Nothing opens.", alternative: "")))
        #expect(app.log == ["press escape (accessibility, ignored)", "press Open details (ignored)"])
        #expect(model.facts.last?.allSatisfy { !$0.contains("needed") } == true)
    }

    @Test("While building, a click a second click could do twice, or the presenter approved, is never sent again")
    func someClicksAreNeverRetriedWhileBuilding() async throws {
        let controls = [
            FakeElement(role: "AXButton", label: "Add task", rect: rect(0.1, 0.1)),
            FakeElement(role: "AXButton", label: "Save", rect: rect(0.1, 0.1)),
            FakeElement(role: "AXButton", label: "Dark mode", rect: rect(0.1, 0.1)),
            FakeElement(role: "AXCheckBox", label: "Notifications", rect: rect(0.1, 0.1), toggle: false),
            FakeElement(role: "AXButton", label: "", rect: rect(0.1, 0.1), help: "Create a list")
        ]
        for var control in controls {
            control.ignoresPress = true
            let app = nativeApp([control])
            let model = ScriptedModel([
                reply(.click(elementID: 0, title: "Act", script: "")),
                reply(.blocked(reason: "Nothing happens.", alternative: ""))
            ])
            let scout = try makeScout(app, model, prompt: "Show it")
            #expect(try await scout.run() == .stopped(.blocked(reason: "Nothing happens.", alternative: "")))
            #expect(app.log == ["press \(control.label) (ignored)"], "\(control.label)")
            #expect(model.facts.last?.last?.contains("no visible change") == true)
        }

        // A dialog's button the presenter approved: approved once, clicked once.
        let app = nativeApp([FakeElement(role: "AXButton", label: "Allow", rect: rect(0.4, 0.5), inDialog: true)])
        app.screens["main"]?.dialogOpen = true
        app.screens["main"]?.elements[0].ignoresPress = true
        let model = ScriptedModel([
            reply(.click(elementID: 0, title: "Allow it", script: "")),
            reply(.blocked(reason: "Nothing happens.", alternative: ""))
        ])
        let scout = try makeScout(app, model, prompt: "Allow notifications")
        guard case .stopped(.needsApproval(let pending)) = try await scout.run() else {
            Issue.record("Expected an approval")
            return
        }
        let approvedRun = try await scout.run(approved: pending)
        #expect(approvedRun == .stopped(.blocked(reason: "Nothing happens.", alternative: "")))
        #expect(app.log == ["press Allow (ignored)"])
    }

    @Test("A retry that can't reach its target, as when something now covers it, ends the retries, not the build")
    func undeliveredRetriesEndQuietly() async throws {
        let app = nativeApp([
            FakeElement(role: "AXButton", label: "Open details", rect: rect(0.1, 0.1), ignoresPress: true)
        ])
        var inputs = 0
        app.beforeInput = { _ in
            inputs += 1
            if inputs == 1 { app.failNextInput = .occluded("Open details") }
        }
        let model = ScriptedModel([
            reply(.click(elementID: 0, title: "Details", script: "")),
            reply(.blocked(reason: "Nothing opens.", alternative: ""))
        ])
        let scout = try makeScout(app, model, prompt: "Open the details")
        #expect(try await scout.run() == .stopped(.blocked(reason: "Nothing opens.", alternative: "")))
        #expect(app.log == ["press Open details (ignored)"])
        #expect(model.facts.last?.last?.contains("no visible change") == true)
    }

    @Test("A click the app shows late gets the effect window and a fresh look before it's sent again")
    func slowClicksGetTheirWindow() async throws {
        let details = FakeScreen(elements: [FakeElement(role: "AXHeading", label: "Details", rect: rect(0.1, 0.1))])
        let app = nativeApp([
            FakeElement(role: "AXButton", label: "Open details", rect: rect(0.1, 0.1), opens: "details")
        ])
        app.screens["details"] = details
        // Two looks agree on the old screen before the new one shows.
        app.opensAfterLooks = 2
        let model = ScriptedModel([
            reply(.click(elementID: 0, title: "Details", script: "")),
            reply(.blocked(reason: "Done.", alternative: ""))
        ])
        var limits = fastScoutLimits()
        limits.effectWindow = .milliseconds(500)
        let scout = try DemoScout(
            demo: makeDemo("Open the details"), source: app.demoSource, driver: app, model: model, key: "key",
            limits: limits, check: {}, onUpdate: { _, _ in })
        #expect(try await scout.run() == .stopped(.blocked(reason: "Done.", alternative: "")))
        #expect(app.log == ["click Open details"])
        #expect(scout.demo.draft?.records.first?.outcome == .changed)
        #expect(scout.demo.draft?.records.first?.steps.first?.route == .accessibility)
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

    /// A record that began on `screen`, as `AXSnapshot.screenKey` names it.
    private func on(_ screen: String, _ record: ScoutRecord) -> ScoutRecord {
        var record = record
        record.screen = screen
        return record
    }

    private func tab(_ label: String, turn: Int) -> ScoutRecord {
        var record = click(label, outcome: .changed, turn: turn)
        record.steps[0].action = .click(
            DemoElementLocator(
                role: "AXRadioButton", subrole: "AXTabButton", label: label, labelIsStable: true, rect: rect(0.1, 0.1)))
        return record
    }

    private func highlight(turn: Int) -> ScoutRecord {
        let beat = DemoBeat(
            effect: .spotlight,
            targets: [
                DemoElementLocator(role: "AXHeading", label: "Activity", labelIsStable: true, rect: rect(0.1, 0.2))
            ])
        let step = DemoStep(
            title: "The activity", script: "", holdSeconds: 1.6, action: .present(beat),
            pre: ScreenSignature(selected: [], headings: [], dialogOpen: false))
        return ScoutRecord(turn: turn, steps: [step], outcome: .changed, fact: "")
    }

    @Test("Cuts clicks that went somewhere and came back to the screen they left, with nothing shown on the way")
    func cutsDetours() {
        let detour = [
            on("home", tab("Activity", turn: 1)), on("activity", click("Filters", outcome: .changed, turn: 2)),
            on("filters", tab("Overview", turn: 3)), on("home", click("Open", outcome: .changed, turn: 4))
        ]
        #expect(ScoutCompaction.compact(detour).map(\.title) == ["Open"])
        // Kept in full without pruning, as the records always are.
        #expect(
            ScoutCompaction.compact(detour, pruning: false).map(\.title) == ["Activity", "Filters", "Overview", "Open"])
        // A detour that never comes back stays, and so does one whose clicks Claude's finish cites.
        let away = [on("home", tab("Activity", turn: 1)), on("activity", click("Open", outcome: .changed, turn: 2))]
        #expect(ScoutCompaction.compact(away).map(\.title) == ["Activity", "Open"])
        #expect(ScoutCompaction.compact(detour, keeping: [2]).count == 4)
        // Records saved before screens were recorded never match.
        let unknown = detour.map { record in
            var record = record
            record.screen = nil
            return record
        }
        #expect(ScoutCompaction.compact(unknown).count == 4)
    }

    @Test("Keeps a round trip that typed, toggled, needed approval, scrolled a target in, or showed something")
    func keepsDetoursThatDidSomething() {
        func roundTrip(through middle: ScoutRecord) -> [String] {
            ScoutCompaction.compact([
                on("home", tab("Activity", turn: 1)), on("activity", middle), on("filters", tab("Overview", turn: 3)),
                on("home", click("Open", outcome: .changed, turn: 4))
            ]).map(\.title)
        }
        var typed = click("Search", outcome: .changed, turn: 2)
        typed.steps[0].action = .typeText(
            field: DemoElementLocator(role: "AXTextField", label: "Search", labelIsStable: true, rect: rect(0.1, 0.1)),
            text: "rent", submit: false)
        var switched = toggle(.changed, turn: 2)
        switched.steps[0].title = "Search"
        var named = click("Dark mode", outcome: .changed, turn: 2)
        named.steps[0].title = "Search"
        var approved = click("Search", outcome: .changed, turn: 2)
        approved.steps[0].approved = true
        var framed = click("Search", outcome: .changed, turn: 2)
        framed.steps[0].framing = 0.2
        var shown = highlight(turn: 2)
        shown.steps[0].title = "Search"
        let scrolled = ScoutRecord(
            turn: 2, steps: [], scroll: RevealHint(container: nil, directionDown: true), outcome: .changed, fact: "")
        for middle in [typed, switched, named, approved, framed, shown] {
            #expect(roundTrip(through: middle) == ["Activity", "Search", "Overview", "Open"])
        }
        #expect(roundTrip(through: scrolled) == ["Activity", "Overview", "Open"])
        // A contaminated click's effect is unknown, so it can't be part of a detour either.
        #expect(roundTrip(through: click("Search", outcome: .contaminated, turn: 2)).count == 4)
    }

    @Test("Cuts a click that showed nothing on its own, never typing or a key that did, or one the finish cites")
    func cutsSilentClicks() {
        var key = click("Escape", outcome: .noEffect, turn: 2)
        key.steps[0].action = .press(.escape)
        let records = [click("Help", outcome: .noEffect, turn: 1), key, click("Open", outcome: .changed, turn: 3)]
        #expect(ScoutCompaction.compact(records).map(\.title) == ["Escape", "Open"])
        #expect(ScoutCompaction.compact([click("Help", outcome: .noEffect, turn: 1)], pruning: false).count == 1)
        // Claude saw it work, as a sort that only reorders rows does, though the digest read the same.
        #expect(ScoutCompaction.compact(records, keeping: [1]).map(\.title) == ["Help", "Escape", "Open"])
    }

    @Test("Claude's wrong turn lets a round trip match by its screen signature, but never cuts anything alone")
    func wrongTurnsHelpMatchScreens() {
        func signed(_ record: ScoutRecord, _ url: String?, selected: [String] = []) -> ScoutRecord {
            var record = record
            record.steps[0].pre = ScreenSignature(urlKey: url, selected: selected, headings: [], dialogOpen: false)
            return record
        }
        let wrong = ScoutJudgement(verdict: .wrongTurn, reason: "Opened billing, not activity")
        var billing = on("home", signed(tab("Billing", turn: 1), "app.example/home"))
        let back = on("billing", signed(tab("Home", turn: 2), "app.example/billing"))
        // The home screen read slightly differently when the build came back to it.
        let open = on("home, redrawn", signed(click("Open", outcome: .changed, turn: 3), "app.example/home"))
        #expect(ScoutCompaction.compact([billing, back, open]).count == 3)
        billing.judgement = wrong
        #expect(ScoutCompaction.compact([billing, back, open]).map(\.title) == ["Open"])
        // Signatures that disagree, or say nothing about the screen, don't match.
        let elsewhere = on("home, redrawn", signed(click("Open", outcome: .changed, turn: 3), "app.example/settings"))
        #expect(ScoutCompaction.compact([billing, back, elsewhere]).count == 3)
        let blank = [signed(billing, nil), signed(back, nil), signed(open, nil)]
        #expect(ScoutCompaction.compact(blank).count == 3)
        #expect(
            ScoutCompaction.compact([
                signed(billing, nil, selected: ["home"]), back, signed(open, nil, selected: ["home"])
            ]).map(\.title) == ["Open"])
    }

    @Test("Each compiled action says whether it changed the screen while building")
    func recordsWhetherActionsChangedTheScreen() {
        var typed = click("Search", outcome: .noEffect, turn: 2)
        typed.steps[0].action = .typeText(
            field: DemoElementLocator(role: "AXTextField", label: "Search", labelIsStable: true, rect: rect(0.1, 0.1)),
            text: "rent", submit: false)
        let steps = ScoutCompaction.compact([
            click("Open", outcome: .changed, turn: 1), typed, click("Help", outcome: .contaminated, turn: 3),
            highlight(turn: 4)
        ])
        #expect(steps.map(\.changedScreen) == [true, false, nil, nil])
    }

    @Test("Scrolls joined into one hint keep the real wheel any of them needed")
    func joinedScrollsKeepTheirRoute() {
        func scroll(_ route: DemoStepRoute?, turn: Int) -> ScoutRecord {
            ScoutRecord(
                turn: turn, steps: [], scroll: RevealHint(container: nil, directionDown: true, route: route),
                outcome: .changed, fact: "")
        }
        let steps = ScoutCompaction.compact([
            scroll(.realWheel, turn: 1), scroll(nil, turn: 2), click("Row", outcome: .changed, turn: 3)
        ])
        #expect(steps.first?.reveal?.count == 2)
        #expect(steps.first?.reveal?.route == .realWheel)
    }
}
