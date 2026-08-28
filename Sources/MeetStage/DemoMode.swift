import CoreGraphics
import Foundation

/// Where a Demo Mode element came from. Accessibility elements carry exact
/// press semantics; recognized-text elements are a fallback for apps that
/// expose a sparse accessibility tree (canvas or web-rendered UIs).
enum DemoElementSource: String, Sendable, Equatable {
    case accessibility
    case recognizedText
}

/// A coarse role used only for match scoring and presenter-facing wording.
/// It intentionally does not mirror the full Accessibility role vocabulary.
enum DemoElementRole: String, Sendable, Equatable {
    case button
    case link
    case tab
    case menuItem
    case field
    case text
    case image
    case other

    /// Interactive roles are weighted above descriptive text when two elements
    /// match a spoken phrase equally well.
    var matchWeight: Double {
        switch self {
        case .button, .link, .tab, .menuItem: 1
        case .field: 0.9
        case .image: 0.7
        case .text, .other: 0.6
        }
    }

    var spokenNoun: String {
        switch self {
        case .button: "button"
        case .link: "link"
        case .tab: "tab"
        case .menuItem: "menu item"
        case .field: "field"
        case .image: "image"
        case .text, .other: "control"
        }
    }
}

/// A named, targetable control inside the captured source window.
///
/// The value is `Sendable` so the background accessibility and text-recognition
/// indexers can hand it to the main actor. It deliberately stores no live
/// `AXUIElement`. `normalizedBounds` (window fractions) is the durable target:
/// actuation re-projects it onto the window's live frame at click time, so a
/// window that moved between indexing and the click is still clicked correctly.
/// `screenFrame` is the frame captured at index time, used for de-duplication.
struct DemoElement: Identifiable, Sendable, Equatable {
    /// Stable only within a single index build.
    let id: Int
    /// The human-visible name used for matching and captions.
    let label: String
    let role: DemoElementRole
    let source: DemoElementSource
    /// The element's bounds as fractions of the source window (top-left origin),
    /// used to draw the highlight on both the source overlay and the Demo Stage.
    let normalizedBounds: NormalizedAnnotationBounds
    /// The element's bounds in global Quartz screen points (top-left origin),
    /// used to synthesize a visible click at its center.
    let screenFrame: CGRect
    /// Whether the element advertises a press action. Recognized-text elements
    /// are never independently pressable; a nearby accessibility element must
    /// back them for actuation.
    let pressable: Bool

    var normalizedCenter: NormalizedWindowPoint {
        NormalizedWindowPoint(
            x: normalizedBounds.minX + normalizedBounds.width / 2,
            y: normalizedBounds.minY + normalizedBounds.height / 2
        )
    }

    var screenCenter: CGPoint {
        CGPoint(x: screenFrame.midX, y: screenFrame.midY)
    }
}

/// A snapshot of the controls discovered for one source window at one moment.
struct DemoElementIndex: Sendable, Equatable {
    /// Increments each time the index is rebuilt so stale actions are ignored.
    let generation: Int
    let elements: [DemoElement]

    static let empty = DemoElementIndex(generation: 0, elements: [])

    var isEmpty: Bool { elements.isEmpty }
}

/// What Demo Mode should do about a control named in narration.
enum DemoIntentKind: String, Sendable, Equatable {
    /// Draw attention only (ring highlight plus a gentle zoom).
    case highlight
    /// Actuate the control, then highlight it.
    case click
}

/// A command resolved from one finalized transcript segment.
struct DemoResolvedCommand: Sendable, Equatable {
    let kind: DemoIntentKind
    let element: DemoElement
    /// The words in the transcript that named the control, for the caption HUD.
    let matchedPhrase: String
    /// 0...1 confidence that the phrase named this element.
    let score: Double

    /// A copy that only highlights — used when clicking is requested but the
    /// app lacks Accessibility trust, so the caption and highlight style stay
    /// truthful.
    var downgradedToHighlight: DemoResolvedCommand {
        guard kind == .click else { return self }
        return DemoResolvedCommand(
            kind: .highlight,
            element: element,
            matchedPhrase: matchedPhrase,
            score: score
        )
    }
}
