import Foundation

extension CharacterSet {
    /// Trailing/leading punctuation stripped from quoted words so the caption
    /// reads "Discover", not "Discover,".
    static let punctuationTrimSet = CharacterSet.punctuationCharacters
        .union(.whitespacesAndNewlines)
}

/// A transcript or label reduced to comparison tokens while keeping the words
/// the presenter actually said, so a matched control can be quoted verbatim in
/// the caption HUD.
struct TokenizedText: Equatable {
    /// Normalized comparison tokens.
    let tokens: [String]
    /// The original words, index-aligned with `tokens`. A word that splits into
    /// several tokens (e.g. "Sign-in") repeats for each produced token so the
    /// alignment holds.
    let words: [String]
    /// Token indices immediately followed by a clause or sentence break (the
    /// spoken word ended with `. , ; : ! ?` or a dash). Cue scanning must not
    /// cross these so a verb in one clause cannot actuate a control named in the
    /// next.
    let boundariesAfter: Set<Int>

    var isEmpty: Bool { tokens.isEmpty }
}

/// Pure text normalization for Demo Mode voice matching. No platform APIs.
enum DemoText {
    /// Spoken/written number equivalences, normalized in both directions so
    /// "2" and "two" compare equal (speech engines emit either form).
    private static let numberWords: [String: String] = [
        "0": "zero", "1": "one", "2": "two", "3": "three", "4": "four",
        "5": "five", "6": "six", "7": "seven", "8": "eight", "9": "nine",
        "10": "ten", "11": "eleven", "12": "twelve", "13": "thirteen",
        "14": "fourteen", "15": "fifteen", "16": "sixteen", "17": "seventeen",
        "18": "eighteen", "19": "nineteen", "20": "twenty", "30": "thirty",
        "40": "forty", "50": "fifty", "60": "sixty", "70": "seventy",
        "80": "eighty", "90": "ninety", "100": "hundred", "1000": "thousand"
    ]

    private static let clauseBoundaryCharacters: Set<Character> = [
        ".", ",", ";", ":", "!", "?", "—", "–"
    ]

    /// Tokenizes free-form transcript text. Each spoken word is split on the same
    /// identifier boundaries as a control label (so "Sign-in" matches "Sign In"),
    /// its original spelling is kept for each produced token, and a clause break
    /// is recorded when the word ends with sentence punctuation.
    static func tokenizeTranscript(_ text: String) -> TokenizedText {
        let words = text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .map(String.init)
        var tokens: [String] = []
        var keptWords: [String] = []
        var boundaries: Set<Int> = []

        for word in words {
            let trimmed = word.trimmingCharacters(in: .punctuationTrimSet)
            var produced = false
            for piece in splitIdentifiers(word) {
                guard let token = normalize(piece) else { continue }
                tokens.append(token)
                keptWords.append(trimmed)
                produced = true
            }
            if produced, let last = word.last, clauseBoundaryCharacters.contains(last) {
                boundaries.insert(tokens.count - 1)
            }
        }
        return TokenizedText(tokens: tokens, words: keptWords, boundariesAfter: boundaries)
    }

    /// The first token index of the clause containing `index`: one past the most
    /// recent boundary before it, or 0.
    static func clauseStart(before index: Int, boundaries: Set<Int>) -> Int {
        var start = 0
        for boundary in boundaries where boundary < index {
            start = max(start, boundary + 1)
        }
        return start
    }

    /// Tokenizes a control label, splitting camelCase and snake_case so
    /// "SignIn" and "sign_in" both compare as ["sign", "in"].
    static func tokenizeLabel(_ text: String) -> [String] {
        splitIdentifiers(text)
            .compactMap(normalize)
    }

    /// Lowercases, folds diacritics, strips punctuation, and maps number forms
    /// to a canonical spelled-out token. Returns nil for empty/pure-symbol input.
    static func normalize(_ raw: String) -> String? {
        let folded = raw.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let scalars = folded.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
        }
        guard !scalars.isEmpty else { return nil }
        let cleaned = String(String.UnicodeScalarView(scalars))
        return numberWords[cleaned] ?? cleaned
    }

    /// Splits identifiers on whitespace, underscores, hyphens, and camelCase
    /// boundaries (including "USBPort" → "USB" "Port").
    static func splitIdentifiers(_ text: String) -> [String] {
        var pieces: [String] = []
        for chunk in text.split(whereSeparator: { $0 == " " || $0 == "_" || $0 == "-" || $0 == "/" }) {
            var current = ""
            let characters = Array(chunk)
            for (offset, character) in characters.enumerated() {
                if character.isUppercase, !current.isEmpty {
                    let previous = characters[offset - 1]
                    let next = offset + 1 < characters.count ? characters[offset + 1] : nil
                    // Break before an uppercase run that starts a new word, and
                    // before the last capital of an acronym that precedes a
                    // lowercase letter ("USBPort" → "USB", "Port").
                    if previous.isLowercase || previous.isNumber
                        || (previous.isUppercase && (next?.isLowercase ?? false))
                    {
                        pieces.append(current)
                        current = ""
                    }
                }
                current.append(character)
            }
            if !current.isEmpty {
                pieces.append(current)
            }
        }
        return pieces
    }
}

/// Pure string-similarity scoring for short control labels.
enum DemoSimilarity {
    /// 0...1 similarity between two normalized tokens. Exact matches score 1;
    /// otherwise Jaro-Winkler, which rewards shared prefixes (well suited to
    /// short UI labels and minor transcription slips).
    static func score(_ lhs: String, _ rhs: String) -> Double {
        if lhs == rhs { return 1 }
        if lhs.isEmpty || rhs.isEmpty { return 0 }
        return jaroWinkler(lhs, rhs)
    }

    static func jaroWinkler(_ lhs: String, _ rhs: String) -> Double {
        let jaro = jaro(lhs, rhs)
        guard jaro > 0.7 else { return jaro }

        let a = Array(lhs)
        let b = Array(rhs)
        var prefix = 0
        for index in 0..<min(4, min(a.count, b.count)) where a[index] == b[index] {
            prefix += 1
        }
        return jaro + Double(prefix) * 0.1 * (1 - jaro)
    }

    private static func jaro(_ lhs: String, _ rhs: String) -> Double {
        let a = Array(lhs)
        let b = Array(rhs)
        if a.isEmpty || b.isEmpty { return 0 }
        if a == b { return 1 }

        let matchDistance = max(a.count, b.count) / 2 - 1
        guard matchDistance >= 0 else {
            return a == b ? 1 : 0
        }

        var aMatches = [Bool](repeating: false, count: a.count)
        var bMatches = [Bool](repeating: false, count: b.count)
        var matches = 0

        for i in 0..<a.count {
            let start = max(0, i - matchDistance)
            let end = min(i + matchDistance + 1, b.count)
            guard start < end else { continue }
            for j in start..<end where !bMatches[j] && a[i] == b[j] {
                aMatches[i] = true
                bMatches[j] = true
                matches += 1
                break
            }
        }
        guard matches > 0 else { return 0 }

        var transpositions = 0
        var k = 0
        for i in 0..<a.count where aMatches[i] {
            while !bMatches[k] { k += 1 }
            if a[i] != b[k] { transpositions += 1 }
            k += 1
        }

        let m = Double(matches)
        return
            (m / Double(a.count)
            + m / Double(b.count)
            + (m - Double(transpositions) / 2) / m) / 3
    }
}

/// The best contiguous window in a transcript that names a label.
struct DemoMatch: Equatable {
    /// Mean per-token similarity across the aligned window, 0...1.
    let score: Double
    /// Half-open range of transcript token indices the label matched.
    let tokenRange: Range<Int>
}

/// Aligns a control label against a transcript as a contiguous token window.
enum DemoLabelMatcher {
    /// Every aligned label token must reach this similarity or the window is
    /// rejected, preventing a single strong token from carrying a poor match.
    static let perTokenFloor = 0.74

    /// Returns the best-scoring alignment of `labelTokens` inside
    /// `transcriptTokens`, or nil if no window clears `perTokenFloor`.
    static func bestMatch(
        labelTokens: [String],
        transcriptTokens: [String]
    ) -> DemoMatch? {
        allMatches(labelTokens: labelTokens, transcriptTokens: transcriptTokens)
            .max { $0.score < $1.score }
    }

    /// Every contiguous window of `transcriptTokens` that names `labelTokens`
    /// above `perTokenFloor`. A control mentioned twice yields two matches, so
    /// each mention can be judged for intent independently.
    static func allMatches(
        labelTokens: [String],
        transcriptTokens: [String]
    ) -> [DemoMatch] {
        guard !labelTokens.isEmpty,
            transcriptTokens.count >= labelTokens.count
        else { return [] }

        let windowLength = labelTokens.count
        var matches: [DemoMatch] = []

        for start in 0...(transcriptTokens.count - windowLength) {
            var total = 0.0
            var rejected = false
            for offset in 0..<windowLength {
                let similarity = DemoSimilarity.score(
                    labelTokens[offset],
                    transcriptTokens[start + offset]
                )
                if similarity < perTokenFloor {
                    rejected = true
                    break
                }
                total += similarity
            }
            guard !rejected else { continue }
            matches.append(
                DemoMatch(
                    score: total / Double(windowLength),
                    tokenRange: start..<(start + windowLength)
                )
            )
        }
        return matches
    }
}
