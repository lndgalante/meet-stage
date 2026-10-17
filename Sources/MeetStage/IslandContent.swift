import Foundation

/// How much of the teleprompter island is out.
enum IslandMode: Equatable {
    /// As tall as the menu bar: a short status beside the camera.
    case compact
    /// The line to read, where the demo is, and the controls.
    case expanded

    /// Expanded while there's a line the demo can present; a finished demo
    /// stays open for Play Again even without a closing line.
    static func make(phase: DemoPhase, line: PresenterPrompter.Line?) -> IslandMode {
        switch phase {
        case .finished:
            .expanded
        case .ready, .needsStart(_, then: .ready), .needsStart(_, then: .play), .returning(then: .play),
            .running(.present, _, _), .paused(.present, _, _, _), .offTrack(.present, _, _):
            line == nil ? .compact : .expanded
        default:
            .compact
        }
    }
}

/// Everything the island's look depends on, read from the session at once.
struct IslandInputs {
    var phase: DemoPhase
    /// The demo panel for the same state. The island takes its actions, help and
    /// reasons from it, so the two never disagree.
    var panel: DemoPanelContent
    var line: PresenterPrompter.Line?
    var position: (current: Int, total: Int)?
    var heading = ""
    var upNext: String?
    var hasClosing = false
    var followsVoice = true
    var voice = SpeechListener.State.off
    var followerIsEmpty = false
    var followerIsComplete = false
    var hold: (start: Date, seconds: Double)?
}

extension IslandInputs {
    /// `panel`, when given, is the session's panel content built already.
    @MainActor init(session: DemoSession, panel: DemoPanelContent? = nil) {
        let prompter = session.prompter
        self.init(
            phase: session.phase,
            panel: panel ?? .make(DemoPanelInputs(session: session, stagePaused: session.stagePaused)),
            line: prompter.line, position: prompter.position, heading: prompter.heading, upNext: prompter.upNext,
            hasClosing: session.demo?.closingScript.isEmpty == false, followsVoice: prompter.followsVoice,
            voice: prompter.listener.state, followerIsEmpty: prompter.follower.isEmpty,
            followerIsComplete: prompter.follower.isComplete, hold: prompter.hold)
    }
}

/// What the teleprompter island shows for one state of the session: a pure
/// mapping, so every state can be checked without drawing it.
struct IslandContent: Equatable {
    /// The glyph before the band's left text.
    enum Mark: Equatable {
        /// `pause.fill`.
        case paused
        /// Orange `exclamationmark.triangle.fill`.
        case stopped
        /// Orange `exclamationmark.circle.fill`.
        case notAtStart
        case spinner
        /// Green `checkmark.circle.fill`.
        case done
    }

    /// The band's right slot: what comes after this line.
    struct Upcoming: Equatable {
        /// "Next", or nil when nothing follows ("Last step").
        var label: String?
        var title: String

        var accessibilityLabel: String { label.map { "\($0): \(title)" } ?? title }
    }

    /// How the line's words are marked.
    enum Words: Equatable {
        /// All white: a preview, a timed hold, or the closing line.
        case uniform
        /// Words already said dim. With `marksNext`, only while listening, the next word is underlined.
        case followed(marksNext: Bool)
        /// Every word said: the line is done and the demo is moving on.
        case allSaid
    }

    enum Body: Equatable {
        /// The current line. `dim` while it isn't live: paused, stopped, not at the start, or going back.
        case line(Words, dim: Bool)
        /// A step with no line: `PresenterPrompter.noLineText`.
        case noLine(dim: Bool)
        /// Nothing left to say, such as `PresenterPrompter.finishedText`.
        case message(String)
    }

    enum Meter: Equatable {
        case hidden
        /// Bars follow the microphone; lit bars show how much of the line is said.
        case voice
        /// Flat dots lit by a timed hold's progress.
        case timed(start: Date, seconds: Double)
        /// Flat, unlit dots: timed, before the step's hold starts.
        case dots
        /// Every bar lit: the line is done.
        case full
    }

    enum Tone: Equatable {
        case plain
        /// Orange, with a warning glyph.
        case warning
    }

    enum Status: Equatable {
        case none
        case text(String, Tone, help: String? = nil)
        /// The last words heard (`PresenterPrompter.heardTail`), or "Listening" before the first.
        case heard
        /// "Moves on in 3 s".
        case countdown(start: Date, seconds: Double)
    }

    var mode: IslandMode
    var mark: Mark?
    /// "2/6" before the title, in monospaced digits.
    var position: String?
    /// The step's title, Opening, Wrap up, or what the compact island is doing.
    var place: String
    var placeHelp: String
    var placeAccessibility: String
    var next: Upcoming?
    /// Nil in the compact island.
    var body: Body?
    var meter = Meter.hidden
    var status = Status.none
    /// Start Over, Previous Step, the primary and the forward action whenever
    /// the island is expanded; empty when compact.
    var slots: [PanelAction] = []
    /// Further actions for the options menu.
    var extras: [PanelAction] = []
    /// Off track: an orange edge around the island.
    var stoppedEdge = false

    static func make(_ inputs: IslandInputs) -> IslandContent {
        IslandMapper(inputs: inputs).content
    }

    /// Four fixed places: Start Over, Previous Step, the primary, and forward.
    /// They're disabled, never removed, so no control ever moves. Off track,
    /// Skip Step takes the forward place, and the panel's other secondaries go
    /// to the options menu.
    static func slots(_ panel: DemoPanelContent, phase: DemoPhase) -> (slots: [PanelAction], extras: [PanelAction]) {
        let primary = panel.primary ?? PanelAction(id: .play, help: "", isEnabled: false)
        var extras = panel.secondaries
        guard panel.transport.count == 3 else {
            let later = "Available while the demo plays"
            let startOverHelp = phase == .ready ? "Play does this" : later
            let startOver = PanelAction(id: .startOver, help: startOverHelp, isEnabled: false)
            let previous = PanelAction(id: .previousStep, help: later, isEnabled: false)
            let next = PanelAction(id: .nextLine, help: later, isEnabled: false)
            return ([startOver, previous, primary, next], extras)
        }
        var forward = panel.transport[2]
        if case .offTrack = phase, let index = extras.firstIndex(where: { $0.id == .skipStep }) {
            forward = extras.remove(at: index)
        }
        return ([panel.transport[0], panel.transport[1], primary, forward], extras)
    }
}

extension PanelAction {
    /// The island draws every slot as a glyph; the panel keeps these few as text.
    var islandSymbol: String { symbol ?? (id == .skipStep ? "forward.end.fill" : "play.fill") }
}

// MARK: - Mapping

private struct IslandMapper {
    let inputs: IslandInputs

    private var panel: DemoPanelContent { inputs.panel }

    /// How the prompter follows the presenter right now.
    private enum Voice: Equatable {
        case listening
        case preparing(String?)
        case unavailable(String)
        case timed

        var isFollowing: Bool {
            switch self {
            case .listening, .preparing: true
            case .unavailable, .timed: false
            }
        }
    }

    private var voice: Voice {
        guard inputs.followsVoice else { return .timed }
        return switch inputs.voice {
        case .listening: .listening
        case .preparing(let text): .preparing(text)
        case .unavailable(let reason): .unavailable(reason)
        // Off while following: starting up, unless the prompter fell back to its timer.
        case .off: inputs.hold == nil ? .preparing(nil) : .timed
        }
    }

    var content: IslandContent {
        IslandMode.make(phase: inputs.phase, line: inputs.line) == .expanded ? expanded : compact
    }

    // MARK: Compact

    private var compact: IslandContent {
        let (mark, text): (IslandContent.Mark?, String) =
            switch inputs.phase {
            case .scouting: (.spinner, "Building")
            case .returning(.verify), .running(.verify, _, _): (.spinner, "Testing")
            case .paused(.verify, _, _, _): (.paused, "Test paused")
            case .offTrack(.verify, _, _): (.stopped, "Test stopped")
            case .returning: (.spinner, "Going back")
            case .needsStart: (panel.glyph == .spinner ? .spinner : .notAtStart, "Not at start")
            default: (nil, "No lines yet")
            }
        let help = mark == nil ? "Your lines appear here once the demo is built." : text
        return IslandContent(mode: .compact, mark: mark, place: text, placeHelp: help, placeAccessibility: text)
    }

    // MARK: Expanded

    private var expanded: IslandContent {
        let place = self.place
        var content = IslandContent(
            mode: .expanded, position: place.position, place: place.title,
            placeHelp: [place.position, place.title].compactMap { $0 }.joined(separator: " "),
            placeAccessibility: place.accessibility, next: upcoming)
        (content.slots, content.extras) = IslandContent.slots(panel, phase: inputs.phase)
        let frozen = IslandContent.Words.followed(marksNext: false)
        switch inputs.phase {
        case .ready:
            content.body = line(.uniform, dim: false)
            content.status = readyStatus
        case .needsStart:
            content.mark = panel.glyph == .spinner ? .spinner : .notAtStart
            content.body = line(.uniform, dim: true)
            content.status = panelStatus(.plain)
        case .returning:
            content.mark = .spinner
            content.placeAccessibility += ", going back"
            content.body = line(.uniform, dim: true)
            content.status = .text(
                [panel.headline.plainText + ".", panel.subline?.text].compactMap { $0 }.joined(separator: " "), .plain)
        case .running:
            guard let target = catchUpTarget else {
                playing(&content)
                break
            }
            content.mark = .spinner
            content.placeAccessibility += ", going back"
            content.body = line(.uniform, dim: true)
            content.status = .text("Replaying up to step \(target + 1)…", .plain)
        case .paused(_, _, _, let reason):
            content.mark = .paused
            content.placeAccessibility += ", paused"
            content.body = line(frozen, dim: true)
            if reason == .user {
                content.status = .text("Paused", .plain)
            } else if case .error = reason {
                content.status = panelStatus(.warning)
            } else {
                content.status = panelStatus(.plain)
            }
        case .offTrack:
            content.mark = .stopped
            content.placeAccessibility += ", stopped"
            content.body = line(frozen, dim: true)
            content.status = panelStatus(.warning)
            content.stoppedEdge = true
        case .finished:
            if inputs.line == nil {
                content.mark = .done
                content.body = .message(PresenterPrompter.finishedText)
            } else {
                content.body = line(.uniform, dim: false)
            }
            content.status = panelStatus(panel.subline?.kind == .notice ? .warning : .plain)
        case .composing, .scouting, .scoutPaused:
            break
        }
        return content
    }

    /// Following the presenter through the line: what's said, the meter, and why it waits.
    private func playing(_ content: inout IslandContent) {
        let voice = self.voice
        let timer = inputs.hold.map { IslandContent.Meter.timed(start: $0.start, seconds: $0.seconds) } ?? .dots
        if inputs.followerIsEmpty {
            content.body = .noLine(dim: false)
            content.meter = voice.isFollowing ? .voice : timer
        } else if inputs.followerIsComplete {
            content.body = .line(.allSaid, dim: false)
            content.meter = .full
        } else {
            switch voice {
            case .listening:
                content.body = .line(.followed(marksNext: true), dim: false)
                content.meter = .voice
            case .preparing:
                // Keeps what was said if the microphone reconnects mid-line.
                content.body = .line(.followed(marksNext: false), dim: false)
                content.meter = .voice
            case .unavailable, .timed:
                content.body = .line(.uniform, dim: false)
                content.meter = timer
            }
        }
        // An empty line moves on by itself only while following; timed, it waits out its hold.
        let movingOn = inputs.followerIsEmpty ? voice.isFollowing : inputs.followerIsComplete
        if case .unavailable(let reason) = voice {
            content.status = .text("Mic unavailable", .warning, help: reason)
        } else if movingOn {
            content.status = .text("Moving on…", .plain)
        } else if case .preparing(let text?) = voice {
            content.status = .text(text, .plain)
        } else if voice == .timed, let hold = inputs.hold {
            content.status = .countdown(start: hold.start, seconds: hold.seconds)
        } else if voice == .listening {
            content.status = .heard
        }
    }

    // MARK: Parts

    /// Where the line is: its position and title, Opening, or Wrap up. With no
    /// line, only a finished demo is expanded.
    private var place: (position: String?, title: String, accessibility: String) {
        switch inputs.line {
        case .opening:
            return (nil, "Opening", "Opening line")
        case .closing:
            return (nil, "Wrap up", "Closing line")
        case .step:
            let title = inputs.heading
            guard let position = inputs.position else { return (nil, title, title) }
            let step = "Step \(position.current) of \(position.total)"
            return ("\(position.current)/\(position.total)", title, title.isEmpty ? step : "\(step), \(title)")
        case nil:
            return (nil, "Done", "Done")
        }
    }

    private var upcoming: IslandContent.Upcoming? {
        guard inputs.phase != .finished, inputs.line != .closing else { return nil }
        if let next = inputs.upNext { return .init(label: "Next", title: next) }
        return inputs.hasClosing ? .init(label: "Next", title: "Wrap up") : .init(label: nil, title: "Last step")
    }

    private func line(_ words: IslandContent.Words, dim: Bool) -> IslandContent.Body {
        inputs.followerIsEmpty ? .noLine(dim: dim) : .line(words, dim: dim)
    }

    /// While going back to an earlier step, the step it replays up to: the line
    /// already shows it while the run is still on an earlier step.
    private var catchUpTarget: Int? {
        guard case .running(.present, let next, let current) = inputs.phase, case .step(let target) = inputs.line,
            (current ?? next) < target
        else { return nil }
        return target
    }

    /// The panel's notice or reason, else how the demo will pace itself.
    private var readyStatus: IslandContent.Status {
        if let subline = panel.subline, subline.kind == .notice || subline.kind == .reason {
            return .text(subline.text, subline.kind == .notice ? .warning : .plain)
        }
        return .text(inputs.followsVoice ? "Follows your voice" : "Timed at speaking pace", .plain)
    }

    private func panelStatus(_ tone: IslandContent.Tone) -> IslandContent.Status {
        panel.subline.map { .text($0.text, tone) } ?? .none
    }
}
