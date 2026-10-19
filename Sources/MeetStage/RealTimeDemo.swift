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
    /// What the target looks like and where it sits, in Claude's words when it was
    /// recorded (`ScoutNote.target`), for finding it again once it moved or was
    /// renamed. Untrusted data: never part of what identifies, matches, compares or
    /// fingerprints the locator, and never read by the policy.
    var note: String?

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

extension DemoElementLocator {
    /// Words that name a button that toggles, such as an eye that hides balances.
    static let toggleWords =
        #"discreet|privacy|hide balances|show balances|mask|dark mode|light mode|theme|mute|toggle|modo discreto"#

    static func namesToggle(_ label: String) -> Bool {
        label.range(of: toggleWords, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// A checkbox or switch, or a button named like one: a second click flips it back.
    var isToggleLike: Bool {
        roleClass == .checkbox || toggleValueAfter != nil || Self.namesToggle(label)
    }

    /// Words on a control that saves, submits or adds something, where a second
    /// click could do it twice. Sending, paying and deleting are never clicked at all.
    static let commitWords =
        #"\b(save|create|add|new|apply|ok|done|go|next|continue|finish|update|upload|import|book|order|join|accept|allow"#
        + #"|guardar|crear|añadir|agregar|nuev[oa]|aplicar|aceptar|listo|siguiente|continuar|salvar|adicionar|próximo"#
        + #"|enregistrer|créer|ajouter|nouveau|nouvelle|appliquer|valider|suivant|terminer|speichern|erstellen"#
        + #"|hinzufügen|neu|übernehmen|fertig|weiter|salva|crea|aggiungi|nuov[oa]|applica|fatto|avanti|opslaan"#
        + #"|maken|toevoegen|nieuw|toepassen|klaar|volgende)\b"#

    /// The words that name this control: its recorded label, and the label and help
    /// text of `node`, the control as the screen has it now.
    func words(with node: AXNode?) -> [String] {
        [label, node?.label ?? "", node?.help ?? ""].filter { !$0.isEmpty }
    }

    /// Whether clicking this control again, after a click that seemed to show nothing,
    /// could do what the first did twice: a switch or a button named like one, or a
    /// control whose words save, submit or add something.
    func clickingAgainCouldRepeat(node: AXNode?) -> Bool {
        guard !isToggleLike, node?.toggleValue == nil else { return true }
        return words(with: node).contains { word in
            Self.namesToggle(word)
                || word.range(of: Self.commitWords, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    /// Equal when they describe the same element the same way: `note` is only a
    /// hint about it, so it never makes two locators differ.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.role == rhs.role && lhs.subrole == rhs.subrole && lhs.identifier == rhs.identifier
            && lhs.label == rhs.label && lhs.labelIsStable == rhs.labelIsStable && lhs.container == rhs.container
            && lhs.visualIndex == rhs.visualIndex && lhs.rect == rhs.rect
            && lhs.toggleValueAfter == rhs.toggleValueAfter
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(role)
        hasher.combine(subrole)
        hasher.combine(identifier)
        hasher.combine(label)
        hasher.combine(labelIsStable)
        hasher.combine(container)
        hasher.combine(visualIndex)
        hasher.combine(rect)
        hasher.combine(toggleValueAfter)
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

    /// The action with no notes on its targets, which encodes as actions recorded
    /// before targets had notes.
    var withoutNotes: DemoAction {
        func plain(_ locator: DemoElementLocator) -> DemoElementLocator {
            var locator = locator
            locator.note = nil
            return locator
        }
        return switch self {
        case .click(let locator): .click(plain(locator))
        case .typeText(let field, let text, let submit): .typeText(field: plain(field), text: text, submit: submit)
        case .present(let beat): .present(DemoBeat(effect: beat.effect, targets: beat.targets.map(plain)))
        case .press, .navigate: self
        }
    }
}

struct RevealHint: Codable, Hashable, Sendable {
    var container: ContainerKey?
    var directionDown: Bool
    /// How many scroll turns the scout took; nil means one.
    var count: Int?
    /// `.realWheel` when Accessibility's scrolling moved nothing on screen and real
    /// scrolling did. Nil otherwise, which keeps fingerprints of demos built before it.
    var route: DemoStepRoute?
}

/// How a step's input reached the app while building, which replay starts from
/// in the background. Accessibility comes first for every step; the others are
/// recorded only when an earlier route performed the input and the app showed nothing.
enum DemoStepRoute: String, Codable, Hashable, Sendable {
    case accessibility
    /// The page's own click, in a browser whose page scripts run.
    case pageScript
    /// A real mouse click.
    case pointer
    /// The real key.
    case realKey
    /// Real scroll-wheel input.
    case realWheel

    /// Whether replay may try `route` for an input recorded with this one: one that
    /// needed the page's click skips Accessibility, and one that needed real input
    /// skips the page's script too. Presenting, which has only Accessibility and real
    /// input, is left with real input.
    func allows(_ route: DemoInputRoute) -> Bool {
        switch self {
        case .accessibility: true
        case .pageScript: route == .browser || route.isReal
        case .pointer, .realKey, .realWheel: route.isReal
        }
    }

    /// The route a click tries next when one through `used` reached the app and the
    /// screen showed nothing: the page's own click after Accessibility's press (the
    /// driver gives a real click where page scripts can't run), then a real click.
    /// Nil after real input, or when nothing was clicked.
    static func afterSilentClick(_ used: DemoInputRoute?) -> DemoStepRoute? {
        switch used {
        case .accessibility: .pageScript
        case .browser: .pointer
        default: nil
        }
    }

    /// What a click that showed through `used` records, so replay starts there.
    init(click used: DemoInputRoute?) {
        self =
            switch used {
            case .browser: .pageScript
            case .borrowedScreen, .foreground: .pointer
            default: .accessibility
            }
    }

    /// What the scout tells Claude a step needed, or nil for Accessibility.
    var neededNote: String? {
        switch self {
        case .accessibility: nil
        case .pageScript: "needed the page’s own click"
        case .pointer: "needed a real click"
        case .realKey: "needed the real key"
        case .realWheel: "needed real scrolling"
        }
    }
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
    /// The route that worked while building, which replay tries first in the
    /// background: a control that ignored Accessibility's press, or a key
    /// Accessibility did that the app didn't show, records the one after it.
    var route = DemoStepRoute.accessibility
    /// How far, in window fractions, scrolling this step's targets into view moved
    /// the content up while building. Nil for steps built before targets were framed.
    var framing: Double?
    /// How far framing for actions left out of the demo moved the content up while
    /// building, after the step before this one, in window fractions.
    var priorFraming: Double?
    /// Whether the action visibly changed the screen while building: false when it
    /// showed nothing, nil for highlights, actions whose result went unseen, and
    /// steps built before it was recorded. Testing clicks once more, on the next
    /// route, when a click that did shows nothing.
    var changedScreen: Bool?

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

    private enum CodingKeys: String, CodingKey {
        case id, title, script, holdSeconds, action, pre, reveal, approved, approvedReason, route, framing
        case priorFraming, changedScreen
    }

    /// Demos saved before routes were recorded marked a step that needed a real click with this.
    private enum LegacyCodingKeys: String, CodingKey {
        case usesPointer
    }
}

extension DemoStep {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        script = try container.decode(String.self, forKey: .script)
        holdSeconds = try container.decode(Double.self, forKey: .holdSeconds)
        action = try container.decode(DemoAction.self, forKey: .action)
        pre = try container.decode(ScreenSignature.self, forKey: .pre)
        reveal = try container.decodeIfPresent(RevealHint.self, forKey: .reveal)
        approved = try container.decode(Bool.self, forKey: .approved)
        approvedReason = try container.decodeIfPresent(String.self, forKey: .approvedReason)
        framing = try container.decodeIfPresent(Double.self, forKey: .framing)
        priorFraming = try container.decodeIfPresent(Double.self, forKey: .priorFraming)
        changedScreen = try container.decodeIfPresent(Bool.self, forKey: .changedScreen)
        if let route = try container.decodeIfPresent(DemoStepRoute.self, forKey: .route) {
            self.route = route
        } else {
            let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
            route = try legacy.decodeIfPresent(Bool.self, forKey: .usesPointer) == true ? .pointer : .accessibility
        }
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
    /// A few words that read after "Starts on". Optional so demos saved before it existed still load.
    var label: String?
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
    /// What Claude said the action would do, in at most 12 words. Nil for scrolls,
    /// highlights, rejections, and actions it said nothing about.
    var expected: String?
    /// How Claude judged the action from the screen that followed it. A hint: the
    /// steps a demo keeps follow what was observed, and a wrong turn only helps
    /// tell a detour that came back to where it began.
    var judgement: ScoutJudgement?
    /// The screen the turn began on (`AXSnapshot.screenKey`), for telling that a
    /// later turn began on it again. Nil for rejections and records saved before it.
    var screen: String?
}

/// How Claude says its last action turned out.
enum ScoutVerdict: String, Codable, CaseIterable, Sendable {
    /// Turn 1, or nothing to judge.
    case none
    case asExpected = "as_expected"
    case partly
    /// The screen changed, but not the way the demo needs.
    case wrongTurn = "wrong_turn"
    case noEffect = "no_effect"
}

/// Claude's verdict on its last action and why, in at most 15 words.
struct ScoutJudgement: Codable, Hashable, Sendable {
    var verdict: ScoutVerdict
    var reason: String
}

/// The steps Claude's finish says show one beat of its outline.
struct ScoutBeatCoverage: Codable, Hashable, Sendable {
    /// The beat's number in the outline, from 1.
    var beat: Int
    /// The # numbers of the executed facts whose actions or highlights show it.
    var steps: [Int]
}

struct ScoutDraft: Codable, Hashable, Sendable {
    var records: [ScoutRecord] = []
    var outline: [String] = []
    var turn = 0
    var spentMicroUSD = 0
    /// What Claude's latest finish said shows each beat; nil before one.
    var coverage: [ScoutBeatCoverage]?
    /// A finish was turned back once, for a beat no step shows or nothing highlighted
    /// when the request asks to show something, so the next one is accepted.
    var finishTurnedBack: Bool?

    /// The turns the finish cited, which compaction never cuts as a detour.
    var citedTurns: Set<Int> { Set(coverage?.flatMap(\.steps) ?? []) }
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
    /// The build's draft as it was compiled, every record kept as the scout made it,
    /// so the demo can be compiled again without pruning detours
    /// (`ScoutCompaction.compact(_:pruning:)`). Nil for demos compiled before it.
    var compiledFrom: ScoutDraft?

    var draft: ScoutDraft? {
        if case .draft(let draft) = status { draft } else { nil }
    }

    /// A build that stopped before it read its first screen, so there's nothing to keep.
    var isEmptyDraft: Bool { draft != nil && start == nil }

    var isCompiled: Bool {
        if case .draft = status { false } else { !steps.isEmpty && start != nil }
    }

    /// The start screen in a few words, for "Starts on {startLabel}". Demos without
    /// a label get one from the first clause of the start description.
    var startLabel: String {
        let fallback = "the starting screen"
        if let label = start?.label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty { return label }
        var text = Substring(start?.description ?? "")
        for separator in [",", " with "] {
            if let range = text.range(of: separator) { text = text[..<range.lowerBound] }
        }
        if let range = text.range(of: " on the ") { text = text[text.index(range.lowerBound, offsetBy: 4)...] }
        text = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
        if text.hasSuffix(".") { text = text.dropLast() }
        let label = text.split(whereSeparator: \.isWhitespace).prefix(4).joined(separator: " ")
        return label.isEmpty || label.count > 32 ? fallback : label
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
    /// window size class. Scripts, titles, holds, highlights, and Claude's notes on
    /// targets are excluded.
    static func make(_ demo: RealTimeDemo, appVersion: String, sizeClass: DemoSizeClass, window: String = "") -> String
    {
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
            actions: mutating.map(\.action.withoutNotes), reveals: mutating.map(\.reveal), appVersion: appVersion,
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
    /// A step needs the app in front, and the presenter never left the Mac alone long enough to lend it.
    case noPause(String)
    case leftScope(String)
    case modelDeclined
    case incompleteResponse
    case requestFailed(DemoRequestFailureSummary)

    var errorDescription: String? {
        switch self {
        case .invalidPlan: "This demo has an invalid step. Edit it or build it again."
        case .missingKey: "Add your Anthropic API key in Settings › Demos."
        case .missingSource: "Choose a live source window first."
        case .permission: "Allow BetterMeets in System Settings → Privacy & Security → Accessibility, then try again."
        case .screenshot: "Couldn’t read the source window. Make sure it’s visible, then try again."
        case .sourceChanged: "The source window changed. Select the demo’s window to continue."
        case .focusChanged: "Paused because the source window lost focus."
        case .invalidResponse: "Claude returned an incomplete answer. Try again."
        case .missingConsent: "Allow Claude to see and operate the selected window in Settings › Demos."
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
        case .noPause(let app):
            "This step needs \(app) in front for a moment. Resume when you can leave the keyboard and pointer alone for a second."
        case .leftScope(let reason): reason
        case .modelDeclined: "Claude declined this request. Edit it and try again."
        case .incompleteResponse: "Claude’s answer was cut off. Try again."
        case .requestFailed(let failure): failure.message
        }
    }

    var diagnosticDetails: String? {
        if case .requestFailed(let failure) = self { failure.details } else { nil }
    }

    var isNoPause: Bool {
        if case .noPause = self { true } else { false }
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
    /// The API refused to compile the request's strict tool schemas into a grammar.
    let isSchemaTooComplex: Bool

    init(_ failure: DemoRequestFailure) {
        message = failure.message
        details = failure.details
        isRetryable = [408, 429, 500, 502, 503, 504, 529].contains(failure.status)
        isSchemaTooComplex =
            failure.status == 400
            && failure.reason?.range(
                of: "grammar is too large|too complex for compilation", options: [.regularExpression, .caseInsensitive])
                != nil
    }
}

enum DemoPlaybackSpeed: Double, CaseIterable, Identifiable, Sendable {
    case normal = 1, brisk = 1.5, fast = 2, fastest = 3
    var id: Self { self }
    var label: String { "\(rawValue.formatted())×" }
}
