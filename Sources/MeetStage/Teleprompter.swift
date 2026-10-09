import AppKit
import SwiftUI

/// What the presenter should be saying now, and how far they have got.
@MainActor
final class PresenterPrompter: ObservableObject {
    enum Line: Equatable {
        case opening
        case step(Int)
        case closing
    }

    @Published private(set) var line: Line?
    @Published private(set) var follower = ScriptFollower(line: "")
    @Published private(set) var heading = ""
    @Published private(set) var upNext: String?
    @Published private(set) var position: (current: Int, total: Int)?
    /// The demo is holding until this line has been said.
    @Published private(set) var isWaitingForVoice = false
    /// A timed hold in progress, for the progress bar.
    @Published private(set) var hold: (start: Date, seconds: Double)?
    @Published var followsVoice: Bool {
        didSet { defaults.set(followsVoice, forKey: "demo.followsVoice") }
    }
    @Published var fontSize: Double {
        didSet { defaults.set(fontSize, forKey: "demo.notesFontSize") }
    }

    let listener = SpeechListener()
    private let defaults: UserDefaults
    /// Words heard before this line appeared belong to an earlier line.
    private var lineStartWord = 0
    /// Words already matched; a recognizer re-sending them must not count twice.
    private var consumedWords = 0
    private var skipRequested = false
    /// When the presenter said "next", and how much had been heard by then.
    private var nextCommand: (at: Date, words: Int)?

    /// How much of a line's key words count as having said it in your own words.
    static let gistCoverage = 0.6
    /// The pause after the gist that reads as "done with this point".
    private static let naturalPause = 1.1
    /// How long a step with no line waits, while following the voice, before moving on.
    private static let silentStepBeat = 0.8

    /// Whether the presenter has said anything since this line appeared.
    private var heardSinceLineStarted: Bool { listener.totalWords > lineStartWord }

    /// Words that move the demo on when said on their own, followed by a pause.
    static let nextWords: Set<String> = ["next", "siguiente", "suivant", "weiter", "avanti", "proximo", "seguinte"]

    /// Following the presenter's voice right now (listening, starting or reconnecting).
    var isFollowingVoice: Bool { followsVoice && listener.wantsToListen }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        // On by default: the demo moves on when the presenter finishes each line.
        followsVoice = defaults.object(forKey: "demo.followsVoice") as? Bool ?? true
        let size = defaults.double(forKey: "demo.notesFontSize")
        fontSize = size == 0 ? 26 : min(48, max(16, size))
        listener.onTranscript = { [weak self] in self?.heard() }
    }

    var isEmpty: Bool { line == nil || follower.isEmpty }

    func show(_ line: Line, text: String, heading: String, upNext: String?, position: (Int, Int)?) {
        self.line = line
        follower = ScriptFollower(line: text)
        self.heading = heading
        self.upNext = upNext
        self.position = position
        hold = nil
        skipRequested = false
        nextCommand = nil
        lineStartWord = listener.totalWords
        consumedWords = lineStartWord
    }

    func clear() {
        line = nil
        follower = ScriptFollower(line: "")
        heading = ""
        upNext = nil
        position = nil
        hold = nil
        isWaitingForVoice = false
    }

    /// Holds a step until the presenter moves on. Following their voice, that
    /// means finishing the line, saying most of it in their own words and then
    /// pausing, or saying "next"; a step with no line moves on after a short
    /// beat. A microphone that reconnects mid-line just keeps waiting. With voice
    /// off or unavailable, it holds for `seconds`. Next Line (→ or ⌃⌘→) always
    /// moves on.
    func hold(seconds: Double) async throws {
        let started = Date()
        defer {
            isWaitingForVoice = false
            hold = nil
        }
        var finishedLine = false
        while true {
            if skipRequested { break }
            let byVoice = isFollowingVoice
            if isWaitingForVoice != byVoice { isWaitingForVoice = byVoice }
            if byVoice {
                if hold != nil { hold = nil }
                if follower.isEmpty {
                    // Nothing to say on this step: a short beat, then on.
                    if Date().timeIntervalSince(started) >= Self.silentStepBeat { break }
                } else if follower.isComplete {
                    finishedLine = true
                    break
                } else if follower.coverage >= Self.gistCoverage, heardSinceLineStarted,
                    Date().timeIntervalSince(listener.lastHeard) >= Self.naturalPause
                {
                    // Said in their own words: most of the line's meaning, then a natural pause.
                    break
                }
                if let command = nextCommand, Date().timeIntervalSince(command.at) >= 0.6,
                    listener.totalWords <= command.words
                {
                    break
                }
            } else {
                if hold == nil { hold = (started, seconds) }
                if Date().timeIntervalSince(started) >= seconds { break }
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        // A beat after the last word, so the next step doesn't cut the sentence off.
        if finishedLine { try await Task.sleep(for: .milliseconds(350)) }
    }

    /// Moves past the current line now, whether the demo waits for a voice or a timer.
    func skipLine() {
        follower.complete()
        skipRequested = true
    }

    private func heard() {
        let total = listener.totalWords
        // A revised partial result can shrink what was heard; re-sent words never count twice.
        guard total > consumedWords else {
            consumedWords = min(consumedWords, total)
            lineStartWord = min(lineStartWord, total)
            return
        }
        consumedWords = total
        let heard = listener.words(since: lineStartWord)
        let moved = follower.advance(heard: heard.joined(separator: " "))
        // "next" on its own moves on; as a word of the line itself it's just reading.
        if let last = heard.last.map(ScriptFollower.normalize), Self.nextWords.contains(last), !moved {
            nextCommand = (Date(), total)
        } else if nextCommand.map({ total > $0.words }) == true {
            nextCommand = nil
        }
    }
}

// MARK: - Panel

/// A teleprompter that hangs just under the camera, so reading it looks like
/// talking to the audience. It never activates BetterMeets, follows the
/// presenter across Spaces, and asks macOS to leave it out of screen capture
/// where supported; sharing the BetterMeets window, not the whole screen,
/// keeps it private. Dragging moves it; Move Under Camera puts it back.
@MainActor
final class TeleprompterController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    var onClose: (() -> Void)?

    static let defaultSize = NSSize(width: 560, height: 200)
    private static let autosaveName = "BetterMeetsTeleprompter"

    var isVisible: Bool { panel?.isVisible == true }

    func show(demo: DemoSession) {
        if let panel {
            panel.orderFrontRegardless()
            return
        }
        let panel = TeleprompterPanel(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
        panel.title = "Teleprompter"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        // Asks macOS to leave the script out of screen capture where that's honored.
        panel.sharingType = .none
        panel.minSize = NSSize(width: 380, height: 120)
        panel.delegate = self
        panel.contentView = NSHostingView(
            rootView: TeleprompterView(demo: demo, moveUnderCamera: { [weak self] in self?.moveUnderCamera() }))
        if !panel.setFrameUsingName(Self.autosaveName) {
            panel.setFrame(Self.underCamera(size: Self.defaultSize), display: false)
        }
        panel.setFrameAutosaveName(Self.autosaveName)
        self.panel = panel
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func moveUnderCamera() {
        guard let panel else { return }
        panel.setFrame(Self.underCamera(size: panel.frame.size), display: true, animate: false)
    }

    func windowWillClose(_ notification: Notification) {
        panel = nil
        onClose?()
    }

    /// Centered just below the menu bar of the display with the camera: the
    /// built-in display when it's open, else the main one.
    static func underCamera(size: NSSize) -> NSRect {
        let screen =
            NSScreen.screens.first { screen in
                guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
                else { return false }
                return CGDisplayIsBuiltin(id) != 0
            } ?? NSScreen.main
        guard let screen else { return NSRect(origin: .zero, size: size) }
        // The camera sits at the middle of the display, whatever the Dock does to the visible area.
        return NSRect(
            x: screen.frame.midX - size.width / 2, y: screen.visibleFrame.maxY - size.height - 6,
            width: size.width, height: size.height)
    }
}

/// A borderless panel that can take clicks and menus without activating BetterMeets.
private final class TeleprompterPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Views

/// One script line with the words already said dimmed and the next word marked.
struct ScriptLineText: View {
    let follower: ScriptFollower
    var size: Double
    var marksNextWord: Bool

    /// Long lines start at the sentence being read, so the next word stays in view.
    var startsAtSentence = false

    var body: some View {
        let next = follower.nextWord
        let spoken = follower.spoken
        let words = follower.displayWords
        var first = 0
        if startsAtSentence, words.count > 24, spoken > 0 {
            let current = min(spoken, words.count - 1)
            first = (0..<current).last { words[$0].last.map { ".!?".contains($0) } == true }.map { $0 + 1 } ?? 0
        }
        var text = AttributedString(first > 0 ? "… " : "")
        for index in first..<max(first, words.count) {
            let word = words[index]
            var piece = AttributedString(index == first ? word : " " + word)
            if index < spoken {
                piece.foregroundColor = .secondary
            } else if marksNextWord, index == next {
                piece.foregroundColor = .accentColor
                piece.underlineStyle = .single
            }
            text.append(piece)
        }
        return Text(text)
            .font(.system(size: size, weight: .medium, design: .rounded))
            .lineSpacing(size * 0.22)
            .animation(.easeOut(duration: 0.15), value: follower.nextWord)
            .accessibilityLabel(follower.displayWords.joined(separator: " "))
    }
}

/// The teleprompter's content: where you are, the line to say, and what's next.
struct TeleprompterView: View {
    @ObservedObject var demo: DemoSession
    @ObservedObject var prompter: PresenterPrompter
    @ObservedObject var listener: SpeechListener
    let moveUnderCamera: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(demo: DemoSession, moveUnderCamera: @escaping () -> Void) {
        self.demo = demo
        prompter = demo.prompter
        listener = demo.prompter.listener
        self.moveUnderCamera = moveUnderCamera
    }

    var body: some View {
        VStack(spacing: 10) {
            header
            ScrollView {
                line
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.never)
            footer
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(minWidth: 380, minHeight: 120)
        .background(
            reduceTransparency ? Color.black : Color.black.opacity(0.86),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .environment(\.colorScheme, .dark)
        .contextMenu { options }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Teleprompter")
    }

    // MARK: Line

    @ViewBuilder private var line: some View {
        if prompter.line != nil, prompter.follower.isEmpty {
            Text("No line for this step")
                .font(.system(size: prompter.fontSize * 0.75, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        } else if prompter.isEmpty {
            Text(emptyText)
                .font(.system(size: prompter.fontSize * 0.65, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        } else {
            ScriptLineText(
                follower: prompter.follower, size: prompter.fontSize,
                marksNextWord: prompter.followsVoice && listener.isListening, startsAtSentence: true)
        }
    }

    private var emptyText: String {
        switch demo.phase {
        case .composing, .scouting, .scoutPaused: "Your lines appear here once the demo is built."
        case .finished: "Demo complete."
        default: "Press Play. Each line appears here as its step begins."
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            if let position = prompter.position {
                Text("\(position.current)/\(position.total)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(prompter.heading)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            voiceButton
            transport
            Menu {
                options
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Teleprompter options")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
    }

    /// Start over, back, pause or play, and next: the whole demo from under the camera.
    @ViewBuilder private var transport: some View {
        if let position = transportPosition {
            Button(action: demo.startOver) { Image(systemName: "arrow.counterclockwise") }
                .disabled(!demo.isLiveSourceSelected)
                .help("Start over from the opening line")
                .accessibilityLabel(PanelActionID.startOver.title)
            Button(action: demo.previousStep) { Image(systemName: "backward.fill") }
                .disabled(!demo.isLiveSourceSelected || position.atFirstStep)
                .help("Previous step (←): goes back to the start and replays up to it")
                .accessibilityLabel(PanelActionID.previousStep.title)
            if position.isRunning {
                Button(action: demo.pause) { Image(systemName: "pause.fill") }
                    .help("Pause the demo")
                    .accessibilityLabel(PanelActionID.pauseDemo.title)
            } else {
                Button {
                    demo.play()
                } label: {
                    Image(systemName: "play.fill")
                }
                .disabled(!demo.isLiveSourceSelected)
                .help(demo.phase == .finished ? "Play again from the start" : "Play the demo")
                .accessibilityLabel(PanelActionID.menuPrimary(in: demo.phase).title)
            }
            Button(action: demo.skipLine) { Image(systemName: "forward.fill") }
                .disabled(!position.isRunning)
                .help("Next line (→)")
                .accessibilityLabel(PanelActionID.nextLine.title)
        }
    }

    /// Where the demo is, while it can be presented; nil while building or testing.
    private var transportPosition: (isRunning: Bool, atFirstStep: Bool)? {
        switch demo.phase {
        case .running(.present, let next, let current): (true, (current ?? next) == 0)
        case .paused(.present, let next, let current, _): (false, (current ?? next) == 0)
        case .offTrack(.present, let index, _): (false, index == 0)
        case .ready: (false, true)
        case .finished: (false, false)
        default: nil
        }
    }

    private var voiceButton: some View {
        Button {
            demo.followsVoice.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: prompter.followsVoice ? "mic.fill" : "mic.slash")
                if prompter.followsVoice {
                    switch listener.state {
                    case .listening:
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: 4 + CGFloat(listener.level) * 22, height: 4)
                            .animation(.easeOut(duration: 0.1), value: listener.level)
                    case .preparing(let text): Text(text).font(.caption).lineLimit(1)
                    case .unavailable: Text("Mic unavailable").font(.caption)
                    case .off: EmptyView()
                    }
                }
            }
        }
        .help(voiceHelp)
        .accessibilityLabel(prompter.followsVoice ? "Stop following my voice" : "Follow my voice")
    }

    private var voiceHelp: String {
        if case .unavailable(let reason) = listener.state { return reason }
        let language = listener.language.map { " Listening for \($0)." } ?? ""
        return prompter.followsVoice
            ? "Following your voice on this Mac. Each step moves on when you finish its line." + language
            : "Follow my voice: highlight the next word and move on when you finish each line."
    }

    @ViewBuilder private var options: some View {
        Button("Larger Text") { prompter.fontSize = min(48, prompter.fontSize + 2) }
        Button("Smaller Text") { prompter.fontSize = max(16, prompter.fontSize - 2) }
        Divider()
        Button("Move Under Camera", action: moveUnderCamera)
        Button("Hide Teleprompter", action: demo.hideTeleprompter)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            if let next = prompter.upNext {
                Text("Next: \(next)").lineLimit(1)
            }
            Spacer(minLength: 8)
            if prompter.isWaitingForVoice {
                Label(prompter.follower.isEmpty ? "Moving on" : "Listening", systemImage: "waveform")
                    .foregroundStyle(Color.accentColor)
            } else if let hold = prompter.hold {
                TimelineView(.animation) { context in
                    let progress = min(1, context.date.timeIntervalSince(hold.start) / max(hold.seconds, 0.1))
                    ProgressView(value: progress).progressViewStyle(.linear).frame(width: 80)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(minHeight: 16)
    }
}
