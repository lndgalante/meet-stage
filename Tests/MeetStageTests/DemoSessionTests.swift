import Foundation
import Testing

@testable import MeetStage

private struct TestKeyStore: DemoKeyStore {
    var key: String? { "test-key" }
    var hasKey: Bool { true }
    func save(_ value: String) -> Bool { true }
}

@Suite("Demo session")
@MainActor
struct DemoSessionTests {
    private func defaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: "demo-session-tests-\(UUID().uuidString)")!
        defaults.set(true, forKey: DemoSession.consentKey)
        return defaults
    }

    private func searchModel() -> ScriptedModel {
        ScriptedModel([
            reply(.typeText(elementID: 1, text: "The Matrix", submit: true, title: "Search The Matrix", script: "")),
            reply(.click(elementID: 2, title: "Open the first result", script: "")),
            reply(
                .present([
                    ScoutBeat(effect: .draw, elementIDs: [2], title: "Point at download", script: "Grab it here.")
                ])),
            reply(.finish(title: "Find The Matrix", startDescription: "Subtis home", startLabel: "", closingScript: ""))
        ])
    }

    private func session(_ app: FakeApp, _ model: ScriptedModel, _ defaults: UserDefaults) -> DemoSession {
        var limits = fastScoutLimits()
        limits.beatPreview = .milliseconds(1)
        let session = DemoSession(
            driver: app, defaults: defaults, model: model, keyStore: TestKeyStore(), observesUserInput: false,
            scoutLimits: limits, opensWindows: false)
        session.replayTuning = (0.001, .milliseconds(300))
        return session
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<1_000 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting")
    }

    @Test("Build explores the app, returns to the start, checks the demo and leaves it ready to play")
    func buildCheckPlay() async throws {
        let app = subtisApp()
        let defaults = defaults()
        let session = session(app, searchModel(), defaults)
        session.prompt = "Search for The Matrix and open the result"
        session.build()
        #expect(session.phase == .scouting)

        try await waitUntil { session.phase == .ready && !session.isWritingScript }
        #expect(session.isChecked)
        #expect(app.current == "home")
        let pass = ["type The Matrix ⏎", "click The Matrix (1999)", "open https://subtis.io/"]
        #expect(app.log == pass + pass)
        // The script written during the check is kept, and words don't undo the check.
        #expect(session.demo?.openingScript == "Let's find a movie.")
        #expect(session.demo?.steps.first?.title == "Polished Search The Matrix")
        #expect(session.demo?.closingScript == "That's the whole flow.")

        session.play()
        try await waitUntil { session.phase == .finished }
        #expect(app.log == pass + pass + Array(pass.prefix(2)))

        let relaunched = self.session(app, ScriptedModel([]), defaults)
        #expect(relaunched.phase == .ready)
        #expect(relaunched.demo?.steps.count == 3)
    }

    @Test("Play brings the app to the front; building and testing leave it in the background")
    func playBringsAppForward() async throws {
        let app = subtisApp()
        let session = session(app, searchModel(), defaults())
        session.prompt = "Search for The Matrix and open the result"
        session.build()
        try await waitUntil { session.phase == .ready && !session.isWritingScript }
        #expect(app.broughtToFront == 0)
        session.play()
        try await waitUntil { app.broughtToFront > 0 }
        try await waitUntil { session.phase == .finished }
    }

    @Test("A finished presentation keeps its last highlight for a moment, then fades it")
    func finalHighlightFades() async throws {
        let app = subtisApp()
        let session = session(app, searchModel(), defaults())
        session.finalCueHold = .milliseconds(150)
        session.prompt = "Search for The Matrix and open the result"
        session.build()
        try await waitUntil { session.phase == .ready && !session.isWritingScript }
        session.play()
        try await waitUntil { session.phase == .finished }
        // The last step's highlight is still up when the demo finishes.
        #expect(app.cues.last.flatMap { $0 } != nil)
        let shown = app.cues.count
        try await waitUntil { app.cues.count > shown }
        #expect(app.cues.last == .some(nil))
    }

    @Test("Play from the wrong screen goes back to the start first, then performs from the top")
    func playReturnsToStartFirst() async throws {
        let app = subtisApp()
        let session = session(app, searchModel(), defaults())
        session.prompt = "Search for The Matrix and open the result"
        session.build()
        try await waitUntil { session.phase == .ready && !session.isWritingScript }
        app.current = "movie"
        app.log = []
        session.play()
        try await waitUntil { session.phase == .finished }
        #expect(app.log == ["open https://subtis.io/", "type The Matrix ⏎", "click The Matrix (1999)"])
    }

    @Test("Previous Step goes back to the start, quietly replays the actions before it, and presents it again")
    func previousStepRewinds() async throws {
        let app = subtisApp()
        let session = session(app, searchModel(), defaults())
        session.prompt = "Search for The Matrix and open the result"
        session.build()
        try await waitUntil { session.phase == .ready && !session.isWritingScript }
        session.replayTuning = (2, .milliseconds(300))
        session.play()
        try await waitUntil { session.phase.currentStep == 2 }
        app.log = []

        session.previousStep()
        try await waitUntil { app.log.count == 3 }
        #expect(session.phase.currentStep == 1)
        #expect(session.prompter.line == .step(1))
        #expect(app.log == ["open https://subtis.io/", "type The Matrix ⏎", "click The Matrix (1999)"])
        session.pause()
    }

    @Test("A check paused partway continues where it stopped and still ends checked")
    func resumesPausedCheck() async throws {
        let app = subtisApp()
        let session = session(app, searchModel(), defaults())
        var inputs = 0
        app.beforeInput = { input in
            inputs += 1
            // Inputs: scout type, scout click, return to start, check type, check click.
            if inputs == 5 { session.pause() }
        }
        session.prompt = "Search for The Matrix and open the result"
        session.build()
        try await waitUntil { if case .paused(.verify, _, _, _) = session.phase { true } else { false } }
        #expect(session.phase.nextStep == 1)
        session.play()
        try await waitUntil { session.phase == .ready }
        #expect(session.isChecked)
    }

    @Test("Stopping a build keeps its steps; a relaunch offers to keep building")
    func stopAndRelaunch() async throws {
        let app = subtisApp()
        let defaults = defaults()
        let model = ScriptedModel([
            reply(.typeText(elementID: 1, text: "The Matrix", submit: true, title: "Search The Matrix", script: ""))
        ])
        let session = session(app, model, defaults)
        session.prompt = "Search for The Matrix"
        app.beforeInput = { _ in session.pause() }
        session.build()
        try await waitUntil { if case .scoutPaused = session.phase { true } else { false } }
        #expect(session.phase == .scoutPaused(.user))

        let relaunched = self.session(app, ScriptedModel([]), defaults)
        if case .scoutPaused = relaunched.phase {
        } else if relaunched.phase != .composing {
            Issue.record("Unexpected phase \(relaunched.phase)")
        }
        #expect(relaunched.prompt == "Search for The Matrix")
    }

    @Test("An app keeps several demos: open one, start another, cancel back, delete one")
    func severalDemosPerApp() async throws {
        let app = subtisApp()
        let defaults = defaults()
        let builder = session(app, searchModel(), defaults)
        builder.prompt = "Search for The Matrix and open the result"
        builder.build()
        try await waitUntil { builder.phase == .ready && !builder.isWritingScript }
        let first = try #require(builder.demo)
        var second = first
        second.id = UUID()
        second.title = "Second tour"
        second.openingScript = "Welcome to the second tour."
        second.steps[0].title = "Open the second tour"
        var library = DemoLibrary(defaults: defaults)
        library.save(second)

        let session = self.session(app, ScriptedModel([]), defaults)
        #expect(session.savedDemos.map(\.id) == [first.id, second.id])
        // The demo open last time comes back, not the newest.
        #expect(session.demo?.id == first.id)

        session.openDemo(second.id)
        #expect(session.demo?.title == "Second tour")
        #expect(session.phase == .ready)
        // Ready to ready keeps the phase, but the teleprompter still shows the new demo.
        #expect(session.prompter.upNext == "Open the second tour")

        session.newDemo()
        #expect(session.phase == .composing)
        #expect(session.demo == nil)
        #expect(session.prompt.isEmpty)
        #expect(session.savedDemos.count == 2)
        // Again while composing keeps the request and the demo to go back to.
        session.prompt = "Show the download history"
        session.newDemo()
        #expect(session.prompt == "Show the download history")
        session.cancelNewDemo()
        #expect(session.demo?.id == second.id)

        session.deleteDemo(second.id)
        #expect(session.savedDemos.map(\.id) == [first.id])
        #expect(session.demo?.id == first.id)
        #expect(session.phase == .ready)

        session.deleteDemo(first.id)
        #expect(session.savedDemos.isEmpty)
        #expect(session.phase == .composing)
    }

    @Test("A new demo's request survives a relaunch, and Cancel goes back to the demo before it")
    func newDemoDraftSurvives() async throws {
        let app = subtisApp()
        let defaults = defaults()
        let builder = session(app, searchModel(), defaults)
        builder.prompt = "Search for The Matrix and open the result"
        builder.build()
        try await waitUntil { builder.phase == .ready && !builder.isWritingScript }
        let built = try #require(builder.demo)

        builder.newDemo()
        builder.prompt = "Show the download history"
        let relaunched = session(app, ScriptedModel([]), defaults)
        #expect(relaunched.phase == .composing)
        #expect(relaunched.demo == nil)
        #expect(relaunched.prompt == "Show the download history")

        relaunched.cancelNewDemo()
        #expect(relaunched.demo?.id == built.id)
        #expect(relaunched.phase == .ready)
    }

    @Test("With Claude access, the request field offers ideas from the app's own features")
    func offersIdeas() async throws {
        let session = session(subtisApp(), ScriptedModel([]), defaults())
        try await waitUntil { session.ideas.count == 3 }
        #expect(session.ideas.first?.label == "Movie search")
        #expect(!session.isFindingIdeas)

        let noAccess = UserDefaults(suiteName: "demo-ideas-\(UUID().uuidString)")!
        let withoutConsent = self.session(subtisApp(), ScriptedModel([]), noAccess)
        try await Task.sleep(for: .milliseconds(100))
        #expect(withoutConsent.ideas.isEmpty)
    }

    @Test("Editing a line keeps the demo tested and times the step to the new line")
    func editingKeepsTheTest() async throws {
        let app = subtisApp()
        let session = session(app, searchModel(), defaults())
        session.prompt = "Search for The Matrix and open the result"
        session.build()
        try await waitUntil { session.phase == .ready && !session.isWritingScript }
        var edited = try #require(session.demo)
        let line = "Type the movie you want, and Subtis finds it as you go, with every subtitle it knows about."
        edited.steps[0].script = line
        edited.openingScript = "Here's the fastest way to a subtitle."
        #expect(session.updateDemo(edited))
        #expect(session.isChecked)
        #expect(session.demo?.openingScript == "Here's the fastest way to a subtitle.")
        #expect(session.demo?.steps[0].holdSeconds == DemoStep.hold(for: line, action: edited.steps[0].action))
    }

    @Test("Renaming keeps the phase and the test, and survives a relaunch")
    func renameKeepsPhaseAndTest() async throws {
        let app = subtisApp()
        let defaults = defaults()
        let session = session(app, searchModel(), defaults)
        session.prompt = "Search for The Matrix and open the result"
        session.build()
        try await waitUntil { session.phase == .ready && !session.isWritingScript }
        session.play()
        try await waitUntil { session.phase == .finished }

        session.renameDemo(to: "  Find a subtitle  ")
        #expect(session.demo?.title == "Find a subtitle")
        #expect(session.phase == .finished)
        #expect(session.isChecked)
        session.renameDemo(to: "   ")
        #expect(session.demo?.title == "Find a subtitle")

        let relaunched = self.session(app, ScriptedModel([]), defaults)
        #expect(relaunched.demo?.title == "Find a subtitle")
        #expect(relaunched.isChecked)
    }

    @Test("Claude's start label lands unless the presenter edited it meanwhile")
    func scriptStartLabel() async throws {
        let app = subtisApp()
        let model = searchModel()
        let session = session(app, model, defaults())
        session.prompt = "Search for The Matrix and open the result"
        session.build()
        try await waitUntil { session.phase == .ready && !session.isWritingScript }
        #expect(session.demo?.start?.label == "the search page")
        #expect(session.demo?.startLabel == "the search page")

        model.scriptDelay = .milliseconds(200)
        session.rewriteScript()
        var edited = try #require(session.demo)
        edited.start?.label = "  Subtis home "
        #expect(session.updateDemo(edited))
        try await waitUntil { !session.isWritingScript }
        #expect(session.demo?.start?.label == "Subtis home")
        #expect(session.isChecked)
    }

    @Test("Demos saved before start labels still load")
    func decodesDemoWithoutStartLabel() throws {
        let locator = DemoElementLocator(
            role: "AXButton", label: "Buscar", labelIsStable: true, rect: rect(0.72, 0.2))
        let signature = ScreenSignature(urlKey: "subtis.io/", selected: [], headings: ["Subtis"], dialogOpen: false)
        let demo = RealTimeDemo(
            prompt: "Search",
            app: DemoAppKey(bundleID: "com.example.app", appName: "Example", engine: .chromium, isBrowser: true),
            title: "Search",
            start: DemoStartPoint(
                signature: signature, url: URL(string: "https://subtis.io/"), toggles: [],
                description: "Subtis home, with the search field empty", label: "Subtis home", sizeClass: .regular),
            steps: [DemoStep(title: "Search", script: "", holdSeconds: 1, action: .click(locator), pre: signature)],
            status: .recorded)
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(demo)) as? [String: Any])
        var start = try #require(json["start"] as? [String: Any])
        #expect(start.removeValue(forKey: "label") != nil)
        json["start"] = start

        let saved = try JSONDecoder().decode(RealTimeDemo.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(saved.start?.label == nil)
        #expect(saved.startLabel == "Subtis home")
        #expect(
            DemoFingerprint.make(saved, appVersion: "1", sizeClass: .regular)
                == DemoFingerprint.make(demo, appVersion: "1", sizeClass: .regular))
    }

    @Test("Without a label, the start label is the first clause of the description")
    func startLabelFallback() {
        func label(_ description: String, label: String? = nil) -> String {
            let signature = ScreenSignature(urlKey: nil, selected: [], headings: [], dialogOpen: false)
            return RealTimeDemo(
                prompt: "", app: DemoAppKey(bundleID: "", appName: "ChatGPT", engine: .native, isBrowser: false),
                title: "Demo",
                start: DemoStartPoint(
                    signature: signature, toggles: [], description: description, label: label, sizeClass: .regular),
                status: .recorded
            ).startLabel
        }
        #expect(
            label(
                "ChatGPT desktop app on the Scheduled page, with no scheduled tasks listed and the New task button visible in the sidebar."
            ) == "the Scheduled page")
        #expect(label("Inbox with no filters applied.") == "Inbox")
        #expect(label("The Home screen.") == "The Home screen")
        #expect(label("Settings window on the General tab", label: " Settings ") == "Settings")
        #expect(label("", label: "") == "the starting screen")
        #expect(label("Supercalifragilisticexpialidocious-dashboard-overview-page") == "the starting screen")
    }

    @Test("Claude access is asked once, on first open, for every app, before touching any")
    func asksForConsentOnce() async throws {
        let app = subtisApp()
        let defaults = UserDefaults(suiteName: "demo-session-consent-\(UUID().uuidString)")!
        let session = session(app, searchModel(), defaults)
        #expect(session.asksForConsent)
        session.cancelBuildSetup()
        #expect(!session.asksForConsent)

        session.prompt = "Search for The Matrix"
        session.build()
        #expect(session.buildSetup == .consent)
        #expect(session.asksForConsent)
        #expect(session.phase == .composing)
        #expect(app.log.isEmpty)

        session.allowClaude()
        #expect(session.phase == .scouting)
        session.pause()
        let relaunched = self.session(app, ScriptedModel([]), defaults)
        #expect(!relaunched.asksForConsent)
    }
}
