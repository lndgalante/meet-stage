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
            reply(.finish(title: "Find The Matrix", startDescription: "Subtis home", closingScript: "")),
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
            reply(.finish(title: "Search", startDescription: "Subtis home", closingScript: "")),
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
        #expect(demo.steps.first?.usesPointer == true)
        #expect(model.facts[1].last?.contains("needed a real click") == true)

        let replayed = app()
        #expect(try await engine(demo, replayed).run(from: 0) == .completed)
        #expect(replayed.log == ["click Buscar película"])
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
}
