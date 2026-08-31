import CoreGraphics
import Foundation

/// One resolved exchange kept for conversational context ("highlight X" … then
/// "click it"). Stored as plain text so the model resolves pronouns from it.
struct DemoConversationTurn: Sendable, Equatable {
    let user: String
    let assistant: String
}

/// Short rolling memory of the demo dialogue, handed to the brain each turn.
struct DemoConversation {
    static let maxTurns = 8

    private(set) var turns: [DemoConversationTurn] = []

    mutating func record(user: String, assistant: String) {
        turns.append(DemoConversationTurn(user: user, assistant: assistant))
        if turns.count > Self.maxTurns {
            turns.removeFirst(turns.count - Self.maxTurns)
        }
    }

    mutating func reset() {
        turns.removeAll()
    }
}

/// One control offered to the brain, with a stable id it can select by.
struct DemoBrainControl: Sendable, Equatable {
    let id: Int
    let label: String
    let role: String
}

/// Everything the brain needs to resolve one utterance.
struct DemoBrainRequest: Sendable {
    /// Read once on the main actor at dispatch, so a background re-read can't
    /// disagree with the `isConfigured` gate.
    let apiKey: String
    let transcript: String
    let history: [DemoConversationTurn]
    let controls: [DemoBrainControl]
    /// Base64 JPEG of the source window, or nil if a capture wasn't available.
    let imageJPEGBase64: String?
    /// Pixel size of that image, the coordinate space for `point`.
    let imagePixelSize: CGSize
    let allowsClicking: Bool
}

enum DemoBrainAction: String, Sendable {
    case highlight
    case click
    /// Focus a field and type `text` into it.
    case type
    /// Draw an annotation circle around the target.
    case circle
    /// Move the focus spotlight (magnifier) onto the target.
    case spotlight
    /// Zoom the Demo Stage to the target.
    case zoom
    case none

    /// Actions that synthesize input into the source app (gated on clicking).
    var actuatesSource: Bool {
        self == .click || self == .type
    }
}

/// The brain's decision. `elementID` is the exact-snap target (preferred);
/// `point` is a vision fallback in image-pixel space for targets not in the list.
struct DemoBrainDecision: Sendable, Equatable {
    let action: DemoBrainAction
    let elementID: Int?
    let point: CGPoint?
    let label: String
    /// The text to enter, for the `type` action.
    let text: String?
}

enum DemoBrainError: Error {
    case missingKey
    /// A non-200 HTTP response, carrying the status so the UI can distinguish a
    /// persistent auth failure (401) from a transient one (429/5xx).
    case http(status: Int, detail: String)
    /// A transport/decoding failure (offline, timeout, malformed body).
    case transport(String)

    /// A short, presenter-facing description.
    var userMessage: String {
        switch self {
        case .missingKey: "Add an API key to use conversational commands"
        case let .http(status, _):
            switch status {
            case 401, 403: "Check your API key"
            case 429: "Rate limited — slow down"
            default: "Assistant error (\(status))"
            }
        case .transport: "Assistant unreachable"
        }
    }

    /// Whether the failure is persistent (should disable, not just blip).
    var isPersistent: Bool {
        if case let .http(status, _) = self { return status == 401 || status == 403 }
        return false
    }
}

/// A conversational intent resolver. Implementations are off-main network or
/// on-device model calls; the coordinator applies all safety gates afterward.
protocol DemoBrain: Sendable {
    /// Whether the brain is configured and usable right now (e.g. key present).
    var isConfigured: Bool { get }

    /// Resolves one utterance, or nil when nothing was confidently commanded.
    func decide(_ request: DemoBrainRequest) async throws -> DemoBrainDecision?
}
