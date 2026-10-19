import AppKit
import Combine
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
        ScriptedModel(searchModelReplies)
    }

    private var searchModelReplies: [Result<ScoutReply, Error>] {
        [
            reply(.typeText(elementID: 1, text: "The Matrix", submit: true, title: "Search The Matrix", script: "")),
            reply(.click(elementID: 2, title: "Open the first result", script: "")),
            reply(
                .present([
                    ScoutBeat(effect: .draw, elementIDs: [2], title: "Point at download", script: "Grab it here.")
                ])),
            reply(.finish(title: "Find The Matrix", startDescription: "Subtis home", startLabel: "", closingScript: ""))
        ]
    }

    private func session(
        _ app: FakeApp, _ model: ScriptedModel, _ defaults: UserDefaults, workspace: NotificationCenter = .init()
    ) -> DemoSession {
        var limits = fastScoutLimits()
        limits.beatPreview = .milliseconds(1)
        let session = DemoSession(
            driver: app, defaults: defaults, model: model, keyStore: TestKeyStore(), observesUserInput: false,
            scoutLimits: limits, opensWindows: false, workspaceNotifications: workspace)
        session.replayTuning = (0.001, .milliseconds(300))
        session.isSecureInputOn = { false }
        return session
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<1_000 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting")
    }

    @Test("A click the test run had to click again keeps the route that worked once the test passes")
    func testKeepsTheRouteAClickNeeded() async throws {
        let app = subtisApp()
        app.runsPageScripts = true
        var clicks = 0
        app.beforeInput = { input in
            guard case .click = input else { return }
            clicks += 1
            // Building's press worked; from the test run on, the result ignores Accessibility's press.
            if clicks == 2 { app.screens["results"]?.elements[2].ignoresPress = true }
        }
        let session = session(app, searchModel(), defaults())
        session.prompt = "Search for The Matrix and open the result"
        session.build()
        try await waitUntil { session.phase == .ready && !session.isWritingScript }
        #expect(session.isChecked)
        #expect(
            app.log == [
                "type The Matrix ⏎", "click The Matrix (1999)", "open https://subtis.io/", "type The Matrix ⏎",
                "press The Matrix (1999) (ignored)", "page click The Matrix (1999)", "open https://subtis.io/"
            ])
        #expect(session.demo?.steps.map(\.route) == [.accessibility, .pageScript, .accessibility])
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
        // The draft is kept as the scout made it, so the demo can be compiled again without pruning.
        let compiledFrom = try #require(session.demo?.compiledFrom)
        #expect(ScoutCompaction.compact(compiledFrom).map(\.id) == session.demo?.steps.map(\.id))
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

    @Test("Building and testing drive the window in the background, playing in front, and every run ends it")
    func driveModes() async throws {
        let app = subtisApp()
        let session = session(app, searchModel(), defaults())
        session.prompt = "Search for The Matrix and open the result"
        session.build()
        try await waitUntil { session.phase == .ready && !session.isWritingScript }
        #expect(
            app.driveModes == [
                .background(.building), .background(.returning), .background(.testing), .background(.returning), nil
            ])
        session.play()
        try await waitUntil { session.phase == .finished }
        #expect(app.driveModes.suffix(2) == [.foreground, nil])
    }

    @Test("A step waiting for a pause shows in the panel, and a browser's tip shows once, until the next run")
    func waitingAndTips() async throws {
        let app = subtisApp()
        let defaults = defaults()
        let session = session(app, searchModel(), defaults)
        let tip = DemoBrowserTip(kind: .javaScript, browser: "Example", bundleID: "com.example.app")
        app.onWaitingForPause?(true)
        #expect(!session.isWaitingForPause)
        var waited = false
        app.beforeInput = { _ in
            guard !waited else { return }
            waited = true
            app.onWaitingForPause?(true)
            #expect(session.isWaitingForPause)
            let panel = DemoPanelContent.make(DemoPanelInputs(session: session, stagePaused: false))
            #expect(panel.glyph == .symbol("hourglass", .secondary))
            app.onWaitingForPause?(false)
            app.onBrowserTip?(tip)
        }
        session.prompt = "Search for The Matrix and open the result"
        session.build()
        try await waitUntil { session.phase == .ready && !session.isWritingScript }
        #expect(!session.isWaitingForPause)
        #expect(session.browserTip == tip)
        let ready = DemoPanelContent.make(DemoPanelInputs(session: session, stagePaused: false))
        #expect(ready.subline == .init(text: tip.message, kind: .tip))
        try await waitUntil { defaults.stringArray(forKey: DemoSession.browserTipsKey) == [tip.key] }

        // A new test run puts it away, and the same browser's tip never comes back.
        session.checkAgain()
        #expect(session.browserTip == nil)
        app.beforeInput = { _ in app.onBrowserTip?(tip) }
        try await waitUntil { session.phase == .ready }
        #expect(session.browserTip == nil)
        #expect(defaults.stringArray(forKey: DemoSession.browserTipsKey) == [tip.key])
    }

    @Test("A tip a notice covered is offered again by the next run, and remembered once it shows")
    func coveredTipComesBack() async throws {
        let app = subtisApp()
        let defaults = defaults()
        let session = session(app, searchModel(), defaults)
        session.prompt = "Search for The Matrix and open the result"
        session.build()
        try await waitUntil { session.phase == .ready && !session.isWritingScript }
        let demo = try #require(session.demo)
        let tip = DemoBrowserTip(kind: .javaScript, browser: "Example", bundleID: "com.example.app")

        session.showForTesting(demo, in: .ready, notice: "The test run didn’t reach every step.", browserTip: tip)
        let covered = DemoPanelContent.make(DemoPanelInputs(session: session, stagePaused: false))
        #expect(covered.subline?.kind == .notice)
        try await Task.sleep(for: .milliseconds(50))
        #expect(defaults.stringArray(forKey: DemoSession.browserTipsKey) == nil)

        // The next run puts it away unseen, offers it again, and the ready panel shows it.
        session.checkAgain()
        #expect(session.browserTip == nil)
        app.beforeInput = { _ in app.onBrowserTip?(tip) }
        try await waitUntil { session.phase == .ready }
        #expect(session.browserTip == tip)
        try await waitUntil { defaults.stringArray(forKey: DemoSession.browserTipsKey) == [tip.key] }
    }

    @Test("While building and testing, only keys in the demo window itself pause the run")
    func keysInTheDemoWindow() {
        let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        func inSource(_ input: DemoUserInput, frontmost: Bool = true, background: Bool, focused: Bool) -> Bool {
            input.isInSource(windowID: 42, frame: frame, appIsFrontmost: frontmost, background: background) {
                focused
            }
        }
        let key = DemoUserInput(windowNumber: 0, location: nil, isKey: true, plainKeyCode: 0)
        // Typing in another window of the same browser while it builds or tests.
        #expect(!inSource(key, background: true, focused: false))
        #expect(inSource(key, background: true, focused: true))
        #expect(!inSource(key, frontmost: false, background: true, focused: true))
        // Presenting, any key in the app counts, as before.
        #expect(inSource(key, background: false, focused: false))
        #expect(!inSource(key, frontmost: false, background: false, focused: false))

        // Clicks and scrolls count by the window under them.
        let point = CGPoint(x: 10, y: 10)
        let click = DemoUserInput(windowNumber: 42, location: point, isKey: false, plainKeyCode: nil)
        #expect(inSource(click, frontmost: false, background: true, focused: false))
        let elsewhere = DemoUserInput(windowNumber: 7, location: point, isKey: false, plainKeyCode: nil)
        #expect(!inSource(elsewhere, background: true, focused: true))
        let unlisted = DemoUserInput(windowNumber: 0, location: point, isKey: false, plainKeyCode: nil)
        #expect(inSource(unlisted, background: true, focused: false))
        #expect(!inSource(unlisted, frontmost: false, background: true, focused: false))
    }

    @Test("A build that finishes in the background leaves a ready notice; only Open BetterMeets brings it forward")
    func readyNoticeWhileAway() async throws {
        let app = subtisApp()
        let session = session(app, searchModel(), defaults())
        session.isAppActive = { false }
        var broughtForward: [Bool] = []
        session.bringForward = { broughtForward.append($0) }
        session.prompt = "Search for The Matrix and open the result"
        session.build()
        try await waitUntil { session.phase == .ready && !session.isWritingScript }
        let notice = try #require(session.demoNoticeState.shown)
        #expect(notice.kind == .ready)
        #expect(notice.badge == "Demo ready")
        #expect(notice.title == session.demo?.title)
        #expect(notice.detail == "Tested · 3 steps · Example")
        #expect(notice.bundleID == "com.example.app")
        // Playing ends the notice.
        session.play()
        try await waitUntil { session.phase == .finished }
        #expect(session.demoNoticeState.shown == nil)
        #expect(broughtForward.isEmpty)

        session.checkAgain()
        try await waitUntil { session.phase == .ready }
        #expect(session.demoNoticeState.shown == notice)
        // A ready demo needs nothing from the panel, so Stage Only stays as it is.
        session.openFromDemoNotice()
        #expect(broughtForward == [false])
        #expect(session.demoNoticeState.shown == nil)
    }

    @Test("A build that finishes while BetterMeets is active leaves no notice, even after switching away")
    func noNoticeWhileActive() async throws {
        let app = subtisApp()
        var active = true
        let session = session(app, searchModel(), defaults())
        session.isAppActive = { active }
        session.prompt = "Search for The Matrix and open the result"
        session.build()
        try await waitUntil { session.phase == .ready && !session.isWritingScript }
        #expect(session.demoNoticeState.shown == nil)
        // The panel said it already, so coming back to ready while away doesn't announce it.
        active = false
        session.returnToStart()
        #expect(session.phase == .returning(then: .ready))
        try await waitUntil { session.phase == .ready }
        #expect(session.demoNoticeState.shown == nil)
    }

    @Test("A build paused again after the presenter put its notice away and resumed it shows the notice again")
    func pauseNoticeReturnsAfterResume() async throws {
        let app = subtisApp()
        let search = reply(
            .typeText(elementID: 1, text: "The Matrix", submit: true, title: "Search The Matrix", script: ""))
        let session = session(app, ScriptedModel([search, search]), defaults())
        session.isAppActive = { false }
        var broughtForward: [Bool] = []
        session.bringForward = { broughtForward.append($0) }
        session.prompt = "Search for The Matrix"
        app.failNextInput = .focusChanged
        session.build()
        try await waitUntil { session.phase == .scoutPaused(.focusLost) }
        let paused = try #require(session.demoNoticeState.shown)
        #expect(paused.badge == "Build paused")
        // Something to act on in the panel brings the controls back from Stage Only.
        session.openFromDemoNotice()
        #expect(broughtForward == [true])
        #expect(session.demoNoticeState.shown == nil)

        app.failNextInput = .focusChanged
        session.keepBuilding()
        #expect(session.phase == .scouting)
        try await waitUntil { session.phase == .scoutPaused(.focusLost) }
        #expect(session.demoNoticeState.shown == paused)
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

    @Test("Going back to a step keeps its line while the presenter gets the app to the start, then catches up to it")
    func previousStepThroughNeedsStart() async throws {
        let app = subtisApp()
        let session = session(app, searchModel(), defaults())
        session.prompt = "Search for The Matrix and open the result"
        session.build()
        try await waitUntil { session.phase == .ready && !session.isWritingScript }
        session.play()
        try await waitUntil { session.phase == .finished }

        // The way back fails, so the presenter takes the app to the start.
        app.failNextInput = .inputNotDelivered("Go to")
        session.previousStep()
        try await waitUntil {
            if case .needsStart(_, then: .play) = session.phase { true } else { false }
        }
        #expect(session.prompter.line == .step(2))
        #expect(IslandContent.make(IslandInputs(session: session)).position == "3/3")

        app.current = "home"
        session.checkStart()
        try await waitUntil {
            if case .running = session.phase { true } else { false }
        }
        // The quiet replay shows the step it goes back to, not a live opening line.
        #expect(session.prompter.line == .step(2))
        #expect(IslandContent.make(IslandInputs(session: session)).status == .text("Replaying up to step 3…", .plain))
        try await waitUntil { session.phase == .finished }
        #expect(session.rewindTarget == nil)
    }

    @Test("Going back again while catching up counts from the step it's going back to")
    func previousStepWhileCatchingUp() async throws {
        let app = subtisApp()
        let session = session(app, searchModel(), defaults())
        session.prompt = "Search for The Matrix and open the result"
        session.build()
        try await waitUntil { session.phase == .ready && !session.isWritingScript }
        session.play()
        try await waitUntil { session.phase == .finished }

        session.previousStep()
        try await waitUntil {
            if case .running = session.phase { true } else { false }
        }
        #expect(session.rewindTarget == 2)
        session.previousStep()
        #expect(session.rewindTarget == 1)
        #expect(session.prompter.line == .step(1))
        session.pause()
    }

    @Test("A resume keeps catching up quietly, and a line skipped meanwhile is still said at the step")
    func resumeWhileCatchingUp() async throws {
        let app = subtisApp()
        let session = session(app, searchModel(), defaults())
        session.prompt = "Search for The Matrix and open the result"
        session.build()
        try await waitUntil { session.phase == .ready && !session.isWritingScript }
        session.play()
        try await waitUntil { session.phase == .finished }
        session.replayTuning = (1, .milliseconds(300))

        session.previousStep()
        try await waitUntil {
            if case .running = session.phase { true } else { false }
        }
        session.pause()
        #expect(session.phase.nextStep < 2)
        var lines: [PresenterPrompter.Line?] = []
        let watching = session.prompter.$line.sink { lines.append($0) }
        session.play()
        session.skipLine()
        try await waitUntil { session.phase.currentStep == 2 }
        watching.cancel()
        #expect(!lines.contains(.step(0)) && !lines.contains(.step(1)))
        #expect(session.prompter.line == .step(2))
        #expect(!session.prompter.follower.isComplete)
        #expect(session.rewindTarget == nil)
        session.pause()
    }

    @Test("Start Over and Play Again show the opening line at once, not the closing line they leave")
    func startOverShowsOpening() async throws {
        let app = subtisApp()
        let session = session(app, searchModel(), defaults())
        session.prompt = "Search for The Matrix and open the result"
        session.build()
        try await waitUntil { session.phase == .ready && !session.isWritingScript }
        session.play()
        try await waitUntil { session.phase == .finished }
        #expect(session.prompter.line == .closing)

        session.startOver()
        #expect(session.phase == .returning(then: .play))
        #expect(session.prompter.line == .opening)
        // The island stays open on the opening line while the app goes back.
        let island = IslandContent.make(IslandInputs(session: session))
        #expect(island.mode == .expanded)
        #expect(island.place == "Opening")
        #expect(island.mark == .spinner)
        try await waitUntil { session.phase == .finished }

        session.play()
        #expect(session.prompter.line == .opening)
        try await waitUntil { session.phase == .finished }
    }

    @Test("The session follows the stage pausing and resuming")
    func followsStagePause() {
        let app = subtisApp()
        let session = session(app, ScriptedModel([]), defaults())
        #expect(!session.stagePaused)
        app.isStagePaused = true
        session.sourceDidChange()
        #expect(session.stagePaused)
        app.isStagePaused = false
        session.sourceDidChange()
        #expect(!session.stagePaused)
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

    @Test("Always Allow answers the question and keeps building, and the app stays trusted until removed")
    func alwaysAllowInApp() async throws {
        let app = subtisApp()
        let suite = "demo-session-trust-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: DemoSession.consentKey)
        let search = reply(.typeText(elementID: 1, text: "Inception", submit: true, title: "Search", script: ""))
        let finish = reply(.finish(title: "Search", startDescription: "Subtis home", startLabel: "", closingScript: ""))
        // Nothing is highlighted, though the request asks to show something, so each build's first finish is turned back.
        let session = session(app, ScriptedModel([search, finish, finish, search, finish, finish]), defaults)
        session.prompt = "Show how search works"
        session.build()
        try await waitUntil {
            if case .scoutPaused(.needsApproval) = session.phase { true } else { false }
        }
        #expect(app.log.isEmpty)
        let card = DemoPanelContent.make(DemoPanelInputs(session: session, stagePaused: false))
        #expect(card.secondaries.map(\.title) == ["Skip", "Always Allow in Example"])

        PanelActionID.alwaysAllow("Example").perform(on: session)
        #expect(session.alwaysAllowedApps == ["com.example.app"])
        try await waitUntil { session.phase == .ready && !session.isWritingScript }
        #expect(session.isChecked)
        let step = try #require(session.demo?.steps.first)
        #expect(step.approved)
        #expect(step.approvedReason == "Type “Inception” into “Buscar película”?")

        // The next build in the app doesn't ask.
        session.newDemo()
        session.prompt = "Show search again"
        session.build()
        try await waitUntil { session.phase == .ready && !session.isWritingScript }

        let relaunched = self.session(app, ScriptedModel([]), defaults)
        #expect(relaunched.isAlwaysAllowed("com.example.app"))
        relaunched.removeAlwaysAllowed("com.example.app")
        #expect(!relaunched.isAlwaysAllowed("com.example.app"))
        #expect(self.session(app, ScriptedModel([]), defaults).alwaysAllowedApps.isEmpty)
        // What was already approved stays approved.
        #expect(relaunched.demo?.steps.first?.approved == true)
    }

    // MARK: Sleep and user switching

    @Test("A build pauses before its next action while the Mac sleeps, and goes on by itself once it wakes")
    func buildPausesWhileAsleep() async throws {
        let app = subtisApp()
        let workspace = NotificationCenter()
        // The first look's typing is interrupted before it reaches the app, so Claude is asked again.
        let model = ScriptedModel(
            [reply(.typeText(elementID: 1, text: "The Matrix", submit: true, title: "Search The Matrix", script: ""))]
                + searchModelReplies)
        let session = session(app, model, defaults(), workspace: workspace)
        session.awayResumeDelay = .milliseconds(150)
        var slept = false
        app.beforeInput = { _ in
            guard !slept else { return }
            slept = true
            workspace.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        }
        session.prompt = "Search for The Matrix and open the result"
        session.build()
        try await waitUntil { session.phase == .scoutPaused(.away(.displaySleep)) }
        #expect(app.log.isEmpty)
        #expect(model.requests.count == 1)
        #expect(
            DemoNoticeContent.make(phase: session.phase, demo: session.demo, isChecked: false) == nil,
            "It goes on by itself, so it never calls the presenter back")

        workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        try await Task.sleep(for: .milliseconds(50))
        #expect(session.phase == .scoutPaused(.away(.displaySleep)), "Waits for the Mac to be back a moment")
        try await waitUntil { session.phase == .ready && !session.isWritingScript }
        #expect(session.isChecked)
        let pass = ["type The Matrix ⏎", "click The Matrix (1999)", "open https://subtis.io/"]
        #expect(app.log == pass + pass)
    }

    @Test("Displays that wake to the lock screen leave a build paused until secure input ends, as signing in does")
    func wakingToTheLockScreenWaits() async throws {
        let app = subtisApp()
        let workspace = NotificationCenter()
        let model = ScriptedModel(
            [reply(.typeText(elementID: 1, text: "The Matrix", submit: true, title: "Search The Matrix", script: ""))]
                + searchModelReplies)
        let session = session(app, model, defaults(), workspace: workspace)
        session.awayResumeDelay = .milliseconds(20)
        var locked = true
        session.isSecureInputOn = { locked }
        var slept = false
        app.beforeInput = { _ in
            guard !slept else { return }
            slept = true
            workspace.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        }
        session.prompt = "Search for The Matrix and open the result"
        session.build()
        try await waitUntil { session.phase == .scoutPaused(.away(.displaySleep)) }

        // The password field holds secure input, so nothing runs behind the lock screen.
        workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        try await Task.sleep(for: .milliseconds(200))
        #expect(session.phase == .scoutPaused(.away(.displaySleep)))
        #expect(model.requests.count == 1)
        #expect(app.log.isEmpty)

        locked = false
        try await waitUntil { session.phase == .ready && !session.isWritingScript }
        #expect(session.isChecked)
    }

    @Test("Secure input that never ends after a wake leaves an ordinary pause for the presenter")
    func endlessSecureInputPausesForThePresenter() async throws {
        let app = subtisApp()
        let workspace = NotificationCenter()
        let model = searchModel()
        let session = session(app, model, defaults(), workspace: workspace)
        session.awayResumeDelay = .milliseconds(20)
        session.awaySignInLimit = .milliseconds(100)
        session.isSecureInputOn = { true }
        app.beforeInput = { _ in workspace.post(name: NSWorkspace.screensDidSleepNotification, object: nil) }
        session.prompt = "Search for The Matrix"
        session.build()
        try await waitUntil { session.phase == .scoutPaused(.away(.displaySleep)) }
        app.beforeInput = nil
        workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        try await waitUntil { session.phase == .scoutPaused(.user) }
        #expect(model.requests.count == 1)
    }

    @Test("A test paused by a switch to another user waits for the displays too, then goes on from its step")
    func testPausesWhileSwitchedAway() async throws {
        let app = subtisApp()
        let workspace = NotificationCenter()
        let session = session(app, searchModel(), defaults(), workspace: workspace)
        session.awayResumeDelay = .milliseconds(20)
        var inputs = 0
        app.beforeInput = { _ in
            inputs += 1
            // Inputs: scout type, scout click, return to start, check type, check click.
            if inputs == 5 { workspace.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil) }
        }
        session.prompt = "Search for The Matrix and open the result"
        session.build()
        try await waitUntil { if case .paused(.verify, _, _, .away) = session.phase { true } else { false } }
        #expect(session.phase.nextStep == 1)
        #expect(session.phase == .paused(.verify, next: 1, current: 1, reason: .away(.sessionInactive)))
        #expect(app.log.count == 4)

        // Back in the session with the displays asleep: still away, for the other reason.
        workspace.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        #expect(session.phase == .paused(.verify, next: 1, current: 1, reason: .away(.displaySleep)))
        try await Task.sleep(for: .milliseconds(100))
        #expect(app.log.count == 4)

        workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        try await waitUntil { session.phase == .ready }
        #expect(session.isChecked)
        #expect(app.log.suffix(2) == ["click The Matrix (1999)", "open https://subtis.io/"])
    }

    @Test("A return to the start the Mac's sleep interrupted goes again once it wakes, then tests")
    func returnGoesAgainAfterSleep() async throws {
        let app = subtisApp()
        let workspace = NotificationCenter()
        let session = session(app, searchModel(), defaults(), workspace: workspace)
        session.awayResumeDelay = .milliseconds(20)
        var inputs = 0
        app.beforeInput = { _ in
            inputs += 1
            // Inputs: scout type, scout click, return to start.
            if inputs == 3 { workspace.post(name: NSWorkspace.screensDidSleepNotification, object: nil) }
        }
        session.prompt = "Search for The Matrix and open the result"
        session.build()
        try await waitUntil { inputs == 3 }
        try await Task.sleep(for: .milliseconds(100))
        // Still on the way, with nothing running.
        #expect(session.phase == .returning(then: .verify))
        #expect(app.log.count <= 3)

        workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        try await waitUntil { session.phase == .ready }
        #expect(session.isChecked)
    }

    @Test("A build the presenter paused stays paused through the Mac sleeping and waking")
    func presenterPauseOutlastsSleep() async throws {
        let app = subtisApp()
        let workspace = NotificationCenter()
        let model = searchModel()
        let session = session(app, model, defaults(), workspace: workspace)
        session.awayResumeDelay = .milliseconds(20)
        app.beforeInput = { _ in session.pause() }
        session.prompt = "Search for The Matrix"
        session.build()
        try await waitUntil { session.phase == .scoutPaused(.user) }
        app.beforeInput = nil

        workspace.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        #expect(session.phase == .scoutPaused(.user))
        workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        try await Task.sleep(for: .milliseconds(150))
        #expect(session.phase == .scoutPaused(.user))
        #expect(model.requests.count == 1)
    }

    @Test("Presenting carries on while the Mac sleeps")
    func playIgnoresSleep() async throws {
        let app = subtisApp()
        let workspace = NotificationCenter()
        let session = session(app, searchModel(), defaults(), workspace: workspace)
        session.prompt = "Search for The Matrix and open the result"
        session.build()
        try await waitUntil { session.phase == .ready && !session.isWritingScript }
        app.beforeInput = { _ in workspace.post(name: NSWorkspace.screensDidSleepNotification, object: nil) }
        session.play()
        try await waitUntil { session.phase == .finished }
        #expect(app.log.suffix(2) == ["type The Matrix ⏎", "click The Matrix (1999)"])
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
