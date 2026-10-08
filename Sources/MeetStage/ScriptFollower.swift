import Foundation

/// Follows a presenter reading one line of their script aloud.
///
/// Speech recognition is noisy: words get dropped, misheard, or still forming.
/// The follower aligns the last few recognized words against the next stretch
/// of the line and only ever moves forward, so a misheard word can't send the
/// highlight backwards and an ad-lib can't jump it ahead.
struct ScriptFollower: Equatable, Sendable {
    /// The line as displayed, one entry per word with its punctuation.
    let displayWords: [String]
    private let words: [String]
    /// How many words have been spoken.
    private(set) var spoken = 0
    /// How many heard words had arrived at the last move; only later ones are new evidence.
    private var heardUsed = 0

    static let fillers: Set<String> = ["um", "uh", "erm", "ah", "eh", "hmm", "mm", "este"]

    init(line: String) {
        displayWords = line.split(whereSeparator: \.isWhitespace).map(String.init)
        words = displayWords.map(Self.normalize)
    }

    var isEmpty: Bool { words.allSatisfy(\.isEmpty) }

    /// The word the presenter is expected to say next, or nil when the line is done.
    var nextWord: Int? { spoken < words.count ? spoken : nil }

    /// Whether the line has been said. The last couple of short words may be
    /// swallowed by the recognizer, so they don't hold the demo back.
    var isComplete: Bool {
        guard !words.isEmpty else { return true }
        let remaining = words[min(spoken, words.count)...].filter { !$0.isEmpty }
        // The recognizer lags a word behind, so a line is done once only its last
        // word (or two short ones) is left; the hold adds a beat after it.
        return remaining.isEmpty
            || (spoken >= words.count * 3 / 4
                && (remaining.count == 1 || (remaining.count == 2 && remaining.allSatisfy { $0.count <= 4 })))
    }

    /// Updates the position from everything heard since this line appeared.
    @discardableResult
    mutating func advance(heard transcript: String) -> Bool {
        let heard = transcript.split(whereSeparator: \.isWhitespace).map { Self.normalize(String($0)) }
            .filter { !$0.isEmpty && !Self.fillers.contains($0) }
        if heard.count < heardUsed { heardUsed = heard.count }
        guard let last = heard.last, !words.isEmpty, spoken < words.count, heard.count > heardUsed else {
            return false
        }
        let tail = Array(heard.suffix(6))
        // Words heard since the last move; older ones already placed the highlight.
        let fresh = Array(heard[heardUsed...])

        // Look a little behind (for repeats) and a sentence ahead.
        let windowStart = max(0, spoken - 3)
        let windowEnd = min(words.count, spoken + 14)
        var best: (end: Int, score: Int)?
        for end in max(spoken, windowStart)..<windowEnd {
            // The most recent word must be this script word, possibly still forming,
            // or the second half of it when a written word is said as two (“on-chain”).
            var before = tail.dropLast()
            var freshBefore = fresh.dropLast()
            if !Self.similar(last, words[end], partial: true) {
                guard tail.count >= 2, Self.similar(tail[tail.count - 2] + last, words[end], partial: true) else {
                    continue
                }
                before = before.dropLast()
                freshBefore = freshBefore.dropLast()
            }
            let jump = end - spoken
            // A jump needs new words matching the words it would skip, never words
            // already said; small steps may lean on recent context.
            let score =
                jump > 2
                ? Self.alignment(freshBefore, Array(words[spoken..<end])) + 1
                : Self.alignment(before, Array(words[windowStart..<end])) + 1
            // Long jumps need more evidence than the next few words do.
            let needed = jump <= 2 ? 1 : jump <= 6 ? 2 : 3
            guard score >= needed || (jump <= 1 && last.count >= 3) else { continue }
            if best == nil || score > best!.score || (score == best!.score && end < best!.end) {
                best = (end, score)
            }
        }
        guard let best, best.end + 1 > spoken else { return false }
        spoken = best.end + 1
        heardUsed = heard.count
        // Numbers and symbols are rarely said exactly as written; skip past them.
        while spoken < words.count, words[spoken].isEmpty || words[spoken].allSatisfy(\.isNumber) { spoken += 1 }
        return true
    }

    mutating func complete() {
        spoken = words.count
    }

    // MARK: Matching

    /// Length of the longest common subsequence of similar words, scanning backwards.
    private static func alignment(_ heard: ArraySlice<String>, _ script: [String]) -> Int {
        let a = Array(heard)
        guard !a.isEmpty, !script.isEmpty else { return 0 }
        var previous = [Int](repeating: 0, count: script.count + 1)
        for i in 1...a.count {
            var current = [Int](repeating: 0, count: script.count + 1)
            for j in 1...script.count {
                current[j] =
                    similar(a[i - 1], script[j - 1], partial: false)
                    ? previous[j - 1] + 1 : max(previous[j], current[j - 1])
            }
            previous = current
        }
        return previous[script.count]
    }

    static func similar(_ heard: String, _ word: String, partial: Bool) -> Bool {
        guard !heard.isEmpty, !word.isEmpty else { return false }
        if heard == word { return true }
        // A word the recognizer is still forming: "transac" for "transactions".
        if partial, heard.count >= 4, word.hasPrefix(heard) { return true }
        // Short words must match exactly: "the" is not "then".
        let limit = word.count >= 8 ? 2 : word.count >= 5 ? 1 : 0
        return limit > 0 && abs(heard.count - word.count) <= limit && distance(heard, word) <= limit
    }

    static func normalize(_ word: String) -> String {
        word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init).joined()
    }

    private static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a)
        let b = Array(b)
        var row = Array(0...b.count)
        for i in 1...a.count {
            var previous = row[0]
            row[0] = i
            for j in 1...b.count {
                let current = row[j]
                row[j] = a[i - 1] == b[j - 1] ? previous : min(previous, row[j], row[j - 1]) + 1
                previous = current
            }
        }
        return row[b.count]
    }
}
