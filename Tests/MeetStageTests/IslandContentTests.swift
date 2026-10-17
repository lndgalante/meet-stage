import Foundation
import Testing

@testable import MeetStage

@Suite("Island content")
struct IslandContentTests {
    private static let titles = [
        "Open a new task", "Write the prompt", "Review the prompt", "Pick the schedule", "The Create button",
        "Create the task", "See the next run", "Check the schedule", "Open the summary"
    ]

    private func demo(opening: String? = nil, closing: String = "") -> RealTimeDemo {
        RealTimeDemo(
            prompt: "Schedule a daily summary",
            app: DemoAppKey(bundleID: "com.openai.chat", appName: "ChatGPT", engine: .native, isBrowser: false),
            title: "Create a scheduled task",
            start: DemoStartPoint(
                signature: ScreenSignature(urlKey: nil, selected: [], headings: [], dialogOpen: false), url: nil,
                returnAnchor: nil, toggles: [],
                description: "The ChatGPT app on the Scheduled page, with the task list showing and no task open",
                sizeClass: .regular),
            steps: Self.titles.map { title in
                DemoStep(
                    title: title, script: "Line for \(title).", holdSeconds: 10, action: .press(.tab),
                    pre: ScreenSignature(urlKey: nil, selected: [], headings: [], dialogOpen: false))
            },
            status: .recorded, closingScript: closing, openingScript: opening)
    }

    private func panel(_ phase: DemoPhase, demo: RealTimeDemo? = nil) -> DemoPanelInputs {
        var inputs = DemoPanelInputs(phase: phase, demo: demo ?? self.demo(), appName: "ChatGPT")
        inputs.teleprompterVisible = true
        return inputs
    }

    /// What the session would hand the island with `line` showing, as `DemoSession.showLine` sets it.
    private func inputs(_ panel: DemoPanelInputs, line: PresenterPrompter.Line?) -> IslandInputs {
        var inputs = IslandInputs(phase: panel.phase, panel: .make(panel), line: line)
        let steps = panel.demo?.steps ?? []
        switch line {
        case .opening:
            inputs.heading = "Opening"
            inputs.upNext = steps.first?.title
        case .step(let index):
            inputs.heading = steps[index].title
            inputs.upNext = steps.indices.contains(index + 1) ? steps[index + 1].title : nil
            inputs.position = (index + 1, steps.count)
        case .closing:
            inputs.heading = "Wrap up"
        case nil:
            break
        }
        inputs.hasClosing = panel.demo?.closingScript.isEmpty == false
        return inputs
    }

    private func inputs(_ phase: DemoPhase, line: PresenterPrompter.Line? = .step(1)) -> IslandInputs {
        inputs(panel(phase), line: line)
    }

    private func make(_ inputs: IslandInputs) -> IslandContent { IslandContent.make(inputs) }

    private func make(_ phase: DemoPhase, line: PresenterPrompter.Line? = .step(1)) -> IslandContent {
        make(inputs(phase, line: line))
    }

    private func titles(_ actions: [PanelAction]) -> [String] { actions.map(\.title) }

    private func enabled(_ actions: [PanelAction]) -> [Bool] { actions.map(\.isEnabled) }

    private let running = DemoPhase.running(.present, next: 1, current: 1)

    // MARK: Mode

    @Test("The island opens for a line it can present, and stays open when the demo finishes")
    func modes() {
        let line = PresenterPrompter.Line.step(0)
        for phase in [
            DemoPhase.ready, .needsStart(.wrongScreen, then: .ready), .needsStart(.wrongScreen, then: .play),
            .returning(then: .play), .running(.present, next: 0, current: 0),
            .paused(.present, next: 0, current: 0, reason: .user), .offTrack(.present, index: 0, .targetNotFound("x"))
        ] {
            #expect(IslandMode.make(phase: phase, line: line) == .expanded)
            #expect(IslandMode.make(phase: phase, line: nil) == .compact)
        }
        #expect(IslandMode.make(phase: .finished, line: nil) == .expanded)
        for phase in [
            DemoPhase.composing, .scouting, .scoutPaused(.user), .returning(then: .verify), .returning(then: .ready),
            .needsStart(.wrongScreen, then: .verify), .running(.verify, next: 0, current: 0),
            .paused(.verify, next: 0, current: 0, reason: .user), .offTrack(.verify, index: 0, .targetNotFound("x"))
        ] {
            #expect(IslandMode.make(phase: phase, line: line) == .compact)
        }
    }

    // MARK: Compact

    @Test("With no lines yet, the compact island says where they'll come from")
    func noLinesYet() {
        for phase in [DemoPhase.composing, .scoutPaused(.user)] {
            let content = make(phase, line: nil)
            #expect(content.mode == .compact)
            #expect(content.mark == nil)
            #expect(content.place == "No lines yet")
            #expect(content.placeHelp == "Your lines appear here once the demo is built.")
            #expect(content.next == nil)
            #expect(content.body == nil)
            #expect(content.meter == .hidden)
            #expect(content.status == .none)
            #expect(content.slots.isEmpty)
            #expect(content.extras.isEmpty)
        }
    }

    @Test("Building, testing and going back show what's happening beside the camera")
    func compactStates() {
        let cases: [(DemoPhase, IslandContent.Mark, String)] = [
            (.scouting, .spinner, "Building"),
            (.returning(then: .verify), .spinner, "Testing"),
            (.running(.verify, next: 2, current: 2), .spinner, "Testing"),
            (.paused(.verify, next: 2, current: 2, reason: .user), .paused, "Test paused"),
            (.offTrack(.verify, index: 2, .targetNotFound("Save")), .stopped, "Test stopped"),
            (.returning(then: .ready), .spinner, "Going back"),
            (.returning(then: .compose), .spinner, "Going back"),
            (.needsStart(.wrongScreen, then: .verify), .notAtStart, "Not at start"),
            (.needsStart(.noAutomaticReturn, then: .compose), .notAtStart, "Not at start")
        ]
        for (phase, mark, place) in cases {
            let content = make(phase, line: nil)
            #expect(content.mode == .compact)
            #expect(content.mark == mark)
            #expect(content.place == place)
            #expect(content.placeHelp == place)
            #expect(content.placeAccessibility == place)
            #expect(content.slots.isEmpty)
        }
    }

    // MARK: Ready

    @Test("Ready previews the opening line, with Play the only live control")
    func ready() {
        let content = make(inputs(panel(.ready, demo: demo(opening: "Here's how scheduling works.")), line: .opening))
        #expect(content.mode == .expanded)
        #expect(content.mark == nil)
        #expect(content.position == nil)
        #expect(content.place == "Opening")
        #expect(content.placeAccessibility == "Opening line")
        #expect(content.next == .init(label: "Next", title: "Open a new task"))
        #expect(content.next?.accessibilityLabel == "Next: Open a new task")
        #expect(content.body == .line(.uniform, dim: false))
        #expect(content.meter == .hidden)
        #expect(content.status == .text("Follows your voice", .plain))
        #expect(titles(content.slots) == ["Start Over", "Previous Step", "Play", "Next Line"])
        #expect(enabled(content.slots) == [false, false, true, false])
        #expect(content.slots[0].help == "Play does this")
        #expect(content.slots[1].help == "Available while the demo plays")
        #expect(content.extras.isEmpty)
        #expect(!content.stoppedEdge)

        // Without an opening line, the first step is up, with its position.
        var inputs = inputs(.ready, line: .step(0))
        inputs.followsVoice = false
        let first = make(inputs)
        #expect(first.position == "1/9")
        #expect(first.place == "Open a new task")
        #expect(first.placeHelp == "1/9 Open a new task")
        #expect(first.placeAccessibility == "Step 1 of 9, Open a new task")
        #expect(first.status == .text("Timed at speaking pace", .plain))
    }

    @Test("Ready shows the panel's notice or reason instead of the pacing")
    func readyNotice() {
        var panel = panel(.ready)
        panel.notice = "The test run didn’t reach every step. Test it again from the start."
        #expect(
            make(inputs(panel, line: .step(0))).status
                == .text("The test run didn’t reach every step. Test it again from the start.", .warning))
        panel.notice = nil
        panel.recheckSuggested = true
        #expect(
            make(inputs(panel, line: .step(0))).status
                == .text("A step moved during the last run. Test again to keep it tested.", .plain))
    }

    @Test("Ready but not live says why, and Play is disabled with the panel's help")
    func readyNotLive() {
        var panel = panel(.ready)
        panel.isLiveSourceSelected = false
        var content = make(inputs(panel, line: .step(0)))
        #expect(content.status == .text("Put ChatGPT on stage to play this demo.", .plain))
        #expect(content.slots[2].title == "Play")
        #expect(!content.slots[2].isEnabled)
        #expect(content.slots[2].help == "Put ChatGPT on stage first")
        panel.stagePaused = true
        content = make(inputs(panel, line: .step(0)))
        #expect(content.status == .text("The stage is paused. Resume it to play this demo.", .plain))
        #expect(content.slots[2].help == "Resume the stage first")
    }

    // MARK: Start

    @Test("Not at the start, Go to Start is the primary and the panel's other choices are in the menu")
    func needsStart() {
        var content = make(.needsStart(.wrongScreen, then: .play), line: .step(0))
        #expect(content.mode == .expanded)
        #expect(content.mark == .notAtStart)
        #expect(content.body == .line(.uniform, dim: true))
        #expect(content.meter == .hidden)
        #expect(
            content.status
                == .text(
                    "ChatGPT isn’t on the Scheduled page. Go to Start takes it there, then the demo plays.", .plain))
        #expect(titles(content.slots) == ["Start Over", "Previous Step", "Go to Start", "Next Line"])
        #expect(enabled(content.slots) == [false, false, true, false])
        #expect(content.slots[0].help == "Available while the demo plays")
        #expect(content.slots[2].islandSymbol == "arrow.backward.to.line")
        #expect(titles(content.extras) == ["Play Anyway"])

        content = make(.needsStart(.togglesDiffer(["Dark mode"]), then: .ready), line: .step(0))
        #expect(titles(content.extras) == ["Play Anyway", "I’m There"])

        content = make(.needsStart(.noAutomaticReturn, then: .ready), line: .step(0))
        #expect(content.slots[2].title == "I’m There")
        #expect(content.slots[2].islandSymbol == "checkmark")

        // While it checks, the band spins and the status says what it's doing.
        var panel = panel(.needsStart(.wrongScreen, then: .play))
        panel.activity = "Looking for the starting screen"
        content = make(inputs(panel, line: .step(0)))
        #expect(content.mark == .spinner)
        #expect(content.status == .text("Looking for the starting screen…", .plain))
    }

    @Test("Going back to play keeps the target line up, dim, with Pause Demo in the middle")
    func returningToPlay() {
        var content = make(.returning(then: .play), line: .opening)
        #expect(content.mode == .expanded)
        #expect(content.mark == .spinner)
        #expect(content.place == "Opening")
        #expect(content.placeAccessibility == "Opening line, going back")
        #expect(content.body == .line(.uniform, dim: true))
        #expect(content.meter == .hidden)
        #expect(content.status == .text("Going to the start. Then the demo plays from the top.", .plain))
        #expect(titles(content.slots) == ["Start Over", "Previous Step", "Pause Demo", "Next Line"])
        #expect(enabled(content.slots) == [false, false, true, false])
        #expect(content.slots[2].role == .interrupt)

        var panel = panel(.returning(then: .play))
        panel.rewindTarget = 3
        content = make(inputs(panel, line: .step(3)))
        #expect(content.position == "4/9")
        #expect(content.status == .text("Going to the start. Then it replays quickly up to step 4.", .plain))
    }

    @Test("Catching up after Previous Step shows the target line while it replays quietly up to it")
    func catchingUp() {
        let content = make(.running(.present, next: 1, current: 0), line: .step(3))
        #expect(content.mark == .spinner)
        #expect(content.position == "4/9")
        #expect(content.place == "Pick the schedule")
        #expect(content.placeAccessibility == "Step 4 of 9, Pick the schedule, going back")
        #expect(content.body == .line(.uniform, dim: true))
        #expect(content.meter == .hidden)
        #expect(content.status == .text("Replaying up to step 4…", .plain))
        #expect(titles(content.slots) == ["Start Over", "Previous Step", "Pause Demo", "Next Line"])

        // On the line's own step, or resumed after it, it's playing again.
        #expect(make(.running(.present, next: 3, current: 3), line: .step(3)).mark == nil)
        #expect(make(.running(.present, next: 4, current: nil), line: .step(3)).mark == nil)
        #expect(make(.running(.present, next: 0, current: nil), line: .step(0)).mark == nil)
    }

    // MARK: Playing

    @Test("Listening, said words dim, the next is underlined, and the meter follows the voice")
    func listening() {
        var inputs = inputs(running)
        inputs.voice = .listening
        let content = make(inputs)
        #expect(content.mode == .expanded)
        #expect(content.mark == nil)
        #expect(content.position == "2/9")
        #expect(content.place == "Write the prompt")
        #expect(content.next == .init(label: "Next", title: "Review the prompt"))
        #expect(content.body == .line(.followed(marksNext: true), dim: false))
        #expect(content.meter == .voice)
        #expect(content.status == .heard)
        #expect(titles(content.slots) == ["Start Over", "Previous Step", "Pause Demo", "Next Line"])
        #expect(enabled(content.slots) == [true, true, true, true])
        #expect(content.slots[3].islandSymbol == "forward.fill")

        // Previous Step has nothing to go back to at the opening.
        var opening = self.inputs(
            panel(.running(.present, next: 0, current: nil), demo: demo(opening: "Hi.")), line: .opening)
        opening.voice = .listening
        #expect(enabled(make(opening).slots) == [true, false, true, true])
    }

    @Test("While the microphone gets ready, the line is plain and the status says what it's doing")
    func preparing() {
        var inputs = inputs(running)
        inputs.voice = .preparing("Getting the microphone ready")
        let content = make(inputs)
        #expect(content.body == .line(.followed(marksNext: false), dim: false))
        #expect(content.meter == .voice)
        #expect(content.status == .text("Getting the microphone ready", .plain))
    }

    @Test("With voice off, the line is timed: dots fill with the hold and the status counts down")
    func timed() {
        var inputs = inputs(running)
        inputs.followsVoice = false
        var content = make(inputs)
        #expect(content.body == .line(.uniform, dim: false))
        #expect(content.meter == .dots)
        #expect(content.status == .none)

        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        inputs.hold = (start, 8)
        content = make(inputs)
        #expect(content.meter == .timed(start: start, seconds: 8))
        #expect(content.status == .countdown(start: start, seconds: 8))
    }

    @Test("An unavailable microphone falls back to the timer and says so in orange")
    func micUnavailable() {
        var inputs = inputs(running)
        inputs.voice = .unavailable("No microphone is available.")
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        inputs.hold = (start, 6)
        let content = make(inputs)
        #expect(content.body == .line(.uniform, dim: false))
        #expect(content.meter == .timed(start: start, seconds: 6))
        #expect(content.status == .text("Mic unavailable", .warning, help: "No microphone is available."))
    }

    @Test("A finished line, or Next Line, shows the whole line said and moves on")
    func movingOn() {
        for voice in [SpeechListener.State.listening, .off] {
            var inputs = inputs(running)
            inputs.voice = voice
            inputs.followsVoice = voice == .listening
            inputs.followerIsComplete = true
            let content = make(inputs)
            #expect(content.body == .line(.allSaid, dim: false))
            #expect(content.meter == .full)
            #expect(content.status == .text("Moving on…", .plain))
        }
    }

    @Test("A step with no line says so, and moves on by voice or waits out its timer")
    func noLine() {
        var inputs = inputs(running)
        inputs.voice = .listening
        inputs.followerIsEmpty = true
        inputs.followerIsComplete = true
        var content = make(inputs)
        #expect(content.position == "2/9")
        #expect(content.body == .noLine(dim: false))
        #expect(content.meter == .voice)
        #expect(content.status == .text("Moving on…", .plain))

        inputs.followsVoice = false
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        inputs.hold = (start, 2)
        content = make(inputs)
        #expect(content.body == .noLine(dim: false))
        #expect(content.meter == .timed(start: start, seconds: 2))
        #expect(content.status == .countdown(start: start, seconds: 2))
    }

    @Test("The last step's next is Wrap up with a closing line, else Last step")
    func lastStep() {
        let last = DemoPhase.running(.present, next: 8, current: 8)
        var content = make(inputs(panel(last, demo: demo(closing: "That's it.")), line: .step(8)))
        #expect(content.next == .init(label: "Next", title: "Wrap up"))
        content = make(last, line: .step(8))
        #expect(content.next == .init(label: nil, title: "Last step"))
        #expect(content.next?.accessibilityLabel == "Last step")
    }

    // MARK: Paused and stopped

    @Test("Paused by the presenter: Resume Demo, and Next Step plays one step")
    func paused() {
        var inputs = inputs(.paused(.present, next: 2, current: 1, reason: .user))
        inputs.voice = .listening
        let content = make(inputs)
        #expect(content.mark == .paused)
        #expect(content.placeAccessibility == "Step 2 of 9, Write the prompt, paused")
        #expect(content.body == .line(.followed(marksNext: false), dim: true))
        #expect(content.meter == .hidden)
        #expect(content.status == .text("Paused", .plain))
        #expect(titles(content.slots) == ["Start Over", "Previous Step", "Resume Demo", "Next Step"])
        #expect(enabled(content.slots) == [true, true, true, true])
        #expect(content.slots[2].role == .forward)
        #expect(content.slots[3].help == "Play the next step, then pause (⌃⌘→)")
    }

    @Test("Paused for another reason, the status says why; an error is orange")
    func pausedReasons() {
        #expect(
            make(.paused(.present, next: 2, current: 1, reason: .userInput)).status
                == .text("You clicked or typed in ChatGPT, so the demo paused.", .plain))
        #expect(
            make(.paused(.present, next: 2, current: 1, reason: .sourceChanged)).status
                == .text("The shared window changed, so the demo paused.", .plain))
        #expect(
            make(.paused(.present, next: 2, current: 1, reason: .error(.invalidResponse))).status
                == .text(DemoError.invalidResponse.localizedDescription, .warning))
    }

    @Test(
        "On the wrong screen, Continue from Step N leads, Skip Step takes the forward place, Try Again is in the menu")
    func offTrackWrongScreen() {
        let content = make(.offTrack(.present, index: 5, .wrongScreen(onStep: 7)), line: .step(5))
        #expect(content.mark == .stopped)
        #expect(content.stoppedEdge)
        #expect(content.placeAccessibility == "Step 6 of 9, Create the task, stopped")
        #expect(content.body == .line(.followed(marksNext: false), dim: true))
        #expect(content.meter == .hidden)
        #expect(content.status == .text("ChatGPT is already on step 8’s screen.", .warning))
        #expect(titles(content.slots) == ["Start Over", "Previous Step", "Continue from Step 8", "Skip Step"])
        #expect(enabled(content.slots) == [true, true, true, true])
        #expect(content.slots[2].islandSymbol == "play.fill")
        #expect(content.slots[3].islandSymbol == "forward.end.fill")
        #expect(content.slots[3].help == "Skip step 6 and go on to step 7")
        #expect(titles(content.extras) == ["Try Again"])
    }

    @Test("When a target is missing, Try Again leads and Skip Step is beside it")
    func offTrackNotFound() {
        let content = make(.offTrack(.present, index: 5, .targetNotFound("Save")), line: .step(5))
        #expect(content.status == .text("Couldn’t find “Save”. It may have moved or been renamed.", .warning))
        #expect(titles(content.slots) == ["Start Over", "Previous Step", "Try Again", "Skip Step"])
        #expect(content.slots[2].islandSymbol == "arrow.clockwise")
        #expect(content.extras.isEmpty)
    }

    // MARK: Finished

    @Test("Finished with a closing line: Wrap up, the closing line, and Play Again")
    func finishedWithClosing() {
        let content = make(
            inputs(panel(.finished, demo: demo(closing: "That's the whole flow.")), line: .closing))
        #expect(content.mode == .expanded)
        #expect(content.mark == nil)
        #expect(content.position == nil)
        #expect(content.place == "Wrap up")
        #expect(content.placeAccessibility == "Closing line")
        #expect(content.next == nil)
        #expect(content.body == .line(.uniform, dim: false))
        #expect(content.meter == .hidden)
        #expect(content.status == .text("Played all 9 steps. Play Again goes back to the start first.", .plain))
        #expect(titles(content.slots) == ["Start Over", "Previous Step", "Play Again", "Next Step"])
        #expect(enabled(content.slots) == [false, true, true, false])
        #expect(content.slots[0].help == "Play Again does this")
    }

    @Test("Finished with no closing line: Done, with a check, and the panel's message")
    func finishedWithoutClosing() {
        var panel = panel(.finished)
        var content = make(inputs(panel, line: nil))
        #expect(content.mode == .expanded)
        #expect(content.mark == .done)
        #expect(content.place == "Done")
        #expect(content.next == nil)
        #expect(content.body == .message(PresenterPrompter.finishedText))
        #expect(titles(content.slots) == ["Start Over", "Previous Step", "Play Again", "Next Step"])
        panel.notice = "Skipped “Share”; couldn’t find it."
        content = make(inputs(panel, line: nil))
        #expect(content.status == .text("Skipped “Share”; couldn’t find it.", .warning))
    }

    @Test("Every expanded state keeps four slots in the same places")
    func fourSlots() {
        let phases: [DemoPhase] = [
            .ready, .needsStart(.wrongScreen, then: .play), .returning(then: .play),
            .running(.present, next: 1, current: 1), .running(.present, next: 0, current: 0),
            .paused(.present, next: 2, current: 1, reason: .user),
            .offTrack(.present, index: 1, .blocked(.invalidResponse)), .finished
        ]
        for phase in phases {
            let content = make(phase)
            #expect(content.mode == .expanded)
            #expect(content.slots.count == 4)
            #expect(content.slots[0].id == .startOver)
            #expect(content.slots[1].id == .previousStep)
        }
    }
}
