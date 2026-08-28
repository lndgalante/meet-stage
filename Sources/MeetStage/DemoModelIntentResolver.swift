import Foundation
import FoundationModels

/// The action Apple's on-device model chose for one utterance.
@Generable
enum DemoModelAction {
    case highlight
    case click
    case none

    var debugName: String {
        switch self {
        case .highlight: "highlight"
        case .click: "click"
        case .none: "none"
        }
    }
}

/// The model's structured decision for one utterance.
@Generable
struct DemoModelDecision {
    @Guide(
        description:
            "click only if the speaker clearly wants to press or open a control; highlight if they point at one; none if no control is referenced"
    )
    let action: DemoModelAction

    @Guide(
        description:
            "the control name copied exactly from the provided list, or an empty string when action is none"
    )
    let control: String
}

/// One control offered to the model, with a role hint so it can prefer an
/// actionable target over descriptive text of the same name.
struct DemoModelControl: Sendable, Equatable {
    let label: String
    let role: String
}

/// A resolved model decision mapped to Demo Mode's intent vocabulary.
struct DemoModelResult: Sendable, Equatable {
    let kind: DemoIntentKind
    let label: String
}

/// PoC intent resolver backed by Apple's on-device Foundation Model. It handles
/// the conversational cases the deterministic `DemoIntentPolicy` cannot — pronoun
/// references ("click it back"), paraphrases, and synonyms — while staying fully
/// on device (no network, no key, private). It never actuates on its own; the
/// coordinator still applies the click/pressable/cooldown/focus safety gates.
@MainActor
final class DemoModelIntentResolver {
    private static let instructions = """
        You map a presenter's spoken narration to a UI action during a live software demo.
        You are given the list of controls currently on screen and the single sentence the \
        presenter just said.

        Rules:
        - Choose "click" when the presenter wants to press, open, activate, or navigate via a \
        control (verbs like click, press, tap, open, select, or phrases like "take us to", \
        "go back to", "let's go to").
        - Navigation counts as clicking the control that leads there. "Go back to the home \
        page" means click the control named Home (or the closest navigation control).
        - Choose "highlight" when they point at or mention a control without asking to operate it.
        - Choose "none" when no on-screen control is referenced.
        - Resolve pronouns such as "it", "that", or "this one" using the most recently \
        acted-on control.
        - Only ever return a control name that appears in the provided list, copied exactly. \
        If nothing in the list fits, choose "none".
        """

    private var session: LanguageModelSession?

    /// Whether the on-device model is ready (Apple Intelligence enabled, model
    /// downloaded, device supported).
    static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case let .unavailable(reason):
            return String(describing: reason)
        @unknown default:
            return "unavailable"
        }
    }

    /// Resolves one utterance against the on-screen controls, or nil when the
    /// model is unavailable, errors, or finds no control.
    func resolve(
        transcript: String,
        controls: [DemoModelControl],
        lastReferencedControl: String?
    ) async -> DemoModelResult? {
        guard Self.isAvailable, !controls.isEmpty else { return nil }

        let session = session ?? LanguageModelSession(instructions: Self.instructions)
        self.session = session

        let inventory = controls.map { "- \($0.label) (\($0.role))" }.joined(separator: "\n")
        var prompt = "Controls on screen:\n\(inventory)\n"
        if let lastReferencedControl {
            prompt += "Most recently acted-on control: \(lastReferencedControl).\n"
        }
        prompt += "The presenter just said: \"\(transcript)\".\n"
        prompt += "Pick the single best control and the action, copying its name exactly."

        do {
            let response = try await session.respond(
                to: prompt,
                generating: DemoModelDecision.self
            )
            let labels = controls.map(\.label)
            let result = map(response.content, controlLabels: labels)
            AppLog.demoMode.notice(
                "Model chose action=\(response.content.action.debugName, privacy: .public) control=\(response.content.control, privacy: .public) resolved=\(result?.label ?? "none", privacy: .public)"
            )
            return result
        } catch {
            AppLog.demoMode.error(
                "On-device intent model failed: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    /// Clears conversation context on teardown or source switch so a new demo
    /// starts fresh.
    func reset() {
        session = nil
    }

    private func map(
        _ decision: DemoModelDecision,
        controlLabels: [String]
    ) -> DemoModelResult? {
        let kind: DemoIntentKind
        switch decision.action {
        case .highlight: kind = .highlight
        case .click: kind = .click
        case .none: return nil
        }

        let target = decision.control.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return nil }

        // The model is told to copy a label verbatim, but guard against drift by
        // resolving to the closest real label.
        guard let resolved = closestLabel(to: target, in: controlLabels) else { return nil }
        return DemoModelResult(kind: kind, label: resolved)
    }

    private func closestLabel(to target: String, in labels: [String]) -> String? {
        if let exact = labels.first(where: {
            $0.caseInsensitiveCompare(target) == .orderedSame
        }) {
            return exact
        }
        let targetTokens = DemoText.tokenizeLabel(target)
        guard !targetTokens.isEmpty else { return nil }

        var best: (label: String, score: Double)?
        for label in labels {
            let labelTokens = DemoText.tokenizeLabel(label)
            guard
                let match = DemoLabelMatcher.bestMatch(
                    labelTokens: labelTokens,
                    transcriptTokens: targetTokens
                ),
                match.score >= DemoIntentPolicy.scoreFloor
            else { continue }
            if best.map({ match.score > $0.score }) ?? true {
                best = (label, match.score)
            }
        }
        return best?.label
    }
}
