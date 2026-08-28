import Foundation

/// Classifies one finalized transcript segment into a Demo Mode command by
/// matching a named control and reading the surrounding words for intent.
///
/// The policy is deliberately conservative: a control is only acted on when the
/// narration supplies a contextual cue (an action verb, a control noun such as
/// "button", or a strong exact name introduced by a determiner), the cue is in
/// the same clause as the name, and the phrase is not negated. Clicking further
/// requires a near-exact name and a pressable target. This is what keeps a live
/// demo from misbehaving.
enum DemoIntentPolicy {
    /// Minimum per-element match score to consider a command at all.
    static let scoreFloor = 0.82
    /// Clicking (and any determiner-only cue) demands a near-exact name so a
    /// passing mention or a fuzzy near-miss cannot trigger an action.
    static let nearExactFloor = 0.95
    /// How many tokens before the matched name to search for an action verb.
    static let verbWindow = 5
    /// How many tokens before the matched name to search for a determiner cue.
    static let determinerWindow = 2

    /// Unambiguous action verbs, matched anywhere in the (clause-clamped) verb
    /// window before the name.
    static let actionVerbs: Set<String> = [
        "click", "clicks", "clicking", "clicked",
        "press", "presses", "pressing", "pressed",
        "tap", "taps", "tapping", "tapped",
        "open", "opens", "opening",
        "select", "selects", "selecting", "selected",
        "choose", "chooses", "choosing", "chose",
        "activate", "activates", "activating",
        "launch", "launches", "launching",
        "toggle", "toggles", "toggling"
    ]

    /// Metaphor-prone verbs ("hit a new high", "push the limits") that count as a
    /// cue only when adjacent to the name — the verb, then optionally
    /// determiners or control nouns, then the name.
    static let tightAdjacencyVerbs: Set<String> = [
        "hit", "hits", "hitting",
        "push", "pushes", "pushing"
    ]

    /// Multi-word navigation phrases that request actuation. The tokens between
    /// the phrase and the name must all be determiners, so "go to the Discover
    /// page" clicks while "go to lengths to simplify Send" does not. "going to"
    /// is deliberately absent: it is almost always future-tense narration.
    static let navigationPhrases: [[String]] = [
        ["go", "to"], ["goes", "to"],
        ["take", "us", "to"], ["take", "you", "to"], ["take", "me", "to"],
        ["takes", "us", "to"], ["takes", "you", "to"],
        ["navigate", "to"], ["navigates", "to"],
        ["bring", "us", "to"], ["bring", "you", "to"],
        ["send", "us", "to"], ["send", "you", "to"],
        ["jump", "to"], ["head", "to"], ["head", "over", "to"],
        ["switch", "to"], ["move", "to"]
    ]

    /// Nouns that confirm the presenter is pointing at a control.
    static let controlNouns: Set<String> = [
        "button", "buttons", "tab", "tabs", "link", "links",
        "icon", "icons", "menu", "menus", "option", "options",
        "field", "fields", "toggle", "toggles", "page", "pages",
        "control", "controls", "item", "items", "section", "sections",
        "card", "cards", "panel", "panels", "row", "rows", "cell",
        "checkbox", "dropdown", "slider", "switch"
    ]

    /// Determiners and presenter fillers that frame a named control.
    static let determiners: Set<String> = [
        "this", "that", "the", "these", "those",
        "your", "our", "my", "a", "an", "new", "here", "heres"
    ]

    /// Negators that, appearing before the verb in the same clause, cancel any
    /// actuation ("don't click Send"). Forms match the tokenizer's output
    /// (apostrophes stripped).
    static let negators: Set<String> = [
        "not", "dont", "doesnt", "didnt", "never", "no",
        "cant", "cannot", "wont", "shouldnt", "wouldnt",
        "avoid", "without", "before", "instead"
    ]

    /// Resolves a command for the transcript segment, or nil if no control was
    /// confidently and contextually named.
    static func resolve(
        transcript: String,
        elements: [DemoElement],
        voiceActions: DemoVoiceActions
    ) -> DemoResolvedCommand? {
        let tokenized = DemoText.tokenizeTranscript(transcript)
        guard !tokenized.isEmpty, !elements.isEmpty else { return nil }

        var best: (command: DemoResolvedCommand, rank: Double, position: Int, id: Int)?

        for element in elements {
            let labelTokens = DemoText.tokenizeLabel(element.label)
            for match in DemoLabelMatcher.allMatches(
                labelTokens: labelTokens,
                transcriptTokens: tokenized.tokens
            ) where match.score >= scoreFloor {
                let cues = contextCues(
                    around: match.tokenRange,
                    in: tokenized.tokens,
                    boundaries: tokenized.boundariesAfter
                )

                let determinerOnly = cues.hasDeterminer && !cues.hasVerb && !cues.hasControlNoun
                if determinerOnly, match.score < nearExactFloor { continue }
                guard cues.hasVerb || cues.hasControlNoun || cues.hasDeterminer else { continue }

                let canClick =
                    cues.hasVerb
                    && voiceActions.allowsClicking
                    && element.pressable
                    && match.score >= nearExactFloor
                let kind: DemoIntentKind = canClick ? .click : .highlight

                let cueBonus = cues.hasVerb ? 0.10 : (cues.hasControlNoun ? 0.04 : 0)
                let rank =
                    match.score
                    + cueBonus
                    + 0.02 * element.role.matchWeight
                    - (element.source == .recognizedText ? 0.02 : 0)
                    - (element.pressable ? 0 : 0.01)
                let command = DemoResolvedCommand(
                    kind: kind,
                    element: element,
                    matchedPhrase: quotedPhrase(for: match.tokenRange, words: tokenized.words),
                    score: match.score
                )

                if isPreferred(
                    rank: rank,
                    position: match.tokenRange.lowerBound,
                    id: element.id,
                    over: best
                ) {
                    best = (command, rank, match.tokenRange.lowerBound, element.id)
                }
            }
        }

        return best?.command
    }

    private static func isPreferred(
        rank: Double,
        position: Int,
        id: Int,
        over current: (command: DemoResolvedCommand, rank: Double, position: Int, id: Int)?
    ) -> Bool {
        guard let current else { return true }
        if abs(rank - current.rank) > 0.0001 { return rank > current.rank }
        // Deterministic tie-break: later mention, then lower element id.
        if position != current.position { return position > current.position }
        return id < current.id
    }

    // MARK: - Context cues

    struct ContextCues: Equatable {
        var hasVerb: Bool
        var hasControlNoun: Bool
        var hasDeterminer: Bool
    }

    static func contextCues(
        around range: Range<Int>,
        in tokens: [String],
        boundaries: Set<Int>
    ) -> ContextCues {
        let clauseStart = DemoText.clauseStart(before: range.lowerBound, boundaries: boundaries)

        let verbStart = max(range.lowerBound - verbWindow, clauseStart)
        let verbWindowTokens = Array(tokens[verbStart..<range.lowerBound])
        let hasVerb = hasActuationVerb(in: verbWindowTokens)

        // A control noun immediately after the name (in the same clause), or a
        // trailing noun that qualifies a multi-token name ("Discover page").
        var hasControlNoun = false
        let trailingIsClauseEnd = boundaries.contains(range.upperBound - 1)
        if range.upperBound < tokens.count,
            !trailingIsClauseEnd,
            controlNouns.contains(tokens[range.upperBound])
        {
            hasControlNoun = true
        } else if range.count > 1, let last = tokens[range].last, controlNouns.contains(last) {
            hasControlNoun = true
        }

        let determinerStart = max(range.lowerBound - determinerWindow, clauseStart)
        let hasDeterminer = tokens[determinerStart..<range.lowerBound].contains(where: determiners.contains)

        return ContextCues(
            hasVerb: hasVerb,
            hasControlNoun: hasControlNoun,
            hasDeterminer: hasDeterminer
        )
    }

    /// Whether the window before a control name contains an un-negated actuation
    /// cue. `window` is in reading order, ending just before the name.
    static func hasActuationVerb(in window: [String]) -> Bool {
        guard let cueIndex = actuationCueIndex(in: window) else { return false }
        // A negator at or before the cue within the clause cancels actuation.
        for index in 0...cueIndex where negators.contains(window[index]) {
            return false
        }
        return true
    }

    /// The index within `window` where an actuation cue begins, or nil.
    private static func actuationCueIndex(in window: [String]) -> Int? {
        if let index = window.firstIndex(where: actionVerbs.contains) {
            return index
        }
        // Tight-adjacency verbs: only the tokens between verb and name that are
        // determiners or control nouns are allowed.
        for index in window.indices.reversed() where tightAdjacencyVerbs.contains(window[index]) {
            let between = window[(index + 1)...]
            if between.allSatisfy({ determiners.contains($0) || controlNouns.contains($0) }) {
                return index
            }
        }
        // Navigation phrases: only determiners may sit between the phrase and the name.
        for phrase in navigationPhrases {
            if let start = subsequenceStart(phrase, in: window) {
                let between = window[(start + phrase.count)...]
                if between.allSatisfy(determiners.contains) {
                    return start
                }
            }
        }
        return nil
    }

    private static func subsequenceStart(_ phrase: [String], in tokens: [String]) -> Int? {
        guard !phrase.isEmpty, tokens.count >= phrase.count else { return nil }
        for start in 0...(tokens.count - phrase.count) {
            var matched = true
            for offset in 0..<phrase.count where tokens[start + offset] != phrase[offset] {
                matched = false
                break
            }
            if matched { return start }
        }
        return nil
    }

    private static func quotedPhrase(for range: Range<Int>, words: [String]) -> String {
        guard range.lowerBound < words.count else { return "" }
        let upper = min(range.upperBound, words.count)
        var phrase: [String] = []
        for word in words[range.lowerBound..<upper] where word != phrase.last {
            phrase.append(word)
        }
        return phrase.joined(separator: " ")
    }
}
