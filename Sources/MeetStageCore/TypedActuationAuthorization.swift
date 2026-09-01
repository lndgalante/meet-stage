import Foundation

/// A framework-free authorization boundary for model-proposed text entry.
///
/// The model may identify a field and propose a payload, but only words the
/// presenter explicitly supplied after an un-negated typing verb are allowed to
/// reach the system event layer.
public enum TypedActuationAuthorization {
    private static let typingVerbs: Set<String> = [
        "type", "types", "typing", "typed",
        "write", "writes", "writing", "wrote",
        "enter", "enters", "entering", "entered",
        "input", "inputs", "inputting"
    ]

    private static let negators: Set<String> = [
        "not", "dont", "doesnt", "didnt", "never", "no",
        "cant", "cannot", "wont", "shouldnt", "wouldnt",
        "avoid", "without", "instead"
    ]

    /// Words that can introduce a quoted payload without becoming part of it.
    private static let payloadIntroducers: Set<String> = [
        "a", "an", "the", "exact", "following", "phrase", "text",
        "value", "word", "message", "url"
    ]

    /// A payload can end at the utterance boundary or before a phrase that
    /// identifies its destination. This prevents a model from swallowing the
    /// field description into the text it proposes to type.
    private static let targetIntroducers: Set<String> = [
        "in", "inside", "into", "on", "to"
    ]

    /// Returns the model payload only when the transcript contains an explicit,
    /// un-negated typing command and the complete normalized payload begins at
    /// the command's payload position. Otherwise, returns `nil`.
    public static func authorizedText(
        proposedText: String?,
        transcript: String
    ) -> String? {
        guard let proposedText else { return nil }
        let proposedTokens = tokenize(proposedText).tokens
        guard !proposedTokens.isEmpty else { return nil }

        let utterance = tokenize(transcript)
        guard !utterance.tokens.isEmpty else { return nil }

        for verbIndex in utterance.tokens.indices
        where typingVerbs.contains(utterance.tokens[verbIndex]) {
            let clauseStart = clauseStart(before: verbIndex, boundaries: utterance.boundariesAfter)
            guard !utterance.tokens[clauseStart..<verbIndex].contains(where: negators.contains)
            else { continue }

            var payloadStart = verbIndex + 1
            while payloadStart < utterance.tokens.count,
                payloadIntroducers.contains(utterance.tokens[payloadStart])
            {
                payloadStart += 1
            }

            guard payloadStart + proposedTokens.count <= utterance.tokens.count else { continue }
            let payloadEnd = payloadStart + proposedTokens.count
            guard Array(utterance.tokens[payloadStart..<payloadEnd]) == proposedTokens else {
                continue
            }
            guard
                canonicalPayload(
                    utterance.spokenWords[payloadStart..<payloadEnd].joined(separator: " "),
                    dropsTerminalClauseBoundary: true
                ) == canonicalPayload(proposedText)
            else { continue }
            guard
                !hasBoundary(
                    from: verbIndex,
                    through: payloadEnd - 1,
                    boundaries: utterance.boundariesAfter
                )
            else { continue }
            guard !utterance.tokens[(verbIndex + 1)..<payloadEnd].contains(where: negators.contains)
            else { continue }
            guard
                payloadEnd == utterance.tokens.count
                    || utterance.boundariesAfter.contains(payloadEnd - 1)
                    || targetIntroducers.contains(utterance.tokens[payloadEnd])
            else { continue }

            return proposedText
        }
        return nil
    }

    private struct Tokenization {
        let tokens: [String]
        let spokenWords: [String]
        let boundariesAfter: Set<Int>
    }

    private static let clauseBoundaryCharacters: Set<Character> = [
        ".", ",", ";", ":", "!", "?", "—", "–"
    ]

    private static func tokenize(_ text: String) -> Tokenization {
        let words = text.split(whereSeparator: { $0.isWhitespace })
        var tokens: [String] = []
        var spokenWords: [String] = []
        var boundaries: Set<Int> = []

        for word in words {
            let folded = String(word).folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: nil
            )
            let scalars = folded.unicodeScalars.filter(CharacterSet.alphanumerics.contains)
            guard !scalars.isEmpty else { continue }
            tokens.append(String(String.UnicodeScalarView(scalars)))
            spokenWords.append(String(word))
            if let last = word.last, clauseBoundaryCharacters.contains(last) {
                boundaries.insert(tokens.count - 1)
            }
        }

        return Tokenization(
            tokens: tokens,
            spokenWords: spokenWords,
            boundariesAfter: boundaries
        )
    }

    private static let wrappingQuoteCharacters = CharacterSet(charactersIn: "\"'“”‘’")

    private static func canonicalPayload(
        _ text: String,
        dropsTerminalClauseBoundary: Bool = false
    ) -> String {
        var value =
            text.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: nil
            )
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")

        if dropsTerminalClauseBoundary {
            while let last = value.last, clauseBoundaryCharacters.contains(last) {
                value.removeLast()
            }
        }
        return value.trimmingCharacters(in: wrappingQuoteCharacters)
    }

    private static func clauseStart(before index: Int, boundaries: Set<Int>) -> Int {
        boundaries.lazy.filter { $0 < index }.max().map { $0 + 1 } ?? 0
    }

    private static func hasBoundary(
        from lowerBound: Int,
        through upperBound: Int,
        boundaries: Set<Int>
    ) -> Bool {
        boundaries.contains { $0 >= lowerBound && $0 < upperBound }
    }
}
