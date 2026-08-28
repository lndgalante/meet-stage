import Foundation
import NaturalLanguage

/// Semantic control matching using Apple's on-device word/sentence embeddings.
///
/// This is the "smart for everyone" tier: it runs on every Mac with no setup, no
/// download prompt, no Apple Intelligence, and no network — the embedding models
/// ship with the OS. It matches a spoken phrase to the nearest control by meaning
/// (so "the get-paid button" resolves to "Receive"), covering the synonym and
/// paraphrase cases that literal string matching misses. It resolves a target
/// only; the caller decides highlight-vs-click from the surrounding words.
@MainActor
final class DemoEmbeddingMatcher {
    /// Minimum cosine similarity (−1...1) to accept a match. Tuned conservatively
    /// so unrelated narration does not resolve to a control.
    static let minimumSimilarity = 0.52

    private let sentenceEmbedding: NLEmbedding?
    private let wordEmbedding: NLEmbedding?

    init(language: NLLanguage = .english) {
        sentenceEmbedding = NLEmbedding.sentenceEmbedding(for: language)
        wordEmbedding = NLEmbedding.wordEmbedding(for: language)
    }

    /// Whether any embedding model loaded (effectively always true on a Mac).
    var isAvailable: Bool {
        sentenceEmbedding != nil || wordEmbedding != nil
    }

    struct Match: Equatable {
        let label: String
        let similarity: Double
    }

    /// Returns the label most semantically similar to `transcript`, or nil if the
    /// best match is below `minimumSimilarity`.
    func bestMatch(transcript: String, labels: [String]) -> Match? {
        guard let utterance = vector(for: transcript) else { return nil }

        var best: Match?
        for label in labels {
            guard let labelVector = vector(for: label) else { continue }
            let similarity = cosineSimilarity(utterance, labelVector)
            guard similarity >= Self.minimumSimilarity else { continue }
            if best.map({ similarity > $0.similarity }) ?? true {
                best = Match(label: label, similarity: similarity)
            }
        }
        return best
    }

    /// Embeds text with the sentence model when available, otherwise averages the
    /// word vectors — so multi-word labels still get a usable vector.
    private func vector(for text: String) -> [Double]? {
        if let sentenceEmbedding, let vector = sentenceEmbedding.vector(for: text) {
            return vector
        }
        guard let wordEmbedding else { return nil }

        var sum: [Double] = []
        var count = 0
        for token in DemoText.tokenizeLabel(text) {
            guard let vector = wordEmbedding.vector(for: token) else { continue }
            if sum.isEmpty {
                sum = vector
            } else if sum.count == vector.count {
                for index in sum.indices {
                    sum[index] += vector[index]
                }
            }
            count += 1
        }
        guard count > 0 else { return nil }
        return sum.map { $0 / Double(count) }
    }

    private func cosineSimilarity(_ lhs: [Double], _ rhs: [Double]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return -1 }
        var dot = 0.0
        var lhsMagnitude = 0.0
        var rhsMagnitude = 0.0
        for index in lhs.indices {
            dot += lhs[index] * rhs[index]
            lhsMagnitude += lhs[index] * lhs[index]
            rhsMagnitude += rhs[index] * rhs[index]
        }
        let denominator = (lhsMagnitude.squareRoot() * rhsMagnitude.squareRoot())
        guard denominator > 0 else { return -1 }
        return dot / denominator
    }
}
