import CryptoKit
import Foundation

// MARK: - Geometry

/// A rectangle in source-window fractions with a top-left origin. Values may
/// fall outside 0…1 for content scrolled just off-screen.
struct NormRect: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double

    var midX: Double { x + w / 2 }
    var midY: Double { y + h / 2 }
    var maxY: Double { y + h }
    var center: NormalizedWindowPoint { NormalizedWindowPoint(x: midX, y: midY) }
    var bounds: NormalizedAnnotationBounds { NormalizedAnnotationBounds(minX: x, minY: y, width: w, height: h) }

    var isUsable: Bool {
        [x, y, w, h].allSatisfy(\.isFinite) && w > 0 && h > 0
    }


    func union(_ other: NormRect) -> NormRect {
        let minX = min(x, other.x)
        let minY = min(y, other.y)
        return NormRect(
            x: minX, y: minY, w: max(x + w, other.x + other.w) - minX, h: max(y + h, other.y + other.h) - minY)
    }

    func distance(to other: NormRect) -> Double {
        hypot(midX - other.midX, midY - other.midY)
    }

    /// The part of the rectangle inside the window, for drawing and aiming.
    var clampedToWindow: NormRect {
        let minX = max(0, x)
        let minY = max(0, y)
        return NormRect(x: minX, y: minY, w: max(0, min(1, x + w) - minX), h: max(0, min(1, y + h) - minY))
    }
}

enum DemoSizeClass: String, Codable, Sendable {
    case compact, regular, wide

    init(windowWidth: Double) {
        self = windowWidth < 1_000 ? .compact : windowWidth < 1_500 ? .regular : .wide
    }
}

// MARK: - App identity

enum AppEngine: String, Codable, Sendable {
    case native, electron, chromium, gecko, webkit

    var rendersWebContent: Bool { self != .native }
}

struct DemoAppKey: Codable, Hashable, Sendable {
    var bundleID: String
    var appName: String
    var engine: AppEngine
    var isBrowser: Bool

    func matches(_ source: DemoSource) -> Bool {
        bundleID.isEmpty ? appName == source.name : bundleID == source.bundleID
    }
}

// MARK: - Locators

/// The nearest structural container of an element: a table, list, tab group,
/// web area, landmark, or labelled group.
struct ContainerKey: Codable, Hashable, Sendable {
    var role: String
    var subrole: String?
    var label: String
}

/// A durable description of one element, recorded while scouting and matched
/// against the live Accessibility tree during replay. It never stores
/// coordinates as the primary identity; `rect` is only a tiebreaker.
struct DemoElementLocator: Codable, Hashable, Sendable {
    var role: String
    var subrole: String?
    var identifier: String?
    /// Original casing for display. Empty when the label is data (amounts, names, dates).
    var label: String
    var labelIsStable: Bool
    var container: ContainerKey?
    /// Index among same-role elements in the container in visual order. Used for data rows.
    var visualIndex: Int?
    var rect: NormRect
    /// Checkbox or switch value observed after the recorded click, so replay never flips it twice.
    var toggleValueAfter: Bool?

    var roleClass: AXRoleClass { AXRoleClass(role: role, subrole: subrole) }

    /// A short, presenter-facing description, e.g. “Transactions” or “row 1 in Operations”.
    var displayName: String {
        if labelIsStable, !label.isEmpty { return label }
        let kind = roleClass.noun
        if let visualIndex, DemoLocatorMatcher.ordersByIndex(container) {
            let place = container.map { $0.label.isEmpty ? "" : " in \($0.label)" } ?? ""
            return "\(kind) \(visualIndex + 1)\(place)"
        }
        return kind
    }
}

// MARK: - Screen identity

/// Code-derived evidence of which screen is showing. It stays advisory until a
/// verification run confirms it, then gates replay.
struct ScreenSignature: Codable, Hashable, Sendable {
    var urlKey: String?
    var selected: [String]
    var headings: [String]
    var dialogOpen: Bool
    var confirmed: Bool = false
}

// MARK: - Steps

enum DemoEffect: String, Codable, CaseIterable, Sendable {
    case spotlight, magnify, draw

    var label: String {
        switch self {
        case .spotlight: "Spotlight"
        case .magnify: "Magnify"
        case .draw: "Circle"
        }
    }

    var symbol: String {
        switch self {
        case .spotlight: "flashlight.on.fill"
        case .magnify: "plus.magnifyingglass"
        case .draw: "pencil.and.outline"
        }
    }
}

struct DemoBeat: Codable, Hashable, Sendable {
    var effect: DemoEffect
    var targets: [DemoElementLocator]
}

/// Keys the demo may press. Return, Space, and command chords are deliberately
/// absent: Return only follows typing into a search field.
enum DemoKey: String, Codable, CaseIterable, Sendable {
    case escape, tab, shiftTab = "shift_tab", up, down, left, right, pageUp = "page_up", pageDown = "page_down"

    var badge: String {
        switch self {
        case .escape: "esc"
        case .tab: "⇥"
        case .shiftTab: "⇧⇥"
        case .up: "↑"
        case .down: "↓"
        case .left: "←"
        case .right: "→"
        case .pageUp: "⇞"
        case .pageDown: "⇟"
        }
    }
}

enum DemoAction: Codable, Hashable, Sendable {
    case click(DemoElementLocator)
    case typeText(field: DemoElementLocator, text: String, submit: Bool)
    case press(DemoKey)
    case navigate(URL)
    case present(DemoBeat)

    var isMutating: Bool {
        if case .present = self { false } else { true }
    }

    var locators: [DemoElementLocator] {
        switch self {
        case .click(let locator): [locator]
        case .typeText(let field, _, _): [field]
        case .present(let beat): beat.targets
        case .press, .navigate: []
        }
    }

    var symbol: String {
        switch self {
        case .click: "cursorarrow.rays"
        case .typeText: "character.cursor.ibeam"
        case .press: "command.square"
        case .navigate: "globe"
        case .present(let beat): beat.effect.symbol
        }
    }

    var kindLabel: String {
        switch self {
        case .click: "Click"
        case .typeText: "Type"
        case .press: "Press key"
        case .navigate: "Open page"
        case .present(let beat): beat.effect.label
        }
    }
}

struct RevealHint: Codable, Hashable, Sendable {
    var container: ContainerKey?
    var directionDown: Bool
    /// How many scroll turns the scout took; nil means one.
    var count: Int?
}

struct DemoStep: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var title: String
    var script: String
    var holdSeconds: Double
    var action: DemoAction
    var pre: ScreenSignature
    var reveal: RevealHint?
    var approved = false
    /// What the presenter approved, so replay accepts only that same decision.
    var approvedReason: String?
    /// The click needs a real pointer: the control ignored Accessibility's press.
    var usesPointer: Bool?

    /// Presenters read aloud at about 150 words a minute.
    static let wordsPerSecond = 2.5

    /// How long it takes to say `script` aloud.
    static func speakingTime(for script: String) -> Double {
        Double(script.split(whereSeparator: \.isWhitespace).count) / wordsPerSecond
    }

    static func hold(for script: String, action: DemoAction) -> Double {
        let words = script.split(whereSeparator: \.isWhitespace).count
        if words == 0 { return action.isMutating ? 0.4 : 1.6 }
        return min(20, max(1.5, speakingTime(for: script) + 0.8))
    }
}

// MARK: - Start point

struct ToggleState: Codable, Hashable, Sendable {
    var locator: DemoElementLocator
    var isOn: Bool
}

struct DemoStartPoint: Codable, Hashable, Sendable {
    var signature: ScreenSignature
    /// Full start URL, stored on this Mac only. Models see host and path.
    var url: URL?
    var returnAnchor: DemoElementLocator?
    var toggles: [ToggleState]
    var description: String
    var sizeClass: DemoSizeClass
}

// MARK: - Scouting draft

enum ActOutcome: String, Codable, Sendable {
    /// Recorded before dispatch; becomes one of the others once observed.
    case pending
    case changed, noEffect
    /// The presenter touched the mouse or keyboard while the action settled.
    case contaminated
    /// Dispatched, but the build stopped before its result was seen.
    case unobserved
    case rejected
}

struct ScoutRecord: Codable, Hashable, Sendable {
    var turn: Int
    /// One step for an action, one per beat for a presentation, none for a scroll.
    var steps: [DemoStep]
    var scroll: RevealHint?
    var outcome: ActOutcome
    var fact: String
}

struct ScoutDraft: Codable, Hashable, Sendable {
    var records: [ScoutRecord] = []
    var outline: [String] = []
    var turn = 0
    var spentMicroUSD = 0
}

// MARK: - Demo

struct DemoVerification: Codable, Hashable, Sendable {
    var checkedAt: Date
    var fingerprint: String
}

enum DemoStatus: Codable, Hashable, Sendable {
    case draft(ScoutDraft)
    case recorded
    case checked(DemoVerification)
}

struct RealTimeDemo: Codable, Hashable, Identifiable, Sendable {
    static let maximumSteps = 40

    var schemaVersion = 2
    var id = UUID()
    var revision = 0
    var prompt: String
    var app: DemoAppKey
    var title: String
    var outline: [String] = []
    var start: DemoStartPoint?
    var steps: [DemoStep] = []
    var status: DemoStatus
    var closingScript = ""
    /// Said before the first step. Optional so demos saved before it existed still load.
    var openingScript: String?

    var draft: ScoutDraft? {
        if case .draft(let draft) = status { draft } else { nil }
    }

    var isCompiled: Bool {
        if case .draft = status { false } else { !steps.isEmpty && start != nil }
    }

    var estimatedSeconds: Int {
        Int(steps.reduce(0) { $0 + $1.holdSeconds + ($1.action.isMutating ? 0.8 : 0.3) }.rounded())
    }

    var presenterScript: String {
        var lines = [title]
        if let start { lines.append("Start on: \(start.description)") }
        if let openingScript, !openingScript.isEmpty { lines.append(openingScript) }
        var number = 0
        for step in steps where !step.script.isEmpty {
            number += 1
            lines.append("\(number). \(step.title)\n\(step.script)")
        }
        if !closingScript.isEmpty { lines.append(closingScript) }
        return lines.joined(separator: "\n\n")
    }

    func validated() throws -> Self {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 120,
            steps.count <= Self.maximumSteps, Set(steps.map(\.id)).count == steps.count
        else { throw DemoError.invalidPlan }
        for step in steps {
            guard !step.title.isEmpty, step.title.count <= 80, step.script.count <= 400,
                step.holdSeconds.isFinite, (0.2...30).contains(step.holdSeconds)
            else { throw DemoError.invalidPlan }
            if case .present(let beat) = step.action, !(1...6).contains(beat.targets.count) {
                throw DemoError.invalidPlan
            }
        }
        return self
    }
}

enum DemoFingerprint {
    /// Identifies everything that decides whether a checked replay still holds:
    /// the start, every action that changes the app, the app version, and the
    /// window size class. Scripts, titles, holds, and highlights are excluded.
    static func make(_ demo: RealTimeDemo, appVersion: String, sizeClass: DemoSizeClass, window: String = "") -> String {
        struct Payload: Encodable {
            let host: String?
            let path: String?
            let start: ScreenSignature?
            let actions: [DemoAction]
            let reveals: [RevealHint?]
            let appVersion: String
            let sizeClass: DemoSizeClass
            let window: String
        }
        let mutating = demo.steps.filter(\.action.isMutating)
        let payload = Payload(
            host: demo.start?.url?.host, path: demo.start?.url?.path, start: demo.start?.signature,
            actions: mutating.map(\.action), reveals: mutating.map(\.reveal), appVersion: appVersion,
            sizeClass: sizeClass, window: window)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(payload)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Errors

enum DemoError: LocalizedError, Equatable {
    case invalidPlan, missingKey, missingSource, permission, screenshot
    case sourceChanged, focusChanged, invalidResponse, missingConsent, keychain
    case webContentUnavailable(AppEngine)
    case targetNotFound(String)
    case occluded(String)
    case typingFailed(String)
    case addressBarUnavailable
    case policyDenied(String)
    /// The app refused the input before anything happened, so it is safe to retry.
    case inputNotDelivered(String)
    case leftScope(String)
    case modelDeclined
    case incompleteResponse
    case requestFailed(DemoRequestFailureSummary)

    var errorDescription: String? {
        switch self {
        case .invalidPlan: "This demo has an invalid step. Edit it or build it again."
        case .missingKey: "Add your Anthropic API key in Demo Setup."
        case .missingSource: "Choose a live source window first."
        case .permission: "Allow BetterMeets in System Settings → Privacy & Security → Accessibility, then try again."
        case .screenshot: "Couldn’t read the source window. Make sure it’s visible, then try again."
        case .sourceChanged: "The source window changed. Select the demo’s window to continue."
        case .focusChanged: "Paused because the source window lost focus."
        case .invalidResponse: "Claude returned an incomplete answer. Try again."
        case .missingConsent: "Allow Claude to see and control the selected window in Demo Setup."
        case .keychain: "Couldn’t save the key to Keychain. Try again."
        case .webContentUnavailable(let engine):
            engine == .gecko
                ? "This browser isn’t exposing its page to Accessibility. In about:config, set accessibility.force_disabled to 0, then try again."
                : "This app isn’t exposing its page to Accessibility yet. Wait for it to load, then try again."
        case .targetNotFound(let name): "Couldn’t find “\(name)”."
        case .occluded(let name): "Something is covering “\(name)”. Close it, then try again."
        case .typingFailed(let name): "Couldn’t type into “\(name)”."
        case .addressBarUnavailable: "Couldn’t reach the browser’s address bar."
        case .policyDenied(let reason): reason
        case .inputNotDelivered(let name): "“\(name)” didn’t respond."
        case .leftScope(let reason): reason
        case .modelDeclined: "Claude declined this request. Edit it and try again."
        case .incompleteResponse: "Claude’s answer was cut off. Try again."
        case .requestFailed(let failure): failure.message
        }
    }

    var diagnosticDetails: String? {
        if case .requestFailed(let failure) = self { failure.details } else { nil }
    }

    /// Errors raised before any input reached the app.
    var wasNotDelivered: Bool {
        switch self {
        case .inputNotDelivered, .occluded, .targetNotFound, .policyDenied, .addressBarUnavailable: true
        default: false
        }
    }
}

/// Equatable, Sendable copy of a failed API response for errors and phases.
struct DemoRequestFailureSummary: Equatable, Sendable {
    let message: String
    let details: String
    let isRetryable: Bool

    init(_ failure: DemoRequestFailure) {
        message = failure.message
        details = failure.details
        isRetryable = [408, 429, 500, 502, 503, 504, 529].contains(failure.status)
    }
}

enum DemoPlaybackSpeed: Double, CaseIterable, Identifiable, Sendable {
    case normal = 1, brisk = 1.5, fast = 2, fastest = 3
    var id: Self { self }
    var label: String { "\(rawValue.formatted())×" }
}
