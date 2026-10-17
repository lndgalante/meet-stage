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
    /// Counts every `show`, so a line shown again (Start Over) reads from its start, even with the same words.
    @Published private(set) var showCount = 0
    /// A timed hold in progress, for the progress bar.
    @Published private(set) var hold: (start: Date, seconds: Double)?
    /// The last few words heard on this line, so the presenter sees they're being followed.
    @Published private(set) var heardTail: [String] = []
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

    /// What a step with no line, and a demo finished without a closing line, show instead.
    nonisolated static let noLineText = "No line for this step"
    nonisolated static let finishedText = "That’s the whole demo."

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

    func show(_ line: Line, text: String, heading: String, upNext: String?, position: (Int, Int)?) {
        self.line = line
        follower = ScriptFollower(line: text)
        self.heading = heading
        self.upNext = upNext
        self.position = position
        showCount += 1
        hold = nil
        heardTail = []
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
        heardTail = []
    }

    /// Holds a step until the presenter moves on. Following their voice, that
    /// means finishing the line, saying most of it in their own words and then
    /// pausing, or saying "next"; a step with no line moves on after a short
    /// beat. A microphone that reconnects mid-line just keeps waiting. With voice
    /// off or unavailable, it holds for `seconds`. Next Line (→ or ⌃⌘→) always
    /// moves on.
    func hold(seconds: Double) async throws {
        let started = Date()
        defer { if hold != nil { hold = nil } }
        var finishedLine = false
        while true {
            if skipRequested { break }
            if isFollowingVoice {
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
        if total <= consumedWords {
            consumedWords = total
            lineStartWord = min(lineStartWord, total)
        }
        let heard = listener.words(since: lineStartWord)
        // Publish only real changes; a recognizer re-sending words would redraw the island for nothing.
        // A revision can change words without adding any, so the tail is refreshed either way.
        let tail = Array(heard.suffix(3))
        if tail != heardTail { heardTail = tail }
        guard total > consumedWords else { return }
        consumedWords = total
        var next = follower
        let moved = next.advance(heard: heard.joined(separator: " "))
        if next != follower { follower = next }
        // "next" on its own moves on; as a word of the line itself it's just reading.
        if let last = heard.last.map(ScriptFollower.normalize), Self.nextWords.contains(last), !moved {
            nextCommand = (Date(), total)
        } else if nextCommand.map({ total > $0.words }) == true {
            nextCommand = nil
        }
    }

    #if DEBUG
        /// Test hook: a timed hold of `seconds` that started `elapsed` seconds ago.
        func simulateHold(seconds: Double, elapsed: Double) {
            hold = (Date().addingTimeInterval(-elapsed), seconds)
        }
    #endif
}

// MARK: - Line

/// One script line with the words already said dimmed and the next word marked.
struct ScriptLineText: View {
    let follower: ScriptFollower
    var size: Double
    var marksNextWord: Bool

    var body: some View {
        let next = follower.nextWord
        let spoken = follower.spoken
        var text = AttributedString()
        for (index, word) in follower.displayWords.enumerated() {
            var piece = AttributedString(index == 0 ? word : " " + word)
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
