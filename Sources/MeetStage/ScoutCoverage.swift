import Foundation

/// Checks Claude's finish against the demo it would compile, once per build: each
/// beat of the turn-1 outline shown by a step the demo keeps, and something
/// highlighted when the request asks to show something. What's missing goes back
/// to Claude as a fact, and the next finish is accepted whatever it covers.
enum ScoutCoverage {
    /// Words that ask a demo to show something rather than only do it, in the
    /// languages BetterMeets writes demos in. Stems match at the start of a word.
    static let showPattern =
        #"\b(show(s|n|ing|case)?\b|highlight|display|reveal|explain|demonstrat|point (out|to|at)\b"#
        + #"|walk (\w+ )?through\b|where\b|tours?\b)"#
        + #"|\b(mu[eé]str|mostr|enseñ|señal|resalt|destac|explic|d[oó]nde\b|onde\b|aponte)"#
        + #"|\b(montr|affich|soulign|expliqu|où\b)|\b(zeig|hervorheb|erklär|wo\b)"#
        + #"|\b(evidenzi|spieg|dove\b)|\b(toon|tonen\b|markeer|uitleg|waar\b)|見せ|表示|显示|展示|顯示|보여|표시"#

    static func asksToShow(_ prompt: String) -> Bool {
        prompt.range(of: showPattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Why the finish is turned back, for the fact Claude reads, or nil when every
    /// beat has a step and a request to show something has a highlight. `shown`
    /// holds the turns whose records the demo keeps steps from. A reply that didn't
    /// say what covers the beats (`coverage` nil) leaves them unjudged.
    static func gap(
        outline: [String], coverage: [ScoutBeatCoverage]?, shown: Set<Int>, highlighted: Bool, prompt: String
    ) -> String? {
        var missing: [String] = []
        if let coverage {
            let uncovered = outline.indices.filter { index in
                !coverage.contains { $0.beat == index + 1 && $0.steps.contains(where: shown.contains) }
            }
            if !uncovered.isEmpty {
                let beats = uncovered.map { "\($0 + 1) “\(String(outline[$0].prefix(40)))”" }
                missing.append(
                    uncovered.count == 1
                        ? "beat \(beats[0]) has no step in the demo that shows it"
                        : "beats \(list(beats)) have no step in the demo that shows them")
            }
        }
        if !highlighted, asksToShow(prompt) {
            missing.append("nothing is highlighted, though the request asks to show something")
        }
        guard !missing.isEmpty else { return nil }
        return missing.joined(separator: ", and ") + ". Show what’s missing, or call finish again if it can’t be shown."
    }

    /// “a”, “a and b”, “a, b and c”.
    private static func list(_ items: [String]) -> String {
        guard let last = items.last, items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + last
    }
}
