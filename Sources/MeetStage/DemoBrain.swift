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

/// Suppresses a transcriber's re-emitted final segment before it can trigger a
/// duplicate paid vision request. Provider and window are part of the key so a
/// deliberate provider comparison or source switch is never mistaken for a
/// duplicate on the old context.
struct DemoBrainRequestGate {
    static let defaultCooldown: TimeInterval = 2

    private struct Key: Equatable {
        let transcript: String
        let provider: DemoBrainProvider
        let windowID: CGWindowID
    }

    private var lastRequest: (key: Key, time: TimeInterval)?

    mutating func admit(
        transcript: String,
        provider: DemoBrainProvider,
        windowID: CGWindowID,
        at now: TimeInterval,
        cooldown: TimeInterval = defaultCooldown
    ) -> Bool {
        let key = Key(transcript: transcript, provider: provider, windowID: windowID)
        if let lastRequest, lastRequest.key == key,
            now - lastRequest.time < cooldown
        {
            return false
        }
        lastRequest = (key, now)
        return true
    }

    mutating func reset() {
        lastRequest = nil
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
    /// disagree with the coordinator's cached key-presence state.
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

    /// Resolves an image-pixel fallback into window fractions, rejecting an
    /// out-of-bounds model coordinate instead of clamping it onto a window edge.
    func normalizedPoint(in imagePixelSize: CGSize) -> CGPoint? {
        guard elementID == nil, let point,
            imagePixelSize.width.isFinite, imagePixelSize.height.isFinite,
            imagePixelSize.width > 0, imagePixelSize.height > 0,
            point.x.isFinite, point.y.isFinite,
            point.x >= 0, point.x <= imagePixelSize.width,
            point.y >= 0, point.y <= imagePixelSize.height
        else { return nil }

        return CGPoint(
            x: point.x / imagePixelSize.width,
            y: point.y / imagePixelSize.height
        )
    }
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
        case .missingKey: String(localized: "Add an API key to use conversational commands")
        case let .http(status, detail):
            switch status {
            case 401, 403: String(localized: "Check your API key")
            // A 429 whose body cites quota is out-of-credit/billing, not throttling.
            case 429 where detail.localizedCaseInsensitiveContains("quota"):
                String(localized: "Out of API credits — check billing")
            case 429: String(localized: "Rate limited — slow down")
            default: String(localized: "Assistant error (\(status))")
            }
        case .transport: String(localized: "Assistant unreachable")
        }
    }

    /// Whether the failure is persistent (should disable, not just blip). Auth
    /// failures and out-of-credit quota errors won't fix themselves on retry.
    var isPersistent: Bool {
        if case let .http(status, detail) = self {
            if status == 401 || status == 403 { return true }
            if status == 429, detail.localizedCaseInsensitiveContains("quota") { return true }
        }
        return false
    }
}

/// Which cloud model powers the conversational brain. The presenter can switch
/// between them to compare grounding quality, latency, and cost on their own demo.
enum DemoBrainProvider: String, CaseIterable, Identifiable, Sendable {
    case claude
    case openai

    var id: Self { self }

    /// Full model name, shown in the settings picker.
    var label: String {
        switch self {
        case .claude: String(localized: "Claude Haiku 4.5")
        case .openai: String(localized: "GPT-5.6 Luna")
        }
    }

    /// Vendor name, for the API-key field placeholder and notes.
    var vendor: String {
        switch self {
        case .claude: String(localized: "Anthropic")
        case .openai: String(localized: "OpenAI")
        }
    }

    /// The Keychain store holding this provider's API key. Centralizing the
    /// mapping here keeps the coordinator free of provider→store branching.
    var keyStore: any DemoKeyStore {
        switch self {
        case .claude: AnthropicKeyStore()
        case .openai: OpenAIKeyStore()
        }
    }
}

/// Immutable authorization snapshot for one cloud request. The coordinator
/// re-validates it immediately before network dispatch and again before acting
/// on the reply, so changing provider, source, focus, or consent invalidates
/// work that started under the previous state.
struct DemoCloudRequestContext: Sendable, Equatable {
    let provider: DemoBrainProvider
    let windowID: CGWindowID

    func remainsAuthorized(
        isDemoModeEnabled: Bool,
        isLive: Bool,
        isSourceFocused: Bool,
        hasCloudConsent: Bool,
        selectedProvider: DemoBrainProvider,
        selectedWindowID: CGWindowID?
    ) -> Bool {
        isDemoModeEnabled
            && isLive
            && isSourceFocused
            && hasCloudConsent
            && selectedProvider == provider
            && selectedWindowID == windowID
    }
}

/// A conversational intent resolver. Implementations are off-main network or
/// on-device model calls; the coordinator applies all safety gates afterward.
protocol DemoBrain: Sendable {
    /// Resolves one utterance, or nil when nothing was confidently commanded.
    func decide(_ request: DemoBrainRequest) async throws -> DemoBrainDecision?
}
