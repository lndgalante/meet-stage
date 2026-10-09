import Foundation

enum PanelActionRole: Sendable {
    /// Goes forward: prominent in the primary slot.
    case forward
    /// Stops what's running: same slot and size, bordered.
    case interrupt
}

/// Every action the demo panel offers, named once. The panel, the Demo menu, the
/// floating widget and the teleprompter read their titles from here, and
/// `perform(on:)` is the one place each action runs.
enum PanelActionID: Hashable, Sendable {
    case build
    case pauseBuild, resumeBuild, allow, skip, editRequest
    case buildAlternative(String)
    case useSteps(Int)
    case pauseTest, resumeTest
    case play, pauseDemo, resumeDemo, playAgain, tryAgain, skipStep, stop
    /// The 1-based step the app is already on.
    case continueFromStep(Int)
    case goToStart, imThere, playAnyway
    case startOver, previousStep, nextLine, nextStep
    case testAgain, editDemo, renameDemo, deleteDemo, newDemo, cancelNewDemo

    /// What an action's help text names.
    struct Context {
        var app: String
        var start: String
        /// The 1-based step the action acts on.
        var step = 1
    }

    var title: String {
        switch self {
        case .build: "Build Demo"
        case .pauseBuild: "Pause Build"
        case .resumeBuild: "Resume Build"
        case .allow: "Allow"
        case .skip: "Skip"
        case .editRequest: "Edit Request"
        case .buildAlternative: "Build Alternative"
        case .useSteps(let count): count == 1 ? "Use 1 Step" : "Use \(count) Steps"
        case .pauseTest: "Pause Test"
        case .resumeTest: "Resume Test"
        case .play: "Play"
        case .pauseDemo: "Pause Demo"
        case .resumeDemo: "Resume Demo"
        case .playAgain: "Play Again"
        case .tryAgain: "Try Again"
        case .skipStep: "Skip Step"
        case .stop: "Stop"
        case .continueFromStep(let step): "Continue from Step \(step)"
        case .goToStart: "Go to Start"
        case .imThere: "I’m There"
        case .playAnyway: "Play Anyway"
        case .startOver: "Start Over"
        case .previousStep: "Previous Step"
        case .nextLine: "Next Line"
        case .nextStep: "Next Step"
        case .testAgain: "Test Again"
        case .editDemo: "Edit Demo…"
        case .renameDemo: "Rename"
        case .deleteDemo: "Delete Demo…"
        case .newDemo: "New Demo"
        case .cancelNewDemo: "Cancel"
        }
    }

    /// The title in menus and the floating widget, which stand apart from the panel.
    var menuTitle: String {
        switch self {
        case .play: "Play Demo"
        case .renameDemo: "Rename Demo…"
        case .cancelNewDemo: "Cancel New Demo"
        default: title
        }
    }

    /// Used by the split button when the full title doesn't fit.
    var shortTitle: String? {
        if case .continueFromStep(let step) = self { "From Step \(step)" } else { nil }
    }

    var symbol: String? {
        switch self {
        case .build: "wand.and.sparkles"
        case .pauseBuild, .pauseTest, .pauseDemo: "pause.fill"
        case .resumeBuild, .resumeTest, .play, .resumeDemo, .playAgain, .continueFromStep: "play.fill"
        case .allow, .useSteps, .imThere: "checkmark"
        case .buildAlternative: "arrow.triangle.branch"
        case .editRequest, .editDemo: "pencil"
        case .tryAgain: "arrow.clockwise"
        case .stop: "stop.fill"
        case .goToStart: "arrow.backward.to.line"
        case .startOver: "arrow.counterclockwise"
        case .previousStep: "backward.fill"
        case .nextLine, .nextStep: "forward.fill"
        case .testAgain: "checkmark.seal"
        case .newDemo: "plus"
        case .deleteDemo: "minus"
        case .skip, .skipStep, .playAnyway, .renameDemo, .cancelNewDemo: nil
        }
    }

    var role: PanelActionRole {
        switch self {
        case .pauseBuild, .pauseTest, .pauseDemo, .stop: .interrupt
        default: .forward
        }
    }

    func help(_ context: Context) -> String {
        let app = context.app
        let step = context.step
        return switch self {
        case .build: "Claude explores \(app), records each step, then plays it back to test it (Return)"
        case .pauseBuild: "Pause the build. Resume it later, or use the steps so far (⌃⌘↩)"
        case .resumeBuild: "Keep building from the current screen (⌃⌘↩)"
        case .allow: "Let Claude do this once, then keep building"
        case .skip: "Don’t do this. Claude finds another way."
        case .editRequest: "Discard this build and go back to your request. Your words stay."
        case .buildAlternative(let alternative): "Go back to the start and build a demo that shows \(alternative)"
        case .useSteps(let count):
            count == 1
                ? "Keep the step recorded so far, then test it"
                : "Keep the \(count) steps recorded so far, then test them"
        case .pauseTest: "Pause the test (⌃⌘↩)"
        case .resumeTest: "Finish the test from step \(step) (⌃⌘↩)"
        case .play:
            "Play from the start (⌃⌘↩). If \(app) isn’t on \(context.start), BetterMeets takes it there first."
        case .pauseDemo: "Pause here. The app and the highlight stay on screen. (⌃⌘↩)"
        case .resumeDemo: "Resume from step \(step) (⌃⌘↩)"
        case .playAgain: "Go back to the start, then play from the top (⌃⌘↩)"
        case .tryAgain: "Try step \(step) again"
        case .skipStep: "Skip step \(step) and go on to step \(step + 1)"
        case .stop: "Stop going back to the start"
        case .continueFromStep(let target): "\(app) is already on step \(target)’s screen. Continue from there."
        case .goToStart: "Put \(app) back on \(context.start) without playing"
        case .imThere: "Check again now. BetterMeets also notices on its own once you’re there."
        case .playAnyway: "Play from the screen \(app) is on now"
        case .startOver: "Start over from the opening line. BetterMeets goes back to the start first."
        case .previousStep: "Previous step (← or ⌃⌘←). BetterMeets goes back to the start and replays up to it."
        case .nextLine: "Next line (→ or ⌃⌘→)"
        case .nextStep: "Play the next step, then pause (⌃⌘→)"
        case .testAgain: "Go back to the start and play it once to check every step"
        case .editDemo: "Edit titles and lines"
        case .renameDemo: "Rename this demo"
        case .deleteDemo: "Delete this demo…"
        case .newDemo: "Start another demo for \(app). This one stays. (⌥⌘N)"
        case .cancelNewDemo: "Go back to the demo that was open (Esc)"
        }
    }

    /// Runs the action. New, Edit, Rename and Delete move focus or open the panel's
    /// sheet or dialog, so they go through `panelRequest`.
    @MainActor func perform(on session: DemoSession) {
        switch self {
        case .build: session.build()
        case .pauseBuild, .pauseTest, .pauseDemo, .stop: session.pause()
        case .resumeBuild: session.keepBuilding()
        case .allow: session.allowPending()
        case .skip: session.skipPending()
        case .editRequest: session.editRequest()
        case .buildAlternative(let alternative): session.buildAlternative("Show \(alternative)")
        case .useSteps: session.useRecordedSteps()
        case .resumeTest, .play, .resumeDemo, .playAgain, .tryAgain, .playAnyway: session.play()
        case .continueFromStep: session.continueFromScreen()
        case .skipStep: session.skipStep()
        case .goToStart: session.returnToStart()
        case .imThere: session.checkStart()
        case .startOver: session.startOver()
        case .previousStep: session.previousStep()
        case .nextLine: session.skipLine()
        case .nextStep: session.play(singleStep: true)
        case .testAgain: session.checkAgain()
        case .editDemo: session.panelRequest = .edit
        case .renameDemo: session.panelRequest = .rename
        case .deleteDemo: session.panelRequest = .delete
        case .newDemo:
            // Stage Only has no panel to put focus in the request field.
            if BetterMeetsWindowState.shared.stageOnly { session.newDemo() } else { session.panelRequest = .new }
        case .cancelNewDemo: session.cancelNewDemo()
        }
    }

    /// The Demo menu's first item, which ⌃⌘↩ runs.
    static func menuPrimary(in phase: DemoPhase) -> PanelActionID {
        switch phase {
        case .scouting: .pauseBuild
        case .returning(.verify), .running(.verify, _, _): .pauseTest
        case .returning(.play), .running(.present, _, _): .pauseDemo
        case .returning: .stop
        case .finished: .playAgain
        case .paused(.present, _, _, _): .resumeDemo
        case .paused(.verify, _, _, _): .resumeTest
        case .offTrack: .tryAgain
        case .scoutPaused(let stop) where stop.canKeepBuilding: .resumeBuild
        case .needsStart(_, .ready), .needsStart(_, .play): .playAnyway
        default: .play
        }
    }

    /// The floating demo button. It names the build it would resume even when
    /// that build can't go on, and away from the start it takes the app there.
    static func floatingPrimary(in phase: DemoPhase) -> PanelActionID {
        switch phase {
        case .scoutPaused: .resumeBuild
        case .needsStart: .goToStart
        default: menuPrimary(in: phase)
        }
    }
}

/// An action as the panel shows it right now.
struct PanelAction: Identifiable, Equatable {
    let id: PanelActionID
    var help: String
    var isEnabled: Bool

    var title: String { id.title }
    var shortTitle: String? { id.shortTitle }
    var symbol: String? { id.symbol }
    var role: PanelActionRole { id.role }
}

/// Everything the panel's look depends on, read from the session at once.
struct DemoPanelInputs {
    var phase: DemoPhase
    var demo: RealTimeDemo?
    var appName: String
    var startLabel: String
    var isChecked = false
    var recheckSuggested = false
    var notice: String?
    var activity = ""
    var scoutedSteps = 0
    var outlineProgress: [(title: String, done: Bool)] = []
    var isLiveSourceSelected = true
    var stagePaused = false
    var teleprompterVisible = false
    var isFollowingVoice = false
    var isWritingScript = false
    var diagnosticDetails: String?
    var hasSavedDemos = false
    var buildSetup: BuildSetup?
    var asksForConsent = false
    var rewindTarget: Int?
    var canReturnAutomatically = false

    init(phase: DemoPhase, demo: RealTimeDemo?, appName: String) {
        self.phase = phase
        self.demo = demo
        self.appName = appName
        startLabel = demo?.startLabel ?? "the starting screen"
        scoutedSteps = demo.map { $0.draft.map { ScoutCompaction.compact($0.records).count } ?? $0.steps.count } ?? 0
        hasSavedDemos = demo != nil
    }

    @MainActor init(session: DemoSession, stagePaused: Bool) {
        self.init(phase: session.phase, demo: session.demo, appName: session.selectedSource?.name ?? "this app")
        isChecked = session.isChecked
        recheckSuggested = session.recheckSuggested
        notice = session.notice
        activity = session.activity
        outlineProgress = session.outlineProgress
        isLiveSourceSelected = session.isLiveSourceSelected
        self.stagePaused = stagePaused
        teleprompterVisible = session.teleprompterVisible
        isFollowingVoice = session.prompter.isFollowingVoice
        isWritingScript = session.isWritingScript
        diagnosticDetails = session.diagnosticDetails
        hasSavedDemos = !session.savedDemos.isEmpty
        buildSetup = session.buildSetup
        asksForConsent = session.asksForConsent
        rewindTarget = session.rewindTarget
        canReturnAutomatically = session.canReturnAutomatically
    }
}

/// How a library row marks its demo.
enum LibraryRowStatus: Equatable {
    case playing
    /// Running something that isn't presenting; the value says what.
    case working(String)
    case paused, tested, notTested, buildPaused, new

    var accessibilityValue: String {
        switch self {
        case .playing: "Playing"
        case .working(let doing): doing
        case .paused: "Paused"
        case .tested: "Tested"
        case .notTested: "Not tested"
        case .buildPaused: "Build paused"
        case .new: "New demo"
        }
    }

    /// A demo that isn't open shows only what it was saved as.
    static func saved(_ demo: RealTimeDemo) -> LibraryRowStatus {
        if demo.draft != nil { return .buildPaused }
        if case .checked = demo.status { return .tested }
        return .notTested
    }
}

/// One cell of the step grid.
struct StepCellModel: Identifiable, Equatable {
    enum State: Equatable {
        /// Ready and waiting, or not reached yet in a run.
        case idle, upcoming
        case recorded, recording, planned, needsApproval
        case passed, testing
        case current, done, failed
    }

    var id: String
    /// 1-based; 0 for a planned beat, which has no number yet.
    var number: Int
    var title: String
    var state: State
    /// Set when the cell is a step of a built demo, which Edit Demo can open at.
    var stepID: UUID?
    var help: String?

    var accessibilityLabel: String { number > 0 ? "Step \(number): \(title)" : title }

    var accessibilityValue: String {
        switch state {
        case .idle: ""
        case .upcoming: "Upcoming"
        case .recorded: "Recorded"
        case .recording: "Recording"
        case .planned: "Planned"
        case .needsApproval: "Needs approval"
        case .passed: "Passed"
        case .testing, .current: "Current"
        case .done: "Done"
        case .failed: "Stopped here"
        }
    }

    /// A run's position, which the overflow cell keeps in view.
    var isRunPosition: Bool { state == .current || state == .testing || state == .failed }
}

/// What the demo panel shows for one state of the session: a pure mapping, so
/// every state can be checked without drawing it.
struct DemoPanelContent: Equatable {
    enum Tint: Equatable { case accent, green, orange, secondary }

    enum Glyph: Equatable {
        case symbol(String, Tint)
        case spinner

        static var paused: Glyph { .symbol("pause.circle.fill", .orange) }
        static var stopped: Glyph { .symbol("exclamationmark.triangle.fill", .orange) }
    }

    enum PipelineStage: Int, Equatable {
        case build = 1, test
    }

    enum Headline: Equatable {
        case text(String)
        /// Build › Test › Ready, with the current stage stressed.
        case pipeline(PipelineStage)

        var plainText: String {
            switch self {
            case .text(let text): text
            case .pipeline: "Build › Test › Ready"
            }
        }

        var accessibilityText: String {
            switch self {
            case .text(let text): text
            case .pipeline(.build): "Building. Stage 1 of 3."
            case .pipeline(.test): "Testing. Stage 2 of 3."
            }
        }
    }

    struct Subline: Equatable {
        enum Kind: Equatable {
            /// Plain facts and progress; they just truncate.
            case facts
            /// Why the demo stopped; cut text gets a More link.
            case reason
            /// A notice from the last action, with an orange glyph and a More link.
            case notice
            /// "Next: …" while presenting.
            case next
        }

        var text: String
        var kind: Kind
        /// Shorter forms, tried in order when the text doesn't fit.
        var shorter: [String] = []
        var help: String?
    }

    enum GridMode: Equatable { case idle, building, test, present, finished }

    enum Body: Equatable {
        case composer
        case grid(GridMode)
        /// The current line, while presenting with the teleprompter hidden.
        case line
        /// The closing line once the demo finished, with the teleprompter hidden.
        case closing
        /// A stopped build that recorded nothing.
        case empty
    }

    enum ComposerRow: Equatable { case ideas, key, consent }

    struct BarActions: Equatable {
        /// Edit Demo… and Test Again, once the demo is built.
        var demoTools: [PanelAction] = []
        var isWritingScript = false
        var teleprompterEnabled = false
        var teleprompterHelp = ""
    }

    var glyph: Glyph
    var headline: Headline
    var subline: Subline?
    var showsCopyDetails = false
    var transport: [PanelAction] = []
    var secondaries: [PanelAction] = []
    var primary: PanelAction?
    var body: Body
    var cells: [StepCellModel] = []
    var cellsAreEditable = false
    var bar = BarActions()
    var libraryStatus: LibraryRowStatus?
    var composerRow = ComposerRow.ideas
    /// What VoiceOver calls the detail region: the open demo's title.
    var detailLabel = "New demo"

    static func make(_ inputs: DemoPanelInputs) -> DemoPanelContent {
        Mapper(inputs: inputs).content
    }

    // MARK: Announcements

    /// What VoiceOver announces when the panel moves on from `previous`. Only a
    /// change of phase kind speaks; steps moving within a run stay quiet.
    static func announcement(from previous: DemoPhase, to inputs: DemoPanelInputs) -> String? {
        let phase = inputs.phase
        guard PhaseKind(previous) != PhaseKind(phase) else { return nil }
        let app = inputs.appName
        switch phase {
        case .scouting:
            return "Building the demo."
        case .scoutPaused(let stop):
            switch stop {
            case .needsApproval(let pending): return "Needs your approval. \(pending.message)"
            case .blocked(let reason, _): return "Can’t show that in \(app). \(reason)"
            case .limit(let limit): return "Build stopped. \(limit.message)"
            case .error(let error): return "Build stopped. \(error.localizedDescription)"
            default: return "Build paused."
            }
        case .returning(.verify), .running(.verify, _, _):
            return isTest(previous) ? nil : "Testing the demo."
        case .ready:
            switch previous {
            case .scouting, .returning(.verify), .running(.verify, _, _):
                return inputs.isChecked ? "Tested. Ready to play." : "Ready, not tested."
            default:
                return nil
            }
        case .needsStart:
            return "\(app) isn’t at the start."
        case .running(.present, _, _):
            return previous.replayMode == .present ? nil : "Playing."
        case .paused(let mode, let next, let current, _):
            let step = Mapper(inputs: inputs).position(next: next, current: current)
            return mode == .verify ? "Test paused at step \(step)." : "Paused at step \(step)."
        case .offTrack(_, let index, _):
            let message = make(inputs).subline?.text ?? ""
            return "Stopped at step \(index + 1). \(message)"
        case .finished:
            return "Demo finished."
        case .composing, .returning:
            return nil
        }
    }

    /// The phase the next announcement compares against. Going back to the start
    /// on the way to ready keeps the phase before it, so a finished test still
    /// announces its result, and Go to Start after a pause stays quiet.
    static func announcementBase(previous: DemoPhase, next: DemoPhase) -> DemoPhase {
        if case .returning(let then) = next, then == .ready || then == .compose { return previous }
        return next
    }

    private static func isTest(_ phase: DemoPhase) -> Bool {
        phase.replayMode == .verify || phase == .returning(then: .verify)
    }

    private enum PhaseKind: Equatable {
        case composing, scouting, scoutPaused, needsStart, ready, finished
        case returning(AfterReturn)
        case running(ReplayMode), paused(ReplayMode), offTrack(ReplayMode)

        init(_ phase: DemoPhase) {
            self =
                switch phase {
                case .composing: .composing
                case .scouting: .scouting
                case .scoutPaused: .scoutPaused
                case .returning(let then): .returning(then)
                case .needsStart: .needsStart
                case .ready: .ready
                case .running(let mode, _, _): .running(mode)
                case .paused(let mode, _, _, _): .paused(mode)
                case .offTrack(let mode, _, _): .offTrack(mode)
                case .finished: .finished
                }
        }
    }
}

// MARK: - Mapping

private struct Mapper {
    let inputs: DemoPanelInputs

    private var app: String { inputs.appName }
    private var start: String { inputs.startLabel }
    private var live: Bool { inputs.isLiveSourceSelected }
    private var count: Int { inputs.demo?.steps.count ?? 0 }
    private var isCompiled: Bool { inputs.demo?.isCompiled == true }
    private var isBusy: Bool { inputs.phase.isActuating }
    private var notLiveHelp: String { inputs.stagePaused ? "Resume the stage first" : "Put \(app) on stage first" }

    private func action(_ id: PanelActionID, enabled: Bool = true, step: Int = 1) -> PanelAction {
        let help = !enabled && !live ? notLiveHelp : id.help(.init(app: app, start: start, step: step))
        return PanelAction(id: id, help: help, isEnabled: enabled)
    }

    private func steps(_ count: Int) -> String { count == 1 ? "1 step" : "\(count) steps" }

    /// The 1-based step a run is on.
    func position(next: Int, current: Int?) -> Int {
        min((current ?? next) + 1, max(count, 1))
    }

    private func reason(_ text: String) -> DemoPanelContent.Subline { .init(text: text, kind: .reason) }

    /// Shows an error: the stopped glyph, its message, and Copy Details when there are details to copy.
    private func showError(_ error: DemoError, in content: inout DemoPanelContent) {
        content.glyph = .stopped
        content.subline = reason(error.localizedDescription)
        content.showsCopyDetails = inputs.diagnosticDetails != nil
    }

    private func notFound(_ name: String) -> DemoPanelContent.Subline {
        reason("Couldn’t find “\(name)”. It may have moved or been renamed.")
    }

    var content: DemoPanelContent {
        var content: DemoPanelContent
        switch inputs.phase {
        case .composing:
            content = composing
        case .scouting:
            let doing = inputs.activity.isEmpty ? "Working" : String(inputs.activity.prefix(50))
            let recorded = inputs.scoutedSteps
            content = DemoPanelContent(
                glyph: .spinner, headline: .pipeline(.build),
                subline: .init(
                    text: recorded > 0 ? "\(steps(recorded)) so far · \(doing)…" : "\(doing)…", kind: .facts),
                body: .grid(.building))
            content.primary = action(.pauseBuild)
        case .scoutPaused(let stop):
            content = scoutPaused(stop)
        case .returning(let then):
            content = returning(then)
        case .needsStart(let mismatch, let then):
            content = needsStart(mismatch, then: then)
        case .ready:
            content = ready
        case .running(.verify, let next, let current):
            let step = position(next: next, current: current)
            content = DemoPanelContent(
                glyph: .spinner, headline: .pipeline(.test),
                subline: .init(text: "Testing step \(step) of \(count)…", kind: .facts), body: .grid(.test))
            content.primary = action(.pauseTest)
        case .paused(.verify, let next, let current, let pause):
            content = pausedTest(step: position(next: next, current: current), reason: pause)
        case .offTrack(.verify, let index, let mismatch):
            content = stoppedTest(index: index, mismatch: mismatch)
        case .running(.present, let next, let current):
            content = presenting(next: next, current: current)
        case .paused(.present, let next, let current, let pause):
            content = pausedDemo(next: next, current: current, reason: pause)
        case .offTrack(.present, let index, let mismatch):
            content = stoppedDemo(index: index, mismatch: mismatch)
        case .finished:
            content = finished
        }
        if let title = inputs.demo?.title { content.detailLabel = title }
        content.cells = cells(for: content.body)
        if content.cells.isEmpty, case .scoutPaused = inputs.phase { content.body = .empty }
        content.cellsAreEditable = isCompiled && !isBusy
        content.bar = bar
        content.libraryStatus = libraryStatus
        return content
    }

    // MARK: Composing

    private var composing: DemoPanelContent {
        let isFirst = !inputs.hasSavedDemos || !live
        let row: DemoPanelContent.ComposerRow =
            inputs.buildSetup == .key ? .key : inputs.asksForConsent ? .consent : .ideas
        var subline: DemoPanelContent.Subline?
        // A setup row explains itself, so the band says nothing more.
        if row == .ideas {
            if let notice = inputs.notice {
                subline = .init(text: notice, kind: .notice)
            } else if !live {
                subline = reason(
                    inputs.stagePaused
                        ? "The stage is paused. Resume it to build a demo."
                        : "Put an app on stage to build a demo of it.")
            } else {
                subline = .init(
                    text: inputs.hasSavedDemos
                        ? "Describe a flow. Claude builds it in \(app) and tests it."
                        : "Describe a flow. Claude builds it in \(app), tests it, and gets it ready to present.",
                    kind: .facts)
            }
        }
        var content = DemoPanelContent(
            glyph: isFirst ? .symbol("play.rectangle.fill", .accent) : .symbol("square.and.pencil", .secondary),
            headline: .text(isFirst ? "Real-time demos" : "New demo"), subline: subline, body: .composer)
        content.composerRow = row
        return content
    }

    // MARK: Building

    private func scoutPaused(_ stop: ScoutStop) -> DemoPanelContent {
        let recorded = inputs.scoutedSteps
        let useSteps = action(.useSteps(recorded), enabled: live && inputs.demo?.start != nil)
        let editRequest = action(.editRequest)
        let soFar = recorded > 0 ? [useSteps] : []
        var content = DemoPanelContent(
            glyph: .paused, headline: .text("Build paused"), body: .grid(.building))
        content.secondaries = soFar + [editRequest]
        content.primary = action(.resumeBuild, enabled: live)
        switch stop {
        case .user:
            content.subline = reason(
                recorded > 0
                    ? "\(steps(recorded)) so far. Resume to keep building from this screen."
                    : "Resume to keep building from this screen.")
        case .userInput:
            content.subline = reason("You clicked or typed in \(app), so the build paused.")
        case .focusLost:
            content.subline = reason("\(app) lost focus, so the build paused.")
        case .relaunched:
            content.subline = reason(
                recorded > 0
                    ? "This build was interrupted. Resume it from the current screen, or use the steps so far."
                    : "This build was interrupted. Resume it from the current screen.")
        case .leftScope(let why):
            content.subline = reason("\(why) Close it and come back to \(app) to resume.")
        case .error(let error):
            content.headline = .text("Build stopped")
            showError(error, in: &content)
        case .needsApproval(let pending):
            content.glyph = .symbol("hand.raised.fill", .orange)
            content.headline = .text("Needs your approval")
            content.subline = reason(pending.message)
            content.secondaries = [action(.skip, enabled: live)]
            content.primary = action(.allow, enabled: live)
        case .blocked(let why, let alternative):
            content.glyph = .stopped
            content.headline = .text("Can’t show that in \(app)")
            if alternative.isEmpty {
                content.subline = reason(why)
                content.secondaries = soFar
                content.primary = editRequest
            } else {
                content.subline = reason("\(why) It can show \(alternative) instead.")
                content.secondaries = [editRequest] + soFar
                content.primary = action(.buildAlternative(alternative), enabled: live)
            }
            if recorded == 0 { content.body = .empty }
        case .limit(let limit):
            content.glyph = .stopped
            content.headline = .text("Build stopped")
            if recorded > 0 {
                content.subline = reason(
                    "\(limit.message) Use the \(steps(recorded)) so far, or edit your request.")
                content.secondaries = [editRequest]
                content.primary = useSteps
            } else {
                content.subline = reason("\(limit.message) Edit your request to try again.")
                content.secondaries = []
                content.primary = editRequest
                content.body = .empty
            }
        }
        return content
    }

    // MARK: Start

    private func returning(_ then: AfterReturn) -> DemoPanelContent {
        var content = DemoPanelContent(
            glyph: .spinner, headline: .text("Going to the start"), body: .grid(.idle))
        switch then {
        case .verify:
            content.headline = .pipeline(.test)
            content.subline = .init(text: "Going to \(start) before the test…", kind: .facts)
            content.primary = action(.pauseTest)
        case .play:
            let target = inputs.rewindTarget ?? 0
            content.subline = .init(
                text: target > 0
                    ? "Then it replays quickly up to step \(target + 1)." : "Then the demo plays from the top.",
                kind: .facts)
            content.primary = action(.pauseDemo)
        case .ready, .compose:
            content.subline = .init(text: "Putting \(app) back on \(start)…", kind: .facts)
            content.primary = action(.stop)
        }
        return content
    }

    private func needsStart(_ mismatch: StartMismatch, then: AfterReturn) -> DemoPanelContent {
        let isChecking = !inputs.activity.isEmpty
        var content = DemoPanelContent(
            glyph: isChecking ? .spinner : .symbol("exclamationmark.circle.fill", .orange),
            headline: .text("Not at the start"), body: .grid(.idle))
        let playAnyway = then == .ready || then == .play ? [action(.playAnyway, enabled: live)] : []
        let goToStart = action(.goToStart, enabled: live)
        let imThere = action(.imThere, enabled: live)
        let text: String
        switch mismatch {
        case .wrongScreen:
            text =
                switch then {
                case .play: "\(app) isn’t on \(start). Go to Start takes it there, then the demo plays."
                case .verify: "\(app) isn’t on \(start), so the test can’t begin."
                case .ready, .compose: "\(app) isn’t on \(start)."
                }
            content.secondaries = playAnyway
            content.primary = goToStart
        case .togglesDiffer(let names):
            text = "Turn \(ListFormatter.localizedString(byJoining: names)) back to how the demo starts."
            content.secondaries = playAnyway + [imThere]
            content.primary = goToStart
        case .webContentUnavailable:
            text = DemoError.webContentUnavailable(inputs.demo?.app.engine ?? .chromium).localizedDescription
            content.secondaries = playAnyway
            content.primary = imThere
        case .noAutomaticReturn:
            let after =
                switch then {
                case .play: "The demo plays once you’re there."
                case .verify: "The test begins once you’re there."
                case .ready, .compose: "BetterMeets notices once you’re there."
                }
            text = (inputs.notice.map { $0 + " " } ?? "") + "Go to \(start) in \(app). \(after)"
            content.secondaries = playAnyway + (inputs.canReturnAutomatically ? [goToStart] : [])
            content.primary = imThere
        }
        content.subline = isChecking ? .init(text: inputs.activity + "…", kind: .facts) : reason(text)
        return content
    }

    // MARK: Ready

    private var checkedGlyph: DemoPanelContent.Glyph {
        inputs.isChecked ? .symbol("checkmark.seal.fill", .green) : .symbol("circle.dashed", .secondary)
    }

    private var ready: DemoPanelContent {
        var content = DemoPanelContent(
            glyph: checkedGlyph, headline: .text(inputs.demo?.title ?? ""), body: .grid(.idle))
        if !live {
            content.subline = reason(
                inputs.stagePaused
                    ? "The stage is paused. Resume it to play this demo." : "Put \(app) on stage to play this demo.")
        } else if let notice = inputs.notice {
            content.subline = .init(text: notice, kind: .notice)
        } else if inputs.recheckSuggested {
            content.subline = reason("A step moved during the last run. Test again to keep it tested.")
        } else {
            content.subline = facts
        }
        content.primary = action(.play, enabled: live && isCompiled)
        return content
    }

    /// Tested · 9 steps · About 2 min · Starts on the Scheduled page. Narrow
    /// widths drop the duration first, then the start.
    private var facts: DemoPanelContent.Subline {
        let status = inputs.isChecked ? "Tested" : "Not tested"
        let seconds = inputs.demo?.estimatedSeconds ?? 0
        let duration = seconds < 60 ? "Under 1 min" : "About \(Int((Double(seconds) / 60).rounded(.up))) min"
        let startsOn = "Starts on \(start)"
        return .init(
            text: [status, steps(count), duration, startsOn].joined(separator: " · "), kind: .facts,
            shorter: [
                [status, steps(count), startsOn].joined(separator: " · "),
                [status, steps(count)].joined(separator: " · ")
            ],
            help: inputs.demo?.start.map { "Starts on: \($0.description)" })
    }

    // MARK: Testing

    private func pausedTest(step: Int, reason pause: PauseReason) -> DemoPanelContent {
        var content = DemoPanelContent(
            glyph: .paused, headline: .text("Test paused at step \(step) of \(count)"),
            body: .grid(.test))
        switch pause {
        case .user:
            content.subline = reason("Resume Test finishes the test from step \(step).")
        case .userInput:
            content.subline = reason("You clicked or typed in \(app), so the test paused.")
        case .sourceChanged:
            content.subline = reason("The shared window changed, so the test paused.")
        case .error(let error):
            showError(error, in: &content)
        }
        content.secondaries = [action(.goToStart, enabled: live)]
        content.primary = action(.resumeTest, enabled: live && isCompiled, step: step)
        return content
    }

    private func stoppedTest(index: Int, mismatch: Mismatch) -> DemoPanelContent {
        var content = DemoPanelContent(
            glyph: .stopped,
            headline: .text("Test stopped at step \(index + 1) of \(count)"), body: .grid(.test))
        content.subline =
            switch mismatch {
            case .targetNotFound(let name): notFound(name)
            case .wrongScreen(let step): reason("\(app) is on step \(step + 1)’s screen, not step \(index + 1)’s.")
            case .blocked(let error): reason(error.localizedDescription)
            }
        content.secondaries = [action(.goToStart, enabled: live)]
        content.primary = action(.tryAgain, enabled: live && isCompiled, step: index + 1)
        return content
    }

    // MARK: Presenting

    private var presentBody: DemoPanelContent.Body { inputs.teleprompterVisible ? .grid(.present) : .line }

    private func isOpeningLine(next: Int, current: Int?) -> Bool {
        current == nil && next == 0 && inputs.demo?.openingScript?.isEmpty == false
    }

    /// "Next: …" for the step after the current one, or what follows the last.
    private func upNext(next: Int, current: Int?) -> String {
        let steps = inputs.demo?.steps ?? []
        if isOpeningLine(next: next, current: current) { return "Next: \(steps.first?.title ?? "")" }
        let following = (current ?? next) + 1
        if steps.indices.contains(following) { return "Next: \(steps[following].title)" }
        return inputs.demo?.closingScript.isEmpty == false ? "Next: closing line" : "Last step"
    }

    private func transport(step: Int, atOpening: Bool = false, next: PanelAction) -> [PanelAction] {
        [
            action(.startOver, enabled: live),
            action(.previousStep, enabled: live && step > 1 && !atOpening),
            next
        ]
    }

    private func presenting(next: Int, current: Int?) -> DemoPanelContent {
        let step = position(next: next, current: current)
        let atOpening = isOpeningLine(next: next, current: current)
        var content = DemoPanelContent(
            glyph: .symbol(inputs.isFollowingVoice ? "waveform" : "play.fill", .accent),
            headline: .text(atOpening ? "Opening line" : "Step \(step) of \(count)"),
            subline: .init(text: upNext(next: next, current: current), kind: .next), body: presentBody)
        content.transport = transport(step: step, atOpening: atOpening, next: action(.nextLine))
        content.primary = action(.pauseDemo)
        return content
    }

    private func pausedDemo(next: Int, current: Int?, reason pause: PauseReason) -> DemoPanelContent {
        let step = position(next: next, current: current)
        var content = DemoPanelContent(
            glyph: .paused, headline: .text("Paused at step \(step) of \(count)"),
            body: presentBody)
        switch pause {
        case .user:
            content.subline = .init(text: upNext(next: next, current: current), kind: .next)
        case .userInput:
            content.subline = reason("You clicked or typed in \(app), so the demo paused.")
        case .sourceChanged:
            content.subline = reason("The shared window changed, so the demo paused.")
        case .error(let error):
            showError(error, in: &content)
        }
        content.transport = transport(step: step, next: action(.nextStep, enabled: live))
        content.primary = action(.resumeDemo, enabled: live && isCompiled, step: step)
        return content
    }

    private func stoppedDemo(index: Int, mismatch: Mismatch) -> DemoPanelContent {
        let step = index + 1
        var content = DemoPanelContent(
            glyph: .stopped,
            headline: .text("Stopped at step \(step) of \(count)"), body: presentBody)
        content.transport = transport(step: step, next: action(.nextStep, enabled: false))
        let skipStep = action(.skipStep, enabled: live, step: step)
        let tryAgain = action(.tryAgain, enabled: live && isCompiled, step: step)
        switch mismatch {
        case .targetNotFound(let name):
            content.subline = notFound(name)
            content.secondaries = [skipStep]
            content.primary = tryAgain
        case .blocked(let error):
            content.subline = reason(error.localizedDescription)
            content.secondaries = [skipStep]
            content.primary = tryAgain
        case .wrongScreen(let onStep):
            content.subline = reason("\(app) is already on step \(onStep + 1)’s screen.")
            content.secondaries = [skipStep, tryAgain]
            content.primary = action(.continueFromStep(onStep + 1), enabled: live)
        }
        return content
    }

    private var finished: DemoPanelContent {
        var content = DemoPanelContent(
            glyph: .symbol("flag.checkered", .secondary), headline: .text("Demo finished"),
            body: inputs.teleprompterVisible ? .grid(.finished) : .closing)
        if let notice = inputs.notice {
            content.subline = .init(text: notice, kind: .notice)
        } else if inputs.recheckSuggested {
            content.subline = reason("A step moved during this run. Test again to keep it tested.")
        } else {
            content.subline = .init(
                text: "Played all \(steps(count)). Play Again goes back to the start first.", kind: .facts)
        }
        var startOver = action(.startOver, enabled: false)
        startOver.help = "Play Again does this"
        content.transport = [startOver, action(.previousStep, enabled: live), action(.nextStep, enabled: false)]
        content.primary = action(.playAgain, enabled: live && isCompiled)
        return content
    }

    // MARK: Steps

    private func cells(for body: DemoPanelContent.Body) -> [StepCellModel] {
        guard case .grid(let mode) = body, let demo = inputs.demo else { return [] }
        guard let draft = demo.draft else {
            return demo.steps.enumerated().map { index, step in
                StepCellModel(
                    id: step.id.uuidString, number: index + 1, title: step.title, state: state(index, mode: mode),
                    stepID: step.id, help: help(for: step))
            }
        }
        let recorded = ScoutCompaction.compact(draft.records)
        var cells = recorded.enumerated().map { index, step in
            StepCellModel(
                id: step.id.uuidString, number: index + 1, title: step.title, state: .recorded,
                help: help(for: step))
        }
        let isScouting = inputs.phase == .scouting
        if isScouting {
            cells.append(
                StepCellModel(id: "recording", number: recorded.count + 1, title: "Recording…", state: .recording))
        }
        if case .scoutPaused(.needsApproval(let pending)) = inputs.phase {
            cells.append(
                StepCellModel(
                    id: "approval", number: recorded.count + 1, title: pending.title, state: .needsApproval,
                    help: pending.message))
        }
        let isBuilding =
            switch inputs.phase {
            case .scouting, .scoutPaused: true
            default: false
            }
        if isBuilding {
            for (offset, beat) in inputs.outlineProgress.enumerated() where !beat.done {
                cells.append(StepCellModel(id: "planned-\(offset)", number: 0, title: beat.title, state: .planned))
            }
        }
        return cells
    }

    /// A step cell's tooltip: its line, or what kind of step it is.
    private func help(for step: DemoStep) -> String {
        step.script.isEmpty ? step.action.kindLabel : step.script
    }

    private func state(_ index: Int, mode: DemoPanelContent.GridMode) -> StepCellModel.State {
        switch (mode, inputs.phase) {
        case (.finished, _):
            return .done
        case (.test, .running(.verify, let next, let current)):
            if index == current { return .testing }
            return index < next ? .passed : .upcoming
        case (.test, .paused(.verify, let next, let current, _)):
            let at = current ?? next
            return index == at ? .current : index < at ? .passed : .upcoming
        case (.test, .offTrack(.verify, let failed, _)):
            return index == failed ? .failed : index < failed ? .passed : .upcoming
        case (.present, .running(.present, let next, let current)),
            (.present, .paused(.present, let next, let current, _)):
            if isOpeningLine(next: next, current: current) { return .upcoming }
            let at = current ?? next
            return index == at ? .current : index < at ? .done : .upcoming
        case (.present, .offTrack(.present, let failed, _)):
            return index == failed ? .failed : index < failed ? .done : .upcoming
        default:
            return .idle
        }
    }

    // MARK: Bar and library

    private var bar: DemoPanelContent.BarActions {
        var bar = DemoPanelContent.BarActions()
        if isCompiled {
            bar.demoTools = [action(.editDemo, enabled: !isBusy), action(.testAgain, enabled: !isBusy && live)]
        }
        bar.isWritingScript = inputs.isWritingScript
        bar.teleprompterEnabled = isCompiled || inputs.teleprompterVisible
        bar.teleprompterHelp =
            !bar.teleprompterEnabled
            ? "Available once the demo is built"
            : inputs.teleprompterVisible ? "Hide the teleprompter (⌃⌘N)" : "Show your lines under the camera (⌃⌘N)"
        return bar
    }

    private var libraryStatus: LibraryRowStatus? {
        guard let demo = inputs.demo else { return inputs.phase == .composing ? .new : nil }
        if demo.draft != nil {
            guard isBusy else { return .buildPaused }
            return .working(inputs.phase == .scouting ? "Building" : "Going to the start")
        }
        switch inputs.phase {
        case .running(.present, _, _): return .playing
        case .running(.verify, _, _), .returning(.verify): return .working("Testing")
        case .returning: return .working("Going to the start")
        case .paused, .offTrack: return .paused
        default: return inputs.isChecked ? .tested : .notTested
        }
    }
}
