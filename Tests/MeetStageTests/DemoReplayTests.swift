import Foundation
import Testing

@testable import MeetStage

@Suite("Demo replay")
@MainActor
struct DemoReplayTests {
    /// Scouts the movie search on a fresh fake app and returns the compiled demo.
    private func recordedDemo() async throws -> RealTimeDemo {
        let app = subtisApp()
        let model = ScriptedModel([
            reply(.typeText(elementID: 1, text: "The Matrix", submit: true, title: "Search The Matrix", script: "")),
            reply(.click(elementID: 2, title: "Open the first result", script: "")),
            reply(.present([ScoutBeat(effect: .spotlight, elementIDs: [0], title: "Show the title", script: "Here it is.")])),
            reply(.finish(title: "Find The Matrix", startDescription: "Subtis home", startLabel: "", closingScript: "")),
        ])
        var limits = fastScoutLimits()
        limits.beatPreview = .milliseconds(1)
        let scout = try DemoScout(
            demo: RealTimeDemo(
                prompt: "Search for The Matrix and open the result",
                app: DemoAppKey(bundleID: "com.example.app", appName: "Example", engine: .chromium, isBrowser: true),
                title: "Demo", status: .draft(ScoutDraft())),
            source: app.demoSource, driver: app, model: model, key: "key", limits: limits, check: {},
            onUpdate: { _, _ in })
        #expect(try await scout.run() == .finished)
        var demo = scout.demo
        demo.steps = ScoutCompaction.compact(demo.draft?.records ?? [])
        demo.status = .recorded
        return demo
    }

    private func engine(
        _ demo: RealTimeDemo, _ app: FakeApp, mode: ReplayMode = .present, singleStep: Bool = false,
        model: ScriptedModel = ScriptedModel([]), commits: @escaping (Int) -> Void = { _ in }
    ) -> DemoReplayEngine {
        DemoReplayEngine(
            demo: demo, source: app.demoSource, driver: app, model: model, key: { "key" },
            options: .init(mode: mode, singleStep: singleStep, holdOverride: 0.001, gateTimeout: .milliseconds(200)),
            hooks: .init(check: {}, onStep: { _, _ in }, onCommit: commits))
    }

    @Test("Replays every action once, in order, with its highlight")
    func replaysInOrder() async throws {
        let demo = try await recordedDemo()
        let app = subtisApp()
        var commits: [Int] = []
        let end = try await engine(demo, app) { commits.append($0) }.run(from: 0)
        #expect(end == .completed)
        #expect(app.log == ["type The Matrix ⏎", "click The Matrix (1999)"])
        #expect(app.cues.contains { $0?.effect == .spotlight })
        #expect(commits == [1, 2, 3])
    }

    @Test("A replay's timings count each step it ran, with the route of each input and its looks")
    func countsStepTimings() async throws {
        let demo = try await recordedDemo()
        let app = subtisApp()
        let engine = engine(demo, app, mode: .verify)
        #expect(try await engine.run(from: 0) == .completed)
        #expect(engine.timings.turns == 3)
        // Typing and the click; the highlight sends no input.
        #expect(engine.timings.routes == ["accessibility": 2])
        #expect(engine.timings.modelCalls == 0)
        #expect(engine.timings.settle > .zero)
    }

    @Test("Pausing between steps and continuing never repeats an action")
    func resumesWithoutRepeating() async throws {
        let demo = try await recordedDemo()
        let app = subtisApp()
        #expect(try await engine(demo, app, singleStep: true).run(from: 0) == .pausedAfter(0))
        #expect(try await engine(demo, app).run(from: 1) == .completed)
        #expect(app.log == ["type The Matrix ⏎", "click The Matrix (1999)"])
    }

    @Test("A toggle already in its recorded state is not clicked again")
    func togglesAreIdempotent() async throws {
        let app = FakeApp(
            screens: [
                "home": FakeScreen(
                    url: nil,
                    elements: [FakeElement(role: "AXCheckBox", label: "Discreet mode", rect: rect(0.9, 0.05), toggle: true)])
            ], start: "home")
        app.isBrowser = false
        app.engine = .native
        var locator = DemoElementLocator(
            role: "AXCheckBox", label: "Discreet mode", labelIsStable: true, rect: rect(0.9, 0.05))
        locator.toggleValueAfter = true
        let demo = RealTimeDemo(
            prompt: "Discreet mode", app: DemoAppKey(bundleID: "a", appName: "A", engine: .native, isBrowser: false),
            title: "Discreet", start: nil,
            steps: [
                DemoStep(
                    title: "Turn on discreet mode", script: "", holdSeconds: 0.4, action: .click(locator),
                    pre: ScreenSignature(selected: [], headings: [], dialogOpen: false))
            ], status: .recorded)
        #expect(try await engine(demo, app).run(from: 0) == .completed)
        #expect(app.log.isEmpty)
    }

    @Test("A checked demo knows which step's screen the app is on")
    func detectsWrongScreen() async throws {
        let demo = try await recordedDemo()
        let app = subtisApp()
        let verify = engine(demo, app, mode: .verify)
        #expect(try await verify.run(from: 0) == .completed)
        let checked = verify.demo
        let confirmed = checked.steps.allSatisfy { $0.pre.confirmed }
        #expect(confirmed)

        let lost = subtisApp()
        lost.current = "results"
        let end = try await engine(checked, lost).run(from: 0)
        #expect(end == .offTrack(index: 0, .wrongScreen(onStep: 1)))
        #expect(lost.log.isEmpty)
    }

    @Test("In an app the presenter always allows, a covered question the step's approval no longer matches passes")
    func trustedReplayAcceptsCoveredQuestions() async throws {
        let model = ScriptedModel([
            reply(.typeText(elementID: 1, text: "Inception", submit: true, title: "Search", script: "")),
            reply(.finish(title: "Search", startDescription: "Subtis home", startLabel: "", closingScript: "")),
            reply(.finish(title: "Search", startDescription: "Subtis home", startLabel: "", closingScript: ""))
        ])
        let builder = subtisApp()
        let scout = try DemoScout(
            demo: RealTimeDemo(
                prompt: "Show how search works",
                app: DemoAppKey(bundleID: "com.example.app", appName: "Example", engine: .chromium, isBrowser: true),
                title: "Demo", status: .draft(ScoutDraft())),
            source: builder.demoSource, driver: builder, model: model, key: "key", limits: fastScoutLimits(),
            trustsApp: true, check: {}, onUpdate: { _, _ in })
        #expect(try await scout.run() == .finished)
        var demo = scout.demo
        demo.steps = ScoutCompaction.compact(demo.draft?.records ?? [])
        demo.status = .recorded
        // As if the field had another name when the question was approved.
        demo.steps[0].approvedReason = "Type “Inception” into “Buscar”?"

        func run(_ demo: RealTimeDemo, trusted: Bool) async throws -> (ReplayEnd, [String]) {
            let app = subtisApp()
            let engine = DemoReplayEngine(
                demo: demo, source: app.demoSource, driver: app, model: ScriptedModel([]), key: { "key" },
                options: .init(mode: .verify, holdOverride: 0.001, gateTimeout: .milliseconds(200), trustsApp: trusted),
                hooks: .init(check: {}, onStep: { _, _ in }, onCommit: { _ in }))
            return (try await engine.run(from: 0), app.log)
        }
        let blocked = Mismatch.blocked(.policyDenied("Type “Inception” into “Buscar película”?"))
        #expect(try await run(demo, trusted: false) == (.offTrack(index: 0, blocked), []))
        #expect(try await run(demo, trusted: true) == (.completed, ["type Inception ⏎"]))

        // A question trust doesn't cover still stops it.
        var offSite = demo
        offSite.steps[0].action = .navigate(try #require(URL(string: "https://evil.example/")))
        let unknown = Mismatch.blocked(.policyDenied("Open evil.example?"))
        #expect(try await run(offSite, trusted: true) == (.offTrack(index: 0, unknown), []))
    }

    @Test("A missing highlight is skipped during a live demo instead of stopping it")
    func skipsMissingHighlight() async throws {
        var demo = try await recordedDemo()
        let app = subtisApp()
        app.screens["movie"]!.elements[0].label = "Matrix"
        demo.steps = demo.steps.map { step in
            var step = step
            step.pre.headings = []
            return step
        }
        let replay = engine(demo, app)
        #expect(try await replay.run(from: 0) == .completed)
        #expect(replay.skippedBeats == ["Show the title"])
    }

    @Test("A renamed control on the right screen is healed and the heal is kept after checking")
    func healsRenamedControl() async throws {
        let app = subtisApp()
        let original = DemoElementLocator(role: "AXButton", label: "Buscar", labelIsStable: true, rect: rect(0.72, 0.2))
        let demo = RealTimeDemo(
            prompt: "Search", app: DemoAppKey(bundleID: "a", appName: "A", engine: .chromium, isBrowser: true),
            title: "Search",
            steps: [
                DemoStep(
                    title: "Search", script: "", holdSeconds: 0.4, action: .click(original),
                    pre: ScreenSignature(urlKey: "subtis.io/", selected: [], headings: [], dialogOpen: false))
            ], status: .recorded)
        app.screens["home"]!.elements[2].label = "Search"
        let replay = engine(demo, app, mode: .verify, model: ScriptedModel([], relocations: [[2]]))
        #expect(try await replay.run(from: 0) == .completed)
        #expect(app.log == ["click Search"])
        guard case .click(let healed) = replay.demo.steps[0].action else {
            Issue.record("Expected a click")
            return
        }
        #expect(healed.label == "Search")
    }

    @Test("Finding a moved target sends Claude's note on it, and the healed target keeps the note")
    func healingSendsTheTargetNote() async throws {
        let app = subtisApp()
        var original = DemoElementLocator(role: "AXButton", label: "Buscar", labelIsStable: true, rect: rect(0.72, 0.2))
        original.note = "button right of the search field"
        let demo = RealTimeDemo(
            prompt: "Search", app: DemoAppKey(bundleID: "a", appName: "A", engine: .chromium, isBrowser: true),
            title: "Search",
            steps: [
                DemoStep(
                    title: "Search", script: "", holdSeconds: 0.4, action: .click(original),
                    pre: ScreenSignature(urlKey: "subtis.io/", selected: [], headings: [], dialogOpen: false))
            ], status: .recorded)
        app.screens["home"]?.elements[2].label = "Search"
        let model = ScriptedModel([], relocations: [[2]])
        let replay = engine(demo, app, mode: .verify, model: model)
        #expect(try await replay.run(from: 0) == .completed)
        #expect(model.relocateRequests.map(\.note) == ["button right of the search field"])
        #expect(model.relocateRequests.first?.description.contains("labelled “Buscar”") == true)
        guard case .click(let healed) = replay.demo.steps[0].action else {
            Issue.record("Expected a click")
            return
        }
        #expect(healed.label == "Search")
        #expect(healed.note == "button right of the search field")
    }

    @Test("A control that ignores Accessibility's press is clicked for real, then and on every replay")
    func pointerOnlyControls() async throws {
        func app() -> FakeApp {
            let home = FakeScreen(
                url: "https://subtis.io/",
                elements: [
                    FakeElement(
                        role: "AXLink", label: "Buscar película", rect: rect(0.7, 0.06), opens: "search", pointerOnly: true)
                ])
            let search = FakeScreen(
                url: "https://subtis.io/",
                elements: [FakeElement(role: "AXTextField", label: "Buscar película", rect: rect(0.3, 0.3, 0.4), placeholder: "Buscar película")],
                dialogOpen: true)
            return FakeApp(screens: ["home": home, "search": search], start: "home")
        }
        let scouted = app()
        let model = ScriptedModel([
            reply(.click(elementID: 0, title: "Open search", script: "")),
            reply(.finish(title: "Search", startDescription: "Subtis home", startLabel: "", closingScript: "")),
        ])
        var limits = fastScoutLimits()
        limits.beatPreview = .milliseconds(1)
        let scout = try DemoScout(
            demo: RealTimeDemo(
                prompt: "Open search", app: DemoAppKey(bundleID: "a", appName: "Dia", engine: .chromium, isBrowser: true),
                title: "Search", status: .draft(ScoutDraft())),
            source: scouted.demoSource, driver: scouted, model: model, key: "key", limits: limits, check: {},
            onUpdate: { _, _ in })
        #expect(try await scout.run() == .finished)
        #expect(scouted.log == ["press Buscar película (ignored)", "click Buscar película"])
        var demo = scout.demo
        demo.steps = ScoutCompaction.compact(demo.draft?.records ?? [])
        demo.status = .recorded
        #expect(demo.steps.first?.route == .pointer)
        #expect(model.facts[1].last?.contains("needed a real click") == true)

        let replayed = app()
        #expect(try await engine(demo, replayed).run(from: 0) == .completed)
        #expect(replayed.log == ["click Buscar película"])
        let tested = app()
        #expect(try await engine(demo, tested, mode: .verify).run(from: 0) == .completed)
        #expect(tested.log == ["click Buscar película"])
    }

    /// Builds a demo of one click on a control that ignores Accessibility's press, in a browser that runs page scripts.
    private func buildClick(on control: FakeElement, model: ScriptedModel) async throws -> (RealTimeDemo, FakeApp) {
        func app() -> FakeApp {
            let home = FakeScreen(url: "https://subtis.io/", elements: [control])
            let search = FakeScreen(url: "https://subtis.io/", elements: [], dialogOpen: true)
            let app = FakeApp(screens: ["home": home, "search": search], start: "home")
            app.runsPageScripts = true
            return app
        }
        let scouted = app()
        var limits = fastScoutLimits()
        limits.beatPreview = .milliseconds(1)
        let scout = try DemoScout(
            demo: RealTimeDemo(
                prompt: "Open search",
                app: DemoAppKey(bundleID: "a", appName: "Dia", engine: .chromium, isBrowser: true), title: "Search",
                status: .draft(ScoutDraft())),
            source: scouted.demoSource, driver: scouted, model: model, key: "key", limits: limits, check: {},
            onUpdate: { _, _ in })
        #expect(try await scout.run() == .finished)
        var demo = scout.demo
        demo.steps = ScoutCompaction.compact(demo.draft?.records ?? [])
        demo.status = .recorded
        return (demo, scouted)
    }

    @Test("A press with no effect in a scriptable page is retried with the page's click before a real one")
    func pageClickRetry() async throws {
        let control = FakeElement(
            role: "AXLink", label: "Buscar", rect: rect(0.7, 0.06), opens: "search", ignoresPress: true)
        let model = ScriptedModel([
            reply(.click(elementID: 0, title: "Open search", script: "")),
            reply(.finish(title: "Search", startDescription: "Subtis home", startLabel: "", closingScript: ""))
        ])
        let (demo, scouted) = try await buildClick(on: control, model: model)
        #expect(scouted.log == ["press Buscar (ignored)", "page click Buscar"])
        #expect(demo.steps.first?.route == .pageScript)
        #expect(model.facts[1].last?.contains("needed the page’s own click") == true)

        func app(pageScripts: Bool) -> FakeApp {
            let app = FakeApp(
                screens: [
                    "home": FakeScreen(url: "https://subtis.io/", elements: [control]),
                    "search": FakeScreen(url: "https://subtis.io/", elements: [], dialogOpen: true)
                ], start: "home")
            app.runsPageScripts = pageScripts
            return app
        }
        // Testing starts from the page's click, and gets a real click where page scripts can't run.
        let tested = app(pageScripts: true)
        #expect(try await engine(demo, tested, mode: .verify).run(from: 0) == .completed)
        #expect(tested.log == ["page click Buscar"])
        let withoutScripts = app(pageScripts: false)
        #expect(try await engine(demo, withoutScripts, mode: .verify).run(from: 0) == .completed)
        #expect(withoutScripts.log == ["click Buscar"])
        // Playing keeps real input with the app in front.
        let played = app(pageScripts: true)
        #expect(try await engine(demo, played).run(from: 0) == .completed)
        #expect(played.log == ["click Buscar"])
    }

    @Test("A control the page's click doesn't move either gets a real click, and replay goes straight to one")
    func realClickAfterPageClick() async throws {
        let control = FakeElement(
            role: "AXLink", label: "Buscar", rect: rect(0.7, 0.06), opens: "search", pointerOnly: true)
        let model = ScriptedModel([
            reply(.click(elementID: 0, title: "Open search", script: "")),
            reply(.finish(title: "Search", startDescription: "Subtis home", startLabel: "", closingScript: ""))
        ])
        let (demo, scouted) = try await buildClick(on: control, model: model)
        #expect(scouted.log == ["press Buscar (ignored)", "page click Buscar (ignored)", "click Buscar"])
        #expect(demo.steps.first?.route == .pointer)
        #expect(model.facts[1].last?.contains("needed a real click") == true)

        let tested = FakeApp(
            screens: [
                "home": FakeScreen(url: "https://subtis.io/", elements: [control]),
                "search": FakeScreen(url: "https://subtis.io/", elements: [], dialogOpen: true)
            ], start: "home")
        tested.runsPageScripts = true
        #expect(try await engine(demo, tested, mode: .verify).run(from: 0) == .completed)
        #expect(tested.log == ["click Buscar"])
    }

    /// A native app with a sheet that Escape closes.
    private func sheetApp() -> FakeApp {
        let sheet = FakeScreen(
            elements: [FakeElement(role: "AXButton", label: "Done", rect: rect(0.6, 0.5))], dialogOpen: true,
            keyOpens: [.escape: "main"])
        let main = FakeScreen(elements: [FakeElement(role: "AXButton", label: "Share", rect: rect(0.1, 0.1))])
        let app = FakeApp(screens: ["sheet": sheet, "main": main], start: "sheet")
        app.isBrowser = false
        app.engine = .native
        app.accessibilityKeys = [.escape]
        return app
    }

    private func scout(_ app: FakeApp, _ model: ScriptedModel) throws -> DemoScout {
        var limits = fastScoutLimits()
        limits.beatPreview = .milliseconds(1)
        return try DemoScout(
            demo: RealTimeDemo(
                prompt: "Close the sheet",
                app: DemoAppKey(bundleID: "a", appName: "Notes", engine: .native, isBrowser: false), title: "Sheet",
                status: .draft(ScoutDraft())),
            source: app.demoSource, driver: app, model: model, key: "key", limits: limits, check: {},
            onUpdate: { _, _ in })
    }

    @Test("A key Accessibility carries out in an app's own views stays in the background")
    func accessibilityKeys() async throws {
        let app = sheetApp()
        let model = ScriptedModel([
            reply(.press(.escape, title: "Close the sheet", script: "")),
            reply(.finish(title: "Sheet", startDescription: "A sheet", startLabel: "", closingScript: ""))
        ])
        let scout = try scout(app, model)
        #expect(try await scout.run() == .finished)
        #expect(app.log == ["press escape (accessibility)"])
        #expect(ScoutCompaction.compact(scout.demo.draft?.records ?? []).first?.route == .accessibility)
    }

    @Test("A key Accessibility did with nothing to show is retried once with the real key, and replay uses it")
    func realKeyAfterStandIn() async throws {
        let app = sheetApp()
        app.ignoresStandIns = true
        let model = ScriptedModel([
            reply(.press(.escape, title: "Close the sheet", script: "")),
            reply(.finish(title: "Sheet", startDescription: "A sheet", startLabel: "", closingScript: ""))
        ])
        let scout = try scout(app, model)
        #expect(try await scout.run() == .finished)
        #expect(app.log == ["press escape (accessibility, ignored)", "press escape"])
        var demo = scout.demo
        demo.steps = ScoutCompaction.compact(demo.draft?.records ?? [])
        demo.status = .recorded
        #expect(demo.steps.first?.route == .realKey)
        #expect(model.facts[1].last?.contains("needed the real key") == true)

        let tested = sheetApp()
        tested.ignoresStandIns = true
        #expect(try await engine(demo, tested, mode: .verify).run(from: 0) == .completed)
        #expect(tested.log == ["press escape"])
    }

    @Test("A test step handed back before its real key commits resumes at that step, never past it")
    func handedBackStepsResumeThere() async throws {
        let app = sheetApp()
        let model = ScriptedModel([
            reply(.press(.escape, title: "Close the sheet", script: "")),
            reply(.finish(title: "Sheet", startDescription: "A sheet", startLabel: "", closingScript: ""))
        ])
        let scout = try scout(app, model)
        #expect(try await scout.run() == .finished)
        var demo = scout.demo
        demo.steps = ScoutCompaction.compact(demo.draft?.records ?? [])
        demo.status = .recorded

        let tested = sheetApp()
        // The test pauses while the real key waits for the person to stop typing.
        tested.whileHandedBack = { throw CancellationError() }
        var commits: [Int] = []
        let engine = engine(demo, tested, mode: .verify) { commits.append($0) }
        do {
            _ = try await engine.run(from: 0)
            Issue.record("Expected the run to pause")
        } catch is CancellationError {}
        #expect(commits == [1, 0])
        #expect(tested.log == ["press escape (accessibility, unavailable)"])
    }

    @Test("A real key with no effect isn't retried")
    func realKeyNotRetried() async throws {
        let app = sheetApp()
        app.accessibilityKeys = []
        app.screens["sheet"]?.keyOpens = [:]
        let model = ScriptedModel([
            reply(.press(.escape, title: "Close the sheet", script: "")),
            reply(.blocked(reason: "The sheet stays open.", alternative: ""))
        ])
        let scout = try scout(app, model)
        #expect(try await scout.run() == .stopped(.blocked(reason: "The sheet stays open.", alternative: "")))
        #expect(app.log == ["press escape"])
        #expect(model.facts[1].last?.contains("no visible change") == true)
    }

    @Test("Scrolling Accessibility did with nothing moving is retried with the real wheel, and replay uses it")
    func realWheelAfterStandIn() async throws {
        // Nothing sits just past the fold, so the scout scrolls the list itself rather than an element into view.
        func app() -> FakeApp {
            let list = FakeScreen(
                elements: [
                    FakeElement(role: "AXStaticText", label: "Recent", rect: rect(0.1, 0.1, 0.3)),
                    FakeElement(role: "AXRow", label: "March invoice", rect: rect(0.1, 0.95, 0.6))
                ], viewport: NormRect(x: 0, y: 0, w: 1, h: 0.9))
            let app = FakeApp(screens: ["list": list], start: "list")
            app.isBrowser = false
            app.engine = .native
            app.accessibilityScrolls = true
            app.ignoresStandIns = true
            return app
        }
        let scouted = app()
        let model = ScriptedModel([
            reply(.scroll(containerID: nil, down: true)),
            reply(.present([ScoutBeat(effect: .spotlight, elementIDs: [1], title: "The invoice", script: "")])),
            reply(.finish(title: "Invoice", startDescription: "The list", startLabel: "", closingScript: ""))
        ])
        let scout = try scout(scouted, model)
        #expect(try await scout.run() == .finished)
        #expect(scouted.log == ["scroll down (accessibility, ignored)", "scroll down"])
        #expect(scout.demo.draft?.records.first?.scroll?.route == .realWheel)
        #expect(model.facts[1].last?.contains("needed real scrolling") == true)
        var demo = scout.demo
        demo.steps = ScoutCompaction.compact(demo.draft?.records ?? [])
        demo.status = .recorded
        #expect(demo.steps.first?.reveal?.route == .realWheel)

        let tested = app()
        #expect(try await engine(demo, tested, mode: .verify).run(from: 0) == .completed)
        #expect(tested.log == ["scroll down"])
    }

    @Test("Return to start opens the start page in the same tab without a model")
    func returnsToStart() async throws {
        let demo = try await recordedDemo()
        let app = subtisApp()
        app.current = "movie"
        let model = ScriptedModel([])
        #expect(try await engine(demo, app, model: model).returnToStart() == nil)
        #expect(app.current == "home")
        #expect(app.log == ["open https://subtis.io/"])
        #expect(model.requests.isEmpty)
    }

    @Test("A step waits out a spinner the last step started, never one already there, and never fails for one")
    func gateWaitsWhileBusy() async throws {
        let demo = try await recordedDemo()
        /// Replays with the app busy for `looks` after the search is typed, or all along.
        func replay(busyAfterTyping looks: Int, busyAllAlong: Bool = false) async throws -> (
            end: ReplayEnd, busyAtClick: Int, looksBeforeClick: Int
        ) {
            let app = subtisApp()
            if busyAllAlong { app.busyLooks = .max }
            var busyAtClick = -1
            var typedAt = 0
            var clickedAt = 0
            app.beforeInput = { input in
                switch input {
                case .type:
                    if !busyAllAlong { app.busyLooks = looks }
                    typedAt = app.generation
                case .click:
                    busyAtClick = app.busyLooks
                    clickedAt = app.generation
                default:
                    break
                }
            }
            let engine = DemoReplayEngine(
                demo: demo, source: app.demoSource, driver: app, model: ScriptedModel([]), key: { "key" },
                options: .init(mode: .verify, holdOverride: 0.001, gateTimeout: .seconds(1)),
                hooks: .init(check: {}, onStep: { _, _ in }, onCommit: { _ in }))
            return (try await engine.run(from: 0), busyAtClick, clickedAt - typedAt)
        }

        // The result is clicked only once the spinner the search started is gone.
        let waited = try await replay(busyAfterTyping: 3)
        #expect(waited.end == .completed)
        #expect(waited.busyAtClick == 0)

        // A spinner showing since before the search never holds the click up.
        let persistent = try await replay(busyAfterTyping: 0, busyAllAlong: true)
        #expect(persistent.end == .completed)
        #expect(persistent.looksBeforeClick == 2)

        // One that never stops holds it for half the gate's time, then the step goes on.
        let endless = try await replay(busyAfterTyping: .max)
        #expect(endless.end == .completed)
        #expect(endless.busyAtClick > 0)
        #expect(endless.looksBeforeClick > 2)
    }

    @Test("A new engine takes its first look as the last step's, so a spinner already there never holds it up")
    func freshEnginesIgnoreStandingSpinners() async throws {
        let demo = try await recordedDemo()
        // Playing on from the result, as Next Step or a resume does, in an app whose spinner never stops.
        let app = subtisApp()
        app.current = "results"
        app.busyLooks = .max
        var clickedAt = 0
        app.beforeInput = { input in
            if case .click = input { clickedAt = app.generation }
        }
        let engine = DemoReplayEngine(
            demo: demo, source: app.demoSource, driver: app, model: ScriptedModel([]), key: { "key" },
            options: .init(mode: .present, holdOverride: 0.001, gateTimeout: .seconds(2)),
            hooks: .init(check: {}, onStep: { _, _ in }, onCommit: { _ in }))
        #expect(try await engine.run(from: 1) == .completed)
        // Two looks that agree, with no wait for the spinner.
        #expect(clickedAt == 2)
    }

    @Test("A demo saved when an icon button had no name still plays once the button borrows one")
    func oldDemosFindBorrowedNames() async throws {
        func app(named: Bool) -> FakeApp {
            let app = FakeApp(
                screens: [
                    "home": FakeScreen(
                        url: nil,
                        elements: [
                            FakeElement(
                                role: "AXButton", label: named ? "Settings" : "", rect: rect(0.9, 0.05, 0.03, 0.04),
                                opens: "settings", borrowsLabel: named)
                        ]),
                    "settings": FakeScreen(
                        url: nil, elements: [FakeElement(role: "AXHeading", label: "Settings", rect: rect(0.1, 0.05))])
                ], start: "home")
            app.isBrowser = false
            app.engine = .native
            return app
        }
        // Recorded on the unnamed button, by where it sat, with the unlabelled question approved.
        let saved = app(named: false)
        let locator = try #require(
            DemoLocatorFactory.locator(for: 0, in: try await saved.snapshot(saved.demoSource, waitForContent: false)))
        #expect(locator.label.isEmpty)
        let demo = RealTimeDemo(
            prompt: "Open settings", app: DemoAppKey(bundleID: "a", appName: "A", engine: .native, isBrowser: false),
            title: "Settings", start: nil,
            steps: [
                DemoStep(
                    title: "Open settings", script: "", holdSeconds: 0.4, action: .click(locator),
                    pre: ScreenSignature(selected: [], headings: [], dialogOpen: false), approved: true,
                    approvedReason: "Click an unlabelled control?")
            ], status: .recorded)

        let live = app(named: true)
        #expect(try await engine(demo, live, mode: .verify).run(from: 0) == .completed)
        #expect(live.log == ["click Settings"])
    }
}

extension DemoReplayTests {
    /// A page whose control opens a details page, and a tested-looking demo that
    /// clicks it, then highlights the details.
    private func detailsDemo(
        _ control: FakeElement, changedScreen: Bool? = true, approved: Bool = false
    ) -> (demo: RealTimeDemo, app: (Bool) -> FakeApp) {
        func app(pageScripts: Bool) -> FakeApp {
            let app = FakeApp(
                screens: [
                    "home": FakeScreen(url: "https://example.com/", elements: [control]),
                    "details": FakeScreen(
                        url: "https://example.com/details",
                        elements: [FakeElement(role: "AXHeading", label: "Details", rect: rect(0.1, 0.1))])
                ], start: "home")
            app.runsPageScripts = pageScripts
            return app
        }
        var click = DemoStep(
            title: "Open details", script: "", holdSeconds: 0.4,
            action: .click(
                DemoElementLocator(
                    role: control.role, subrole: control.subrole, label: control.label, labelIsStable: true,
                    rect: control.rect)),
            pre: ScreenSignature(urlKey: "example.com/", selected: [], headings: [], dialogOpen: false),
            approved: approved)
        click.changedScreen = changedScreen
        let highlight = DemoStep(
            title: "The details", script: "", holdSeconds: 1.6,
            action: .present(
                DemoBeat(
                    effect: .spotlight,
                    targets: [
                        DemoElementLocator(
                            role: "AXHeading", label: "Details", labelIsStable: true, rect: rect(0.1, 0.1))
                    ])),
            pre: ScreenSignature(urlKey: "example.com/details", selected: [], headings: [], dialogOpen: false))
        let demo = RealTimeDemo(
            prompt: "Open the details",
            app: DemoAppKey(bundleID: "a", appName: "A", engine: .chromium, isBrowser: true),
            title: "Details", steps: [click, highlight], status: .recorded)
        return (demo, app)
    }

    private func checking(
        _ demo: RealTimeDemo, _ app: FakeApp, mode: ReplayMode = .verify, gateTimeout: Duration = .milliseconds(200)
    ) -> DemoReplayEngine {
        DemoReplayEngine(
            demo: demo, source: app.demoSource, driver: app, model: ScriptedModel([]), key: { "key" },
            options: .init(
                mode: mode, holdOverride: 0.001, gateTimeout: gateTimeout, effectWindow: .milliseconds(40)),
            hooks: .init(check: {}, onStep: { _, _ in }, onCommit: { _ in }))
    }

    @Test("Testing clicks a press that showed nothing once more on the next route, and keeps that route once it passes")
    func testingClicksSilentPressesAgain() async throws {
        let (demo, makeApp) = detailsDemo(
            FakeElement(
                role: "AXButton", label: "Open details", rect: rect(0.1, 0.1), opens: "details", ignoresPress: true))

        // The page's own click first, where page scripts run, and a real click where they can't.
        let scripted = makeApp(true)
        let tested = checking(demo, scripted)
        #expect(try await tested.run(from: 0) == .completed)
        #expect(scripted.log == ["press Open details (ignored)", "page click Open details"])
        #expect(tested.demo.steps[0].route == .pageScript)
        #expect(tested.timings.routes == ["accessibility": 1, "browser": 1])
        let unscripted = makeApp(false)
        let real = checking(demo, unscripted)
        #expect(try await real.run(from: 0) == .completed)
        #expect(unscripted.log == ["press Open details (ignored)", "click Open details"])
        #expect(real.demo.steps[0].route == .pointer)

        // Playing is unchanged: one press, and nothing else tried.
        let played = makeApp(true)
        let end = try await checking(demo, played, mode: .present).run(from: 0)
        #expect(played.log == ["press Open details (ignored)"])
        #expect(end == .completed)
        #expect(played.current == "home")
    }

    @Test("Testing never clicks again after a click that may already have acted")
    func uncertainClicksAreNotRepeated() async throws {
        let (demo, makeApp) = detailsDemo(
            FakeElement(
                role: "AXButton", label: "Open details", rect: rect(0.1, 0.1), opens: "details", ignoresPress: true))
        let app = makeApp(true)
        // Accessibility's press timed out, so the app may still act on it.
        app.accessibilityDelivery = .uncertain
        _ = try await checking(demo, app).run(from: 0)
        #expect(app.log == ["press Open details (ignored)"])
    }

    @Test("A second click that shows nothing isn't followed by a third, and no route is kept")
    func clicksAgainOnlyOnce() async throws {
        let (demo, makeApp) = detailsDemo(
            FakeElement(
                role: "AXButton", label: "Open details", rect: rect(0.1, 0.1), opens: "details", pointerOnly: true))
        let app = makeApp(true)
        let tested = checking(demo, app)
        #expect(try await tested.run(from: 0) == .offTrack(index: 1, .targetNotFound("Details")))
        #expect(app.log == ["press Open details (ignored)", "page click Open details (ignored)"])
        #expect(tested.demo.steps[0].route == .accessibility)
    }

    @Test("An app too slow to show the first click in time gets it at most twice")
    func slowAppsGetAtMostTwoClicks() async throws {
        let (demo, makeApp) = detailsDemo(
            FakeElement(role: "AXButton", label: "Open details", rect: rect(0.1, 0.1), opens: "details"))
        let app = makeApp(true)
        app.opensAfterLooks = 4
        let tested = checking(demo, app, gateTimeout: .seconds(2))
        #expect(try await tested.run(from: 0) == .completed)
        #expect(app.log == ["click Open details", "page click Open details"])
        // The second click showed nothing in time either, so the step keeps its route.
        #expect(tested.demo.steps[0].route == .accessibility)
    }

    @Test("Never clicked again: switches, controls that save or search, approved steps, and steps built before")
    func someClicksAreNeverRepeated() async throws {
        let cases: [(FakeElement, changedScreen: Bool?, approved: Bool)] = [
            (FakeElement(role: "AXCheckBox", label: "Notifications", rect: rect(0.1, 0.1), toggle: false), true, false),
            (FakeElement(role: "AXButton", label: "Dark mode", rect: rect(0.1, 0.1)), true, false),
            (FakeElement(role: "AXButton", label: "Save", rect: rect(0.1, 0.1)), true, false),
            (FakeElement(role: "AXButton", label: "Add task", rect: rect(0.1, 0.1)), true, false),
            (FakeElement(role: "AXButton", label: "Buscar", rect: rect(0.1, 0.1)), true, false),
            (FakeElement(role: "AXButton", label: "Open details", rect: rect(0.1, 0.1)), true, true),
            (FakeElement(role: "AXButton", label: "Open details", rect: rect(0.1, 0.1)), nil, false),
            (FakeElement(role: "AXButton", label: "Open details", rect: rect(0.1, 0.1)), false, false)
        ]
        for (control, changedScreen, approved) in cases {
            var control = control
            control.opens = "details"
            control.ignoresPress = true
            let (demo, makeApp) = detailsDemo(control, changedScreen: changedScreen, approved: approved)
            let app = makeApp(true)
            _ = try await checking(demo, app).run(from: 0)
            #expect(app.log == ["press \(control.label) (ignored)"], "\(control.label)")
        }
    }

    /// A native app with a sheet whose Close button ignores Accessibility's press, over a main view with a selected Home tab.
    private func sheetOverHome() -> (RealTimeDemo, FakeApp) {
        let sheet = FakeScreen(
            elements: [
                FakeElement(
                    role: "AXButton", label: "Close", rect: rect(0.6, 0.5), opens: "main", ignoresPress: true,
                    inDialog: true)
            ], dialogOpen: true)
        let main = FakeScreen(
            elements: [
                FakeElement(
                    role: "AXRadioButton", label: "Home", rect: rect(0.05, 0.1), subrole: "AXTabButton", selected: true),
                FakeElement(role: "AXButton", label: "Share", rect: rect(0.3, 0.1))
            ])
        let app = FakeApp(screens: ["sheet": sheet, "main": main], start: "sheet")
        app.isBrowser = false
        app.engine = .native
        let home = DemoElementLocator(
            role: "AXRadioButton", subrole: "AXTabButton", label: "Home", labelIsStable: true, rect: rect(0.05, 0.1))
        let share = DemoElementLocator(role: "AXButton", label: "Share", labelIsStable: true, rect: rect(0.3, 0.1))
        let demo = RealTimeDemo(
            prompt: "Share", app: DemoAppKey(bundleID: "a", appName: "Notes", engine: .native, isBrowser: false),
            title: "Share",
            start: DemoStartPoint(
                signature: ScreenSignature(selected: ["home"], headings: [], dialogOpen: false), returnAnchor: home,
                toggles: [], description: "Home", sizeClass: .regular),
            steps: [
                DemoStep(
                    title: "Share", script: "", holdSeconds: 0.4, action: .click(share),
                    pre: ScreenSignature(selected: ["home"], headings: [], dialogOpen: false))
            ], status: .recorded)
        return (demo, app)
    }

    @Test("Going back to the start in the background clicks a close button that showed nothing once more")
    func backgroundReturnClicksAgain() async throws {
        let (demo, background) = sheetOverHome()
        #expect(try await checking(demo, background, mode: .present).returnToStart(inBackground: true) == nil)
        // The Home tab was already selected, so it showing nothing never brings a second click.
        #expect(background.log == ["press Close (ignored)", "click Close", "click Home"])

        // Going back to play drives the app in front, as playing does, so nothing is clicked twice.
        let (_, foreground) = sheetOverHome()
        _ = try await checking(demo, foreground, mode: .present).returnToStart()
        #expect(foreground.log.first == "press Close (ignored)")
        #expect(!foreground.log.contains("click Close"))
    }
}
