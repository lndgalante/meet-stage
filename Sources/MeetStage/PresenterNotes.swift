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
    /// means finishing the line or saying "next" (a step with no line waits for
    /// "next"); there are no timers, and a microphone that reconnects mid-line
    /// just keeps waiting. With voice off or unavailable, it holds for `seconds`.
    /// Skip and ⌃⌘→ always move on.
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
                if !follower.isEmpty, follower.isComplete {
                    finishedLine = true
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

/// A floating teleprompter beside the stage. It never takes focus, follows the
/// presenter across Spaces, and asks macOS to hide it from capture where
/// supported. Sharing the BetterMeets window, not the whole screen, keeps it private.
@MainActor
final class PresenterNotesController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    var onClose: (() -> Void)?

    var isVisible: Bool { panel?.isVisible == true }

    func show(demo: DemoSession) {
        if let panel {
            panel.orderFrontRegardless()
            return
        }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 230),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: false)
        panel.title = "Presenter Notes"
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Asks macOS to leave the script out of screen capture where that's honored.
        panel.sharingType = .none
        panel.minSize = NSSize(width: 380, height: 160)
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: PresenterNotesView(demo: demo, prompter: demo.prompter))
        if !panel.setFrameUsingName("BetterMeetsPresenterNotes"), let screen = NSScreen.main {
            // Near the top of the screen, close to where the camera usually is.
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - 310, y: frame.maxY - 250))
        }
        panel.setFrameAutosaveName("BetterMeetsPresenterNotes")
        self.panel = panel
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        panel = nil
        onClose?()
    }
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

struct PresenterNotesView: View {
    @ObservedObject var demo: DemoSession
    @ObservedObject var prompter: PresenterPrompter
    @ObservedObject var listener: SpeechListener

    init(demo: DemoSession, prompter: PresenterPrompter) {
        self.demo = demo
        self.prompter = prompter
        listener = prompter.listener
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            ScrollView {
                if prompter.line != nil, prompter.follower.isEmpty {
                    Text(prompter.isFollowingVoice ? "Say “next” to continue." : "No line for this step.")
                        .font(.system(size: prompter.fontSize * 0.8, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if prompter.isEmpty {
                    Text(emptyText)
                        .font(.system(size: prompter.fontSize * 0.7, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScriptLineText(
                        follower: prompter.follower, size: prompter.fontSize,
                        marksNextWord: prompter.followsVoice && listener.isListening, startsAtSentence: true
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            footer
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 14)
        .frame(minWidth: 380, minHeight: 160)
        .background(.regularMaterial)
    }

    private var emptyText: String {
        switch demo.phase {
        case .composing, .scouting, .scoutPaused: "Your script appears here once the demo is built."
        case .finished: "Demo complete."
        default: "Press Play Demo. Each line appears here as its step begins."
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let position = prompter.position {
                Text("\(position.current) / \(position.total)")
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(prompter.heading)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
            Spacer()
            voiceToggle
            Button {
                prompter.fontSize = max(16, prompter.fontSize - 2)
            } label: {
                Image(systemName: "textformat.size.smaller")
            }
            .buttonStyle(.borderless)
            .help("Smaller text")
            Button {
                prompter.fontSize = min(48, prompter.fontSize + 2)
            } label: {
                Image(systemName: "textformat.size.larger")
            }
            .buttonStyle(.borderless)
            .help("Larger text")
        }
    }

    private var voiceToggle: some View {
        Button {
            prompter.followsVoice.toggle()
            demo.updateListening()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: prompter.followsVoice ? "mic.fill" : "mic.slash")
                if prompter.followsVoice {
                    switch listener.state {
                    case .listening:
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: 4 + CGFloat(listener.level) * 26, height: 4)
                            .animation(.easeOut(duration: 0.1), value: listener.level)
                    case .preparing(let text): Text(text).lineLimit(1)
                    case .unavailable: Text("Unavailable")
                    case .off: Text("Follow my voice")
                    }
                } else {
                    Text("Follow my voice")
                }
            }
            .font(.caption)
            .frame(minWidth: 40, alignment: .leading)
        }
        .buttonStyle(.borderless)
        .help(voiceHelp)
    }

    private var voiceHelp: String {
        if case .unavailable(let reason) = listener.state { return reason }
        let language = listener.language.map { " Listening for \($0)." } ?? ""
        return prompter.followsVoice
            ? "Following your voice on this Mac. The demo moves on when you finish each line." + language
            : "Follow my voice: highlight the next word and move on when you finish each line. Speech stays on this Mac."
    }

    @ViewBuilder private var footer: some View {
        HStack(spacing: 10) {
            if prompter.isWaitingForVoice {
                Label(
                    prompter.follower.isEmpty ? "Say “next” to continue" : "Finish the line or say “next”",
                    systemImage: "waveform")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                Button("Skip", action: demo.skipLine)
                    .controlSize(.small)
                    .help("Move on now (⌃⌘→)")
            } else if let hold = prompter.hold {
                TimelineView(.animation) { context in
                    let progress = min(1, context.date.timeIntervalSince(hold.start) / max(hold.seconds, 0.1))
                    ProgressView(value: progress).progressViewStyle(.linear).frame(maxWidth: 120)
                }
                Button("Skip", action: demo.skipLine)
                    .controlSize(.small)
                    .help("Move on now (⌃⌘→)")
            }
            if let next = prompter.upNext {
                Text("Next: \(next)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .frame(minHeight: 18)
    }
}
