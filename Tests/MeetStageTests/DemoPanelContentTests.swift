import Foundation
import Testing

@testable import MeetStage

@Suite("Demo panel content")
struct DemoPanelContentTests {
    private static let titles = [
        "Open a new task", "Write the prompt", "Review the prompt", "Pick the schedule", "The Create button",
        "Create the task", "See the next run", "Check the schedule", "Open the summary"
    ]

    private func step(_ title: String) -> DemoStep {
        DemoStep(
            title: title, script: "Line for \(title).", holdSeconds: 10, action: .press(.tab),
            pre: ScreenSignature(urlKey: nil, selected: [], headings: [], dialogOpen: false))
    }

    private func demo(steps count: Int = 9, opening: String? = nil, closing: String = "") -> RealTimeDemo {
        RealTimeDemo(
            prompt: "Schedule a daily summary",
            app: DemoAppKey(bundleID: "com.openai.chat", appName: "ChatGPT", engine: .native, isBrowser: false),
            title: "Create a scheduled task",
            start: DemoStartPoint(
                signature: ScreenSignature(urlKey: nil, selected: [], headings: [], dialogOpen: false), url: nil,
                returnAnchor: nil, toggles: [],
                description: "The ChatGPT app on the Scheduled page, with the task list showing and no task open",
                sizeClass: .regular),
            steps: (0..<count).map { step(Self.titles[$0 % Self.titles.count]) }, status: .recorded,
            closingScript: closing, openingScript: opening)
    }

    /// A build that recorded `recorded` steps and still plans two beats.
    private func draft(recorded: Int) -> RealTimeDemo {
        var demo = demo(steps: 0)
        let records = (0..<recorded).map { index in
            ScoutRecord(turn: index, steps: [step(Self.titles[index])], scroll: nil, outcome: .changed, fact: "")
        }
        demo.outline = ["Open the summary", "See the next run"]
        demo.status = .draft(ScoutDraft(records: records, outline: demo.outline))
        return demo
    }

    private func inputs(_ phase: DemoPhase, demo: RealTimeDemo? = nil) -> DemoPanelInputs {
        let open = demo ?? self.demo()
        var inputs = DemoPanelInputs(phase: phase, demo: open, appName: "ChatGPT")
        inputs.outlineProgress = open.outline.map { ($0, false) }
        return inputs
    }

    private func make(_ inputs: DemoPanelInputs) -> DemoPanelContent { DemoPanelContent.make(inputs) }

    private func make(_ phase: DemoPhase, demo: RealTimeDemo? = nil) -> DemoPanelContent {
        make(inputs(phase, demo: demo))
    }

    private func titles(_ actions: [PanelAction]) -> [String] { actions.map(\.title) }

    private func enabled(_ actions: [PanelAction]) -> [Bool] { actions.map(\.isEnabled) }

    // MARK: Composing (rows 1–6)

    private func composing() -> DemoPanelInputs {
        var inputs = DemoPanelInputs(phase: .composing, demo: nil, appName: "ChatGPT")
        inputs.hasSavedDemos = false
        return inputs
    }

    @Test("1: The first demo invites a request, with Build Demo in the field")
    func firstDemo() {
        let content = make(composing())
        #expect(content.glyph == .symbol("play.rectangle.fill", .accent))
        #expect(content.headline == .text("Real-time demos"))
        #expect(
            content.subline?.text
                == "Describe a flow. Claude builds it in ChatGPT, tests it, and gets it ready to present.")
        #expect(content.primary == nil)
        #expect(content.secondaries.isEmpty)
        #expect(content.body == .composer)
        #expect(content.composerRow == .ideas)
        #expect(content.detailLabel == "New demo")
    }

    @Test("2: A new demo beside saved ones is called New demo, and its library row is the new one")
    func newDemoWithSaved() {
        var inputs = composing()
        inputs.hasSavedDemos = true
        let content = make(inputs)
        #expect(content.glyph == .symbol("square.and.pencil", .secondary))
        #expect(content.headline == .text("New demo"))
        #expect(content.subline?.text == "Describe a flow. Claude builds it in ChatGPT and tests it.")
        #expect(content.primary == nil)
        #expect(content.libraryStatus == .new)
    }

    @Test("3–4: A setup row hides the subline and replaces the ideas")
    func setupRows() {
        var key = composing()
        key.buildSetup = .key
        #expect(make(key).subline == nil)
        #expect(make(key).composerRow == .key)
        var consent = composing()
        consent.asksForConsent = true
        #expect(make(consent).subline == nil)
        #expect(make(consent).composerRow == .consent)
        // The key row comes first when both apply.
        key.asksForConsent = true
        #expect(make(key).composerRow == .key)
    }

    @Test("5: A build notice replaces the subline")
    func composingNotice() {
        var inputs = composing()
        inputs.notice = "Couldn’t read the source window."
        #expect(make(inputs).subline == .init(text: "Couldn’t read the source window.", kind: .notice))
    }

    @Test("6: With no app on stage, the band says how to get one")
    func composingNotLive() {
        var inputs = composing()
        inputs.hasSavedDemos = true
        inputs.isLiveSourceSelected = false
        var content = make(inputs)
        #expect(content.headline == .text("Real-time demos"))
        #expect(content.subline == .init(text: "Put an app on stage to build a demo of it.", kind: .reason))
        inputs.stagePaused = true
        content = make(inputs)
        #expect(content.subline?.text == "The stage is paused. Resume it to build a demo.")
    }

    // MARK: Building (rows 7–18)

    @Test("7: Building shows the pipeline, what it's doing, and Pause Build")
    func scouting() {
        var inputs = inputs(.scouting, demo: draft(recorded: 4))
        inputs.activity = "Opening the schedule picker"
        var content = make(inputs)
        #expect(content.glyph == .spinner)
        #expect(content.headline == .pipeline(.build))
        #expect(content.headline.plainText == "Build › Test › Ready")
        #expect(content.headline.accessibilityText == "Building. Stage 1 of 3.")
        #expect(content.subline?.text == "4 steps so far · Opening the schedule picker…")
        #expect(content.primary?.title == "Pause Build")
        #expect(content.primary?.role == .interrupt)
        #expect(content.secondaries.isEmpty)
        #expect(content.body == .grid(.building))
        #expect(
            content.cells.map(\.state) == [.recorded, .recorded, .recorded, .recorded, .recording, .planned, .planned])
        #expect(content.cells[4].title == "Recording…")
        #expect(content.bar.demoTools.isEmpty)
        #expect(!content.bar.teleprompterEnabled)
        #expect(content.bar.teleprompterHelp == "Available once the demo is built")
        #expect(content.libraryStatus == .working("Building"))

        inputs = self.inputs(.scouting, demo: draft(recorded: 0))
        content = make(inputs)
        #expect(content.subline?.text == "Working…")
        inputs.activity = String(repeating: "a", count: 80)
        #expect(make(inputs).subline?.text == String(repeating: "a", count: 50) + "…")
    }

    @Test("8: A paused build offers Resume Build, the steps so far and Edit Request")
    func buildPausedByUser() {
        var content = make(.scoutPaused(.user), demo: draft(recorded: 4))
        #expect(content.glyph == .symbol("pause.circle.fill", .orange))
        #expect(content.headline == .text("Build paused"))
        #expect(content.subline?.text == "4 steps so far. Resume to keep building from this screen.")
        #expect(titles(content.secondaries) == ["Use 4 Steps", "Edit Request"])
        #expect(content.primary?.title == "Resume Build")
        #expect(content.primary?.role == .forward)
        #expect(content.body == .grid(.building))
        #expect(content.cells.map(\.state) == [.recorded, .recorded, .recorded, .recorded, .planned, .planned])
        #expect(content.libraryStatus == .buildPaused)

        content = make(.scoutPaused(.user), demo: draft(recorded: 0))
        #expect(content.subline?.text == "Resume to keep building from this screen.")
        #expect(titles(content.secondaries) == ["Edit Request"])
    }

    @Test("9–12: Each interruption says why in the presenter's words")
    func buildInterruptions() {
        let demo = draft(recorded: 2)
        #expect(
            make(.scoutPaused(.userInput), demo: demo).subline?.text
                == "You clicked or typed in ChatGPT, so the build paused.")
        #expect(make(.scoutPaused(.focusLost), demo: demo).subline?.text == "ChatGPT lost focus, so the build paused.")
        #expect(
            make(.scoutPaused(.relaunched), demo: demo).subline?.text
                == "This build was interrupted. Resume it from the current screen, or use the steps so far.")
        #expect(
            make(.scoutPaused(.relaunched), demo: draft(recorded: 0)).subline?.text
                == "This build was interrupted. Resume it from the current screen.")
        let leftScope = make(.scoutPaused(.leftScope("ChatGPT opened a settings window.")), demo: demo)
        #expect(
            leftScope.subline?.text
                == "ChatGPT opened a settings window. Close it and come back to ChatGPT to resume.")
        for content in [make(.scoutPaused(.userInput), demo: demo), leftScope] {
            #expect(content.headline == .text("Build paused"))
            #expect(titles(content.secondaries) == ["Use 2 Steps", "Edit Request"])
            #expect(content.primary?.title == "Resume Build")
        }
    }

    @Test("13: A build error stops the build, with Copy Details when there are any")
    func buildError() {
        var inputs = inputs(.scoutPaused(.error(.invalidResponse)), demo: draft(recorded: 2))
        inputs.diagnosticDetails = "request-id: abc"
        let content = make(inputs)
        #expect(content.glyph == .symbol("exclamationmark.triangle.fill", .orange))
        #expect(content.headline == .text("Build stopped"))
        #expect(content.subline == .init(text: DemoError.invalidResponse.localizedDescription, kind: .reason))
        #expect(content.showsCopyDetails)
        #expect(content.primary?.title == "Resume Build")
    }

    @Test("14: An approval asks the policy question verbatim, with Skip and Allow")
    func needsApproval() {
        let pending = PendingApproval(
            action: .press(.tab), title: "Create the task", script: "", message: "Click “Create” in this dialog?")
        let content = make(.scoutPaused(.needsApproval(pending)), demo: draft(recorded: 3))
        #expect(content.glyph == .symbol("hand.raised.fill", .orange))
        #expect(content.headline == .text("Needs your approval"))
        #expect(content.subline?.text == "Click “Create” in this dialog?")
        #expect(titles(content.secondaries) == ["Skip"])
        #expect(content.primary?.title == "Allow")
        #expect(content.primary?.role == .forward)
        #expect(content.cells.map(\.state) == [.recorded, .recorded, .recorded, .needsApproval, .planned, .planned])
        #expect(content.cells[3].title == "Create the task")
    }

    @Test("15: A blocked request offers the alternative Claude found")
    func blockedWithAlternative() {
        let content = make(
            .scoutPaused(.blocked(reason: "Exporting needs a paid plan.", alternative: "the export settings")),
            demo: draft(recorded: 2))
        #expect(content.glyph == .symbol("exclamationmark.triangle.fill", .orange))
        #expect(content.headline == .text("Can’t show that in ChatGPT"))
        #expect(content.subline?.text == "Exporting needs a paid plan. It can show the export settings instead.")
        #expect(titles(content.secondaries) == ["Edit Request", "Use 2 Steps"])
        #expect(content.primary?.title == "Build Alternative")
        #expect(content.primary?.help == "Go back to the start and build a demo that shows the export settings")
        #expect(content.body == .grid(.building))
        #expect(
            make(.scoutPaused(.blocked(reason: "No.", alternative: "x")), demo: draft(recorded: 0)).body == .empty)
    }

    @Test("16: A blocked request with no alternative goes back to the request")
    func blockedWithoutAlternative() {
        var content = make(
            .scoutPaused(.blocked(reason: "That needs a login.", alternative: "")), demo: draft(recorded: 2))
        #expect(content.subline?.text == "That needs a login.")
        #expect(titles(content.secondaries) == ["Use 2 Steps"])
        #expect(content.primary?.title == "Edit Request")
        #expect(content.primary?.symbol == "pencil")
        #expect(content.primary?.role == .forward)
        content = make(.scoutPaused(.blocked(reason: "That needs a login.", alternative: "")), demo: draft(recorded: 0))
        #expect(content.secondaries.isEmpty)
        #expect(content.body == .empty)
    }

    @Test("17: A limit with steps recorded makes Use Steps the primary")
    func limitWithSteps() {
        let content = make(.scoutPaused(.limit(.budget)), demo: draft(recorded: 4))
        #expect(content.headline == .text("Build stopped"))
        #expect(content.subline?.text == "Stopped at the $2 build limit. Use the 4 steps so far, or edit your request.")
        #expect(titles(content.secondaries) == ["Edit Request"])
        #expect(content.primary?.title == "Use 4 Steps")
        #expect(content.primary?.symbol == "checkmark")
    }

    @Test("18: A limit with nothing recorded can only edit the request")
    func limitWithoutSteps() {
        let content = make(.scoutPaused(.limit(.time)), demo: draft(recorded: 0))
        #expect(content.subline?.text == "Stopped after four minutes. Edit your request to try again.")
        #expect(content.secondaries.isEmpty)
        #expect(content.primary?.title == "Edit Request")
        #expect(content.body == .empty)
    }

    @Test("Build decisions need the stage, except Edit Request")
    func buildDecisionsNeedTheStage() {
        var inputs = inputs(.scoutPaused(.user), demo: draft(recorded: 3))
        inputs.isLiveSourceSelected = false
        inputs.stagePaused = true
        let content = make(inputs)
        #expect(enabled(content.secondaries) == [false, true])
        #expect(content.primary?.isEnabled == false)
        #expect(content.primary?.help == "Resume the stage first")
        inputs.stagePaused = false
        #expect(make(inputs).primary?.help == "Put ChatGPT on stage first")
    }

    // MARK: Going to the start (rows 19–22)

    @Test("19: Going to the start before a test is the test stage")
    func returningToVerify() {
        let content = make(.returning(then: .verify))
        #expect(content.glyph == .spinner)
        #expect(content.headline == .pipeline(.test))
        #expect(content.headline.accessibilityText == "Testing. Stage 2 of 3.")
        #expect(content.subline?.text == "Going to the Scheduled page before the test…")
        #expect(content.primary?.title == "Pause Test")
        #expect(content.primary?.role == .interrupt)
        #expect(content.body == .grid(.idle))
        #expect(content.libraryStatus == .working("Testing"))
    }

    @Test("20–21: Going to the start before playing says what happens next")
    func returningToPlay() {
        var content = make(.returning(then: .play))
        #expect(content.headline == .text("Going to the start"))
        #expect(content.subline?.text == "Then the demo plays from the top.")
        #expect(content.primary?.title == "Pause Demo")
        #expect(content.primary?.role == .interrupt)
        #expect(content.cells.allSatisfy { $0.state == .idle })
        var inputs = inputs(.returning(then: .play))
        inputs.rewindTarget = 3
        content = make(inputs)
        #expect(content.subline?.text == "Then it replays quickly up to step 4.")
    }

    @Test("22: Going back to the start with nothing after offers Stop")
    func returningToReady() {
        for then in [AfterReturn.ready, .compose] {
            let content = make(.returning(then: then))
            #expect(content.headline == .text("Going to the start"))
            #expect(content.subline?.text == "Putting ChatGPT back on the Scheduled page…")
            #expect(content.primary?.title == "Stop")
            #expect(content.primary?.symbol == "stop.fill")
            #expect(content.primary?.role == .interrupt)
        }
        #expect(make(.returning(then: .ready)).libraryStatus == .working("Going to the start"))
    }

    // MARK: Not at the start (rows 23–29c)

    @Test("23–26: On the wrong screen, Go to Start is the fix")
    func wrongScreen() {
        let play = make(.needsStart(.wrongScreen, then: .play))
        #expect(play.glyph == .symbol("exclamationmark.circle.fill", .orange))
        #expect(play.headline == .text("Not at the start"))
        #expect(
            play.subline?.text
                == "ChatGPT isn’t on the Scheduled page. Go to Start takes it there, then the demo plays.")
        #expect(titles(play.secondaries) == ["Play Anyway"])
        #expect(play.primary?.title == "Go to Start")
        #expect(play.primary?.symbol == "arrow.backward.to.line")
        #expect(play.body == .grid(.idle))

        let ready = make(.needsStart(.wrongScreen, then: .ready))
        #expect(ready.subline?.text == "ChatGPT isn’t on the Scheduled page.")
        #expect(titles(ready.secondaries) == ["Play Anyway"])

        let verify = make(.needsStart(.wrongScreen, then: .verify))
        #expect(verify.subline?.text == "ChatGPT isn’t on the Scheduled page, so the test can’t begin.")
        #expect(verify.secondaries.isEmpty)
        #expect(verify.primary?.title == "Go to Start")

        let compose = make(.needsStart(.wrongScreen, then: .compose))
        #expect(compose.subline?.text == "ChatGPT isn’t on the Scheduled page.")
        #expect(compose.secondaries.isEmpty)
    }

    @Test("27: Toggles that differ name each one")
    func togglesDiffer() {
        let content = make(.needsStart(.togglesDiffer(["Dark mode"]), then: .play))
        #expect(content.subline?.text == "Turn Dark mode back to how the demo starts.")
        #expect(titles(content.secondaries) == ["Play Anyway", "I’m There"])
        #expect(content.primary?.title == "Go to Start")
        let verify = make(.needsStart(.togglesDiffer(["Dark mode"]), then: .verify))
        #expect(titles(verify.secondaries) == ["I’m There"])
    }

    @Test("28: Unreadable web content waits for I'm There")
    func webContentUnavailable() {
        let content = make(.needsStart(.webContentUnavailable, then: .ready))
        #expect(content.subline?.text == DemoError.webContentUnavailable(.native).localizedDescription)
        #expect(content.subline?.kind == .reason)
        #expect(titles(content.secondaries) == ["Play Anyway"])
        #expect(content.primary?.title == "I’m There")
        #expect(content.primary?.symbol == "checkmark")
    }

    @Test("29: Without an automatic return, the presenter goes there and says I'm There")
    func noAutomaticReturnBeforePlaying() {
        var inputs = inputs(.needsStart(.noAutomaticReturn, then: .play))
        inputs.notice = "Still not at the start."
        var content = make(inputs)
        #expect(
            content.subline?.text
                == "Still not at the start. Go to the Scheduled page in ChatGPT. The demo plays once you’re there.")
        #expect(titles(content.secondaries) == ["Play Anyway"])
        #expect(content.primary?.title == "I’m There")
        inputs.canReturnAutomatically = true
        content = make(inputs)
        #expect(titles(content.secondaries) == ["Play Anyway", "Go to Start"])
    }

    @Test("29b: Before a test, the test begins once the presenter is there")
    func noAutomaticReturnBeforeTesting() {
        let content = make(.needsStart(.noAutomaticReturn, then: .verify))
        #expect(content.subline?.text == "Go to the Scheduled page in ChatGPT. The test begins once you’re there.")
        #expect(content.secondaries.isEmpty)
        #expect(content.primary?.title == "I’m There")
    }

    @Test("29c: Going back to ready or the request, BetterMeets notices on its own")
    func noAutomaticReturnBeforeReady() {
        let ready = make(.needsStart(.noAutomaticReturn, then: .ready))
        #expect(ready.subline?.text == "Go to the Scheduled page in ChatGPT. BetterMeets notices once you’re there.")
        #expect(titles(ready.secondaries) == ["Play Anyway"])
        let compose = make(.needsStart(.noAutomaticReturn, then: .compose))
        #expect(compose.subline?.text == ready.subline?.text)
        #expect(compose.secondaries.isEmpty)
    }

    @Test("Checking the start shows a spinner and the activity, keeping the actions")
    func checkingTheStart() {
        var inputs = inputs(.needsStart(.wrongScreen, then: .play))
        inputs.activity = "Looking for the starting screen"
        let content = make(inputs)
        #expect(content.glyph == .spinner)
        #expect(content.subline == .init(text: "Looking for the starting screen…", kind: .facts))
        #expect(content.primary?.title == "Go to Start")
    }

    // MARK: Ready (rows 30–34)

    @Test("30: A tested demo shows its title, its facts and Play")
    func readyTested() {
        var inputs = inputs(.ready)
        inputs.isChecked = true
        let content = make(inputs)
        #expect(content.glyph == .symbol("checkmark.seal.fill", .green))
        #expect(content.headline == .text("Create a scheduled task"))
        #expect(content.subline?.text == "Tested · 9 steps · About 2 min · Starts on the Scheduled page")
        #expect(
            content.subline?.shorter == ["Tested · 9 steps · Starts on the Scheduled page", "Tested · 9 steps"])
        #expect(
            content.subline?.help
                == "Starts on: The ChatGPT app on the Scheduled page, with the task list showing and no task open")
        #expect(content.primary?.title == "Play")
        #expect(content.primary?.role == .forward)
        #expect(content.primary?.isEnabled == true)
        #expect(content.secondaries.isEmpty)
        #expect(content.transport.isEmpty)
        #expect(content.body == .grid(.idle))
        #expect(content.cellsAreEditable)
        #expect(content.cells.first?.help == "Line for Open a new task.")
        #expect(titles(content.bar.demoTools) == ["Edit Demo…", "Test Again"])
        #expect(enabled(content.bar.demoTools) == [true, true])
        #expect(content.libraryStatus == .tested)
        #expect(content.detailLabel == "Create a scheduled task")
    }

    @Test("31: An untested demo says so")
    func readyNotTested() {
        let content = make(.ready, demo: demo(steps: 1))
        #expect(content.glyph == .symbol("circle.dashed", .secondary))
        #expect(content.subline?.text == "Not tested · 1 step · Under 1 min · Starts on the Scheduled page")
        #expect(content.libraryStatus == .notTested)
    }

    @Test("32–33: A moved step or a notice takes the subline")
    func readyNotices() {
        var inputs = inputs(.ready)
        inputs.isChecked = true
        inputs.recheckSuggested = true
        var content = make(inputs)
        #expect(content.glyph == .symbol("checkmark.seal.fill", .green))
        #expect(
            content.subline
                == .init(
                    text: "A step moved during the last run. Test again to keep it tested.", kind: .reason))
        inputs.notice = "The test run didn’t reach every step. Test it again from the start."
        content = make(inputs)
        #expect(content.subline?.kind == .notice)
        #expect(content.subline?.text == inputs.notice)
        #expect(content.primary?.title == "Play")
    }

    @Test("34: Play waits for the stage")
    func readyNotLive() {
        var inputs = inputs(.ready)
        inputs.isLiveSourceSelected = false
        inputs.stagePaused = true
        var content = make(inputs)
        #expect(content.subline?.text == "The stage is paused. Resume it to play this demo.")
        #expect(content.primary?.isEnabled == false)
        #expect(content.primary?.help == "Resume the stage first")
        #expect(content.bar.demoTools.map(\.isEnabled) == [true, false])
        inputs.stagePaused = false
        content = make(inputs)
        #expect(content.subline?.text == "Put ChatGPT on stage to play this demo.")
        #expect(content.primary?.help == "Put ChatGPT on stage first")
    }

    // MARK: Testing (rows 35–42)

    @Test("35: Testing shows the step and green checks on the steps that passed")
    func testing() {
        let content = make(.running(.verify, next: 2, current: 2))
        #expect(content.glyph == .spinner)
        #expect(content.headline == .pipeline(.test))
        #expect(content.subline?.text == "Testing step 3 of 9…")
        #expect(content.primary?.title == "Pause Test")
        #expect(content.primary?.role == .interrupt)
        #expect(content.body == .grid(.test))
        #expect(content.cells.prefix(4).map(\.state) == [.passed, .passed, .testing, .upcoming])
        #expect(!content.cellsAreEditable)
        #expect(enabled(content.bar.demoTools) == [false, false])
        #expect(content.libraryStatus == .working("Testing"))
    }

    @Test("36–39: A paused test resumes from its step")
    func pausedTest() {
        let user = make(.paused(.verify, next: 2, current: 2, reason: .user))
        #expect(user.glyph == .symbol("pause.circle.fill", .orange))
        #expect(user.headline == .text("Test paused at step 3 of 9"))
        #expect(user.subline?.text == "Resume Test finishes the test from step 3.")
        #expect(titles(user.secondaries) == ["Go to Start"])
        #expect(user.primary?.title == "Resume Test")
        #expect(user.primary?.role == .forward)
        #expect(user.primary?.help == "Finish the test from step 3 (⌃⌘↩)")
        #expect(user.cells.prefix(4).map(\.state) == [.passed, .passed, .current, .upcoming])
        #expect(user.libraryStatus == .paused)
        #expect(
            make(.paused(.verify, next: 2, current: 2, reason: .userInput)).subline?.text
                == "You clicked or typed in ChatGPT, so the test paused.")
        #expect(
            make(.paused(.verify, next: 2, current: 2, reason: .sourceChanged)).subline?.text
                == "The shared window changed, so the test paused.")
        let error = make(.paused(.verify, next: 2, current: 2, reason: .error(.screenshot)))
        #expect(error.glyph == .symbol("exclamationmark.triangle.fill", .orange))
        #expect(error.headline == .text("Test paused at step 3 of 9"))
        #expect(error.subline?.text == DemoError.screenshot.localizedDescription)
        #expect(error.primary?.title == "Resume Test")
    }

    @Test("40–42: A stopped test marks the failed step and offers Try Again")
    func stoppedTest() {
        let notFound = make(.offTrack(.verify, index: 4, .targetNotFound("Create")))
        #expect(notFound.glyph == .symbol("exclamationmark.triangle.fill", .orange))
        #expect(notFound.headline == .text("Test stopped at step 5 of 9"))
        #expect(notFound.subline?.text == "Couldn’t find “Create”. It may have moved or been renamed.")
        #expect(titles(notFound.secondaries) == ["Go to Start"])
        #expect(notFound.primary?.title == "Try Again")
        #expect(notFound.primary?.symbol == "arrow.clockwise")
        #expect(notFound.cells.prefix(6).map(\.state) == [.passed, .passed, .passed, .passed, .failed, .upcoming])
        #expect(
            make(.offTrack(.verify, index: 4, .wrongScreen(onStep: 7))).subline?.text
                == "ChatGPT is on step 8’s screen, not step 5’s.")
        #expect(
            make(.offTrack(.verify, index: 4, .blocked(.occluded("Create")))).subline?.text
                == DemoError.occluded("Create").localizedDescription)
    }

    // MARK: Presenting (rows 43–51)

    @Test("43: Presenting shows the step, what's next, the transport and Pause Demo")
    func presenting() {
        var inputs = inputs(.running(.present, next: 3, current: 3))
        var content = make(inputs)
        #expect(content.glyph == .symbol("play.fill", .accent))
        #expect(content.headline == .text("Step 4 of 9"))
        #expect(content.subline == .init(text: "Next: The Create button", kind: .next))
        #expect(titles(content.transport) == ["Start Over", "Previous Step", "Next Line"])
        #expect(enabled(content.transport) == [true, true, true])
        #expect(content.secondaries.isEmpty)
        #expect(content.primary?.title == "Pause Demo")
        #expect(content.primary?.role == .interrupt)
        #expect(content.body == .line)
        #expect(content.libraryStatus == .playing)

        inputs.teleprompterVisible = true
        inputs.isFollowingVoice = true
        content = make(inputs)
        #expect(content.glyph == .symbol("waveform", .accent))
        #expect(content.body == .grid(.present))
        #expect(content.cells.prefix(5).map(\.state) == [.done, .done, .done, .current, .upcoming])
    }

    @Test("43: The opening line, the first step and the last step")
    func presentingEnds() {
        let opening = make(.running(.present, next: 0, current: nil), demo: demo(opening: "Hi.", closing: "Bye."))
        #expect(opening.headline == .text("Opening line"))
        #expect(opening.subline?.text == "Next: Open a new task")
        #expect(enabled(opening.transport) == [true, false, true])
        let first = make(.running(.present, next: 0, current: 0))
        #expect(first.headline == .text("Step 1 of 9"))
        #expect(enabled(first.transport) == [true, false, true])
        #expect(
            make(.running(.present, next: 8, current: 8), demo: demo(closing: "Bye.")).subline?.text
                == "Next: closing line")
        #expect(make(.running(.present, next: 8, current: 8)).subline?.text == "Last step")
    }

    @Test("44–47: A paused demo resumes from its step, with Next Step in the transport")
    func pausedDemo() {
        let user = make(.paused(.present, next: 4, current: 3, reason: .user))
        #expect(user.glyph == .symbol("pause.circle.fill", .orange))
        #expect(user.headline == .text("Paused at step 4 of 9"))
        #expect(user.subline == .init(text: "Next: The Create button", kind: .next))
        #expect(titles(user.transport) == ["Start Over", "Previous Step", "Next Step"])
        #expect(enabled(user.transport) == [true, true, true])
        #expect(user.primary?.title == "Resume Demo")
        #expect(user.primary?.role == .forward)
        #expect(user.primary?.help == "Resume from step 4 (⌃⌘↩)")
        #expect(user.cellsAreEditable)
        #expect(user.libraryStatus == .paused)
        #expect(
            make(.paused(.present, next: 4, current: 3, reason: .userInput)).subline?.text
                == "You clicked or typed in ChatGPT, so the demo paused.")
        #expect(
            make(.paused(.present, next: 4, current: 3, reason: .sourceChanged)).subline?.text
                == "The shared window changed, so the demo paused.")
        var error = inputs(.paused(.present, next: 4, current: 3, reason: .error(.screenshot)))
        error.diagnosticDetails = "details"
        #expect(make(error).glyph == .symbol("exclamationmark.triangle.fill", .orange))
        #expect(make(error).showsCopyDetails)
    }

    @Test("48–49: A stopped demo offers Skip Step and Try Again, with Next off")
    func stoppedDemo() {
        let notFound = make(.offTrack(.present, index: 5, .targetNotFound("Create")))
        #expect(notFound.glyph == .symbol("exclamationmark.triangle.fill", .orange))
        #expect(notFound.headline == .text("Stopped at step 6 of 9"))
        #expect(notFound.subline?.text == "Couldn’t find “Create”. It may have moved or been renamed.")
        #expect(titles(notFound.transport) == ["Start Over", "Previous Step", "Next Step"])
        #expect(enabled(notFound.transport) == [true, true, false])
        #expect(titles(notFound.secondaries) == ["Skip Step"])
        #expect(notFound.secondaries.first?.help == "Skip step 6 and go on to step 7")
        #expect(notFound.primary?.title == "Try Again")
        let blocked = make(.offTrack(.present, index: 5, .blocked(.occluded("Create"))))
        #expect(blocked.subline?.text == DemoError.occluded("Create").localizedDescription)
        #expect(titles(blocked.secondaries) == ["Skip Step"])
    }

    @Test("50: On a later step's screen, Continue from that step is the primary")
    func stoppedOnLaterScreen() {
        var inputs = inputs(.offTrack(.present, index: 5, .wrongScreen(onStep: 7)))
        inputs.teleprompterVisible = true
        let content = make(inputs)
        #expect(content.subline?.text == "ChatGPT is already on step 8’s screen.")
        #expect(titles(content.secondaries) == ["Skip Step", "Try Again"])
        #expect(content.primary?.title == "Continue from Step 8")
        #expect(content.primary?.shortTitle == "From Step 8")
        #expect(content.primary?.symbol == "play.fill")
        #expect(content.cells.prefix(7).map(\.state) == [.done, .done, .done, .done, .done, .failed, .upcoming])
    }

    @Test("51: A finished demo offers Play Again and shows the closing line")
    func finished() {
        var inputs = inputs(.finished, demo: demo(closing: "Bye."))
        var content = make(inputs)
        #expect(content.glyph == .symbol("flag.checkered", .secondary))
        #expect(content.headline == .text("Demo finished"))
        #expect(content.subline?.text == "Played all 9 steps. Play Again goes back to the start first.")
        #expect(titles(content.transport) == ["Start Over", "Previous Step", "Next Step"])
        #expect(enabled(content.transport) == [false, true, false])
        #expect(content.transport.first?.help == "Play Again does this")
        #expect(content.primary?.title == "Play Again")
        #expect(content.primary?.role == .forward)
        #expect(content.body == .closing)
        inputs.teleprompterVisible = true
        content = make(inputs)
        #expect(content.body == .grid(.finished))
        #expect(content.cells.allSatisfy { $0.state == .done })
        inputs.recheckSuggested = true
        #expect(make(inputs).subline?.text == "A step moved during this run. Test again to keep it tested.")
        inputs.notice = "Skipped “Share”; couldn’t find it."
        #expect(make(inputs).subline == .init(text: "Skipped “Share”; couldn’t find it.", kind: .notice))
    }

    @Test("The transport needs the stage")
    func transportNeedsTheStage() {
        var inputs = inputs(.paused(.present, next: 4, current: 3, reason: .user))
        inputs.isLiveSourceSelected = false
        let content = make(inputs)
        #expect(enabled(content.transport) == [false, false, false])
        #expect(content.primary?.isEnabled == false)
        var running = self.inputs(.running(.present, next: 3, current: 3))
        running.isLiveSourceSelected = false
        #expect(enabled(make(running).transport) == [false, false, true])
    }

    // MARK: Labels

    @Test("Only Continue from Step has a short title for the narrow split button")
    func shortTitles() {
        #expect(PanelActionID.continueFromStep(8).shortTitle == "From Step 8")
        let others: [PanelActionID] = [
            .play, .playAgain, .resumeDemo, .resumeTest, .resumeBuild, .tryAgain, .goToStart, .imThere, .allow,
            .buildAlternative("x"), .useSteps(4), .editRequest
        ]
        #expect(others.allSatisfy { $0.shortTitle == nil })
        #expect(PanelActionID.useSteps(1).title == "Use 1 Step")
        #expect(PanelActionID.play.menuTitle == "Play Demo")
        #expect(PanelActionID.cancelNewDemo.menuTitle == "Cancel New Demo")
        #expect(PanelActionID.renameDemo.menuTitle == "Rename Demo…")
    }

    @Test("Interrupt actions are the pauses and Stop")
    func roles() {
        let interrupts: [PanelActionID] = [.pauseBuild, .pauseTest, .pauseDemo, .stop]
        #expect(interrupts.allSatisfy { $0.role == .interrupt })
        #expect([PanelActionID.play, .resumeDemo, .tryAgain, .goToStart].allSatisfy { $0.role == .forward })
    }

    @Test("The Demo menu's first item names what ⌃⌘↩ does in each phase")
    func menuPrimary() {
        let pending = PendingApproval(action: .press(.tab), title: "t", script: "", message: "m")
        let cases: [(DemoPhase, String)] = [
            (.scouting, "Pause Build"),
            (.returning(then: .verify), "Pause Test"),
            (.running(.verify, next: 2, current: 2), "Pause Test"),
            (.returning(then: .play), "Pause Demo"),
            (.running(.present, next: 2, current: 2), "Pause Demo"),
            (.returning(then: .ready), "Stop"),
            (.returning(then: .compose), "Stop"),
            (.ready, "Play Demo"),
            (.finished, "Play Again"),
            (.paused(.present, next: 3, current: 2, reason: .user), "Resume Demo"),
            (.paused(.verify, next: 3, current: 2, reason: .user), "Resume Test"),
            (.offTrack(.present, index: 2, .targetNotFound("x")), "Try Again"),
            (.offTrack(.verify, index: 2, .targetNotFound("x")), "Try Again"),
            (.scoutPaused(.user), "Resume Build"),
            (.scoutPaused(.needsApproval(pending)), "Play Demo"),
            (.needsStart(.wrongScreen, then: .ready), "Play Anyway"),
            (.needsStart(.wrongScreen, then: .play), "Play Anyway"),
            (.needsStart(.wrongScreen, then: .verify), "Play Demo"),
            (.composing, "Play Demo")
        ]
        for (phase, title) in cases {
            #expect(PanelActionID.menuPrimary(in: phase).menuTitle == title, "\(phase)")
        }
    }

    @Test("The floating demo button follows the menu, except while paused building or away from the start")
    func floatingPrimary() {
        let pending = PendingApproval(action: .press(.tab), title: "t", script: "", message: "m")
        #expect(PanelActionID.floatingPrimary(in: .scoutPaused(.needsApproval(pending))).menuTitle == "Resume Build")
        #expect(PanelActionID.floatingPrimary(in: .needsStart(.wrongScreen, then: .play)).menuTitle == "Go to Start")
        #expect(PanelActionID.floatingPrimary(in: .needsStart(.noAutomaticReturn, then: .verify)) == .goToStart)
        let shared: [DemoPhase] = [
            .scouting, .returning(then: .verify), .running(.present, next: 1, current: 1), .returning(then: .ready),
            .paused(.verify, next: 1, current: 1, reason: .user), .offTrack(.present, index: 1, .targetNotFound("x")),
            .ready, .finished
        ]
        #expect(shared.allSatisfy { PanelActionID.floatingPrimary(in: $0) == PanelActionID.menuPrimary(in: $0) })
    }

    // MARK: Library

    @Test("Library rows mark what the open demo is doing")
    func libraryStatus() {
        #expect(make(.running(.present, next: 1, current: 1)).libraryStatus == .playing)
        #expect(make(.offTrack(.present, index: 1, .targetNotFound("x"))).libraryStatus == .paused)
        #expect(make(.needsStart(.wrongScreen, then: .play)).libraryStatus == .notTested)
        #expect(
            make(.returning(then: .compose), demo: draft(recorded: 2)).libraryStatus == .working("Going to the start"))
        var saved = demo()
        #expect(LibraryRowStatus.saved(saved) == .notTested)
        saved.status = .checked(DemoVerification(checkedAt: Date(), fingerprint: "f"))
        #expect(LibraryRowStatus.saved(saved) == .tested)
        #expect(LibraryRowStatus.saved(draft(recorded: 1)) == .buildPaused)
    }

    // MARK: Grid

    @Test("The grid fits columns of three to the width and never scrolls")
    func gridLayout() {
        let fits = StepGridLayout(cells: 9, width: 459)
        #expect(fits.columns == 3)
        #expect(fits.visible == 9)
        #expect(fits.hidden == 0)
        let narrow = StepGridLayout(cells: 14, width: 459)
        #expect(narrow.columns == 3)
        #expect(narrow.visible == 8)
        #expect(narrow.hidden == 6)
        #expect(StepGridLayout(cells: 15, width: 794).hidden == 0)
        #expect(StepGridLayout(cells: 16, width: 794).visible == 14)
        #expect(StepGridLayout(cells: 24, width: 1279).hidden == 0)
        #expect(StepGridLayout(cells: 25, width: 1279).columns == 8)
        let short = StepGridLayout(cells: 2, width: 1279)
        #expect(short.columns == 1)
        #expect(short.columnWidth == 260)
    }

    // MARK: Announcements

    private func announcement(from previous: DemoPhase, to phase: DemoPhase, checked: Bool = false) -> String? {
        var inputs = inputs(phase)
        inputs.isChecked = checked
        return DemoPanelContent.announcement(from: previous, to: inputs)
    }

    @Test("A build announces starting, stopping and needing approval")
    func buildAnnouncements() {
        let pending = PendingApproval(action: .press(.tab), title: "t", script: "", message: "Open example.com?")
        #expect(announcement(from: .composing, to: .scouting) == "Building the demo.")
        #expect(
            announcement(from: .scouting, to: .scoutPaused(.needsApproval(pending)))
                == "Needs your approval. Open example.com?")
        #expect(
            announcement(from: .scouting, to: .scoutPaused(.blocked(reason: "It needs a login.", alternative: "")))
                == "Can’t show that in ChatGPT. It needs a login.")
        #expect(
            announcement(from: .scouting, to: .scoutPaused(.limit(.budget)))
                == "Build stopped. Stopped at the $2 build limit.")
        #expect(
            announcement(from: .scouting, to: .scoutPaused(.error(.screenshot)))
                == "Build stopped. \(DemoError.screenshot.localizedDescription)")
        #expect(announcement(from: .scouting, to: .scoutPaused(.user)) == "Build paused.")
        #expect(announcement(from: .scoutPaused(.user), to: .scoutPaused(.userInput)) == nil)
    }

    @Test("A test announces once, and its result when the demo is ready")
    func testAnnouncements() {
        #expect(announcement(from: .scouting, to: .returning(then: .verify)) == "Testing the demo.")
        #expect(announcement(from: .returning(then: .verify), to: .running(.verify, next: 0, current: nil)) == nil)
        #expect(
            announcement(
                from: .paused(.verify, next: 2, current: 2, reason: .user), to: .running(.verify, next: 2, current: nil)
            )
                == nil)
        #expect(announcement(from: .ready, to: .returning(then: .verify)) == "Testing the demo.")
        // A passed test goes back to the start before it's ready; the result still speaks.
        let running = DemoPhase.running(.verify, next: 9, current: 8)
        let base = DemoPanelContent.announcementBase(previous: running, next: .returning(then: .ready))
        #expect(base == running)
        #expect(announcement(from: running, to: .returning(then: .ready)) == nil)
        #expect(announcement(from: base, to: .ready, checked: true) == "Tested. Ready to play.")
        #expect(announcement(from: base, to: .ready) == "Ready, not tested.")
        #expect(announcement(from: .scouting, to: .ready, checked: true) == "Tested. Ready to play.")
    }

    @Test("Going back to the start after a pause, and composing, stay quiet")
    func quietTransitions() {
        let paused = DemoPhase.paused(.present, next: 4, current: 3, reason: .user)
        let base = DemoPanelContent.announcementBase(previous: paused, next: .returning(then: .ready))
        #expect(base == paused)
        #expect(announcement(from: base, to: .ready) == nil)
        #expect(announcement(from: .ready, to: .returning(then: .play)) == nil)
        #expect(announcement(from: .scoutPaused(.user), to: .composing) == nil)
        #expect(
            DemoPanelContent.announcementBase(previous: .ready, next: .returning(then: .play))
                == .returning(then: .play))
    }

    @Test("Playing, pausing, stopping and finishing each speak once")
    func presentAnnouncements() {
        #expect(announcement(from: .ready, to: .needsStart(.wrongScreen, then: .play)) == "ChatGPT isn’t at the start.")
        #expect(
            announcement(
                from: .needsStart(.wrongScreen, then: .play), to: .needsStart(.togglesDiffer(["A"]), then: .play))
                == nil)
        #expect(
            announcement(from: .returning(then: .play), to: .running(.present, next: 0, current: nil)) == "Playing.")
        #expect(
            announcement(
                from: .paused(.present, next: 4, current: 3, reason: .user),
                to: .running(.present, next: 4, current: nil))
                == nil)
        #expect(
            announcement(from: .running(.present, next: 3, current: 3), to: .running(.present, next: 4, current: 4))
                == nil)
        #expect(
            announcement(
                from: .running(.present, next: 3, current: 3), to: .paused(.present, next: 4, current: 3, reason: .user)
            )
                == "Paused at step 4.")
        #expect(
            announcement(
                from: .running(.verify, next: 2, current: 2), to: .paused(.verify, next: 2, current: 2, reason: .user))
                == "Test paused at step 3.")
        #expect(
            announcement(
                from: .running(.present, next: 5, current: 5),
                to: .offTrack(.present, index: 5, .targetNotFound("Create")))
                == "Stopped at step 6. Couldn’t find “Create”. It may have moved or been renamed.")
        #expect(announcement(from: .running(.present, next: 9, current: 8), to: .finished) == "Demo finished.")
    }
}
