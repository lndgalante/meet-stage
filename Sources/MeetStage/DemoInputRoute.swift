import Foundation
import MeetStageCore

/// How a run drives the source app.
enum DemoDriveMode: Equatable, Sendable {
    /// Presenting: the app is in front, and real input reaches it at once.
    case foreground
    /// Building, testing, or going back to the start for them, while the person
    /// keeps using their Mac: the window carries BetterMeets' badge and cursor,
    /// and a step that needs the app in front waits for a pause.
    case background(DemoWindowActivity)

    var isBackground: Bool {
        if case .background = self { true } else { false }
    }
}

extension DemoPhase {
    /// How the driver drives the bound source in this phase; nil when nothing runs.
    var driveMode: DemoDriveMode? {
        switch self {
        case .scouting: .background(.building)
        case .returning(.play): .foreground
        case .returning: .background(.returning)
        case .running(.verify, _, _): .background(.testing)
        case .running(.present, _, _): .foreground
        default: nil
        }
    }
}

/// What the source browser's own scripting allows during this run.
struct DemoBrowserAccess: Equatable, Sendable {
    /// The browser can open addresses and run page scripts through its scripting.
    var scriptable: Bool
    var automation: AutomationPermission
    /// Unknown until a page script has tried this run.
    var javaScript: BrowserJavaScriptState

    /// Not a browser BetterMeets can script, or its scripting stopped answering this run.
    static let none = DemoBrowserAccess(scriptable: false, automation: .notDetermined, javaScript: .unknown)

    /// Opening an address sets the tab's URL, which needs only Automation.
    var canOpenAddresses: Bool {
        scriptable && automation != .denied
    }

    /// Page scripts also need the browser's Allow JavaScript from Apple Events.
    var canRunPageScripts: Bool {
        canOpenAddresses && javaScript != .off
    }
}

/// One way an input can reach the source app.
enum DemoInputRoute: Equatable, Sendable {
    /// Accessibility in the background: a press, a value, scrolling into view, a
    /// field's confirm, or what a key or a scroll does in the app's own views.
    case accessibility
    /// The browser's own scripting in the background: a page script in the tab, or the tab's address.
    case browser
    /// Accessibility in the background replacing a field's selected text, for a
    /// field that ignores a new value, as many in Electron apps do.
    case selectedText
    /// Real input with the window borrowed for a moment, once the person pauses.
    case borrowedScreen
    /// Real input with the app in front, as presenting does.
    case foreground

    var isReal: Bool { self == .borrowedScreen || self == .foreground }

    enum Input: Equatable, Sendable {
        case click
        case type
        /// Return in the field a step just typed into.
        case submit
        case key(DemoKey)
        case navigate
        /// Wheel or exact scrolling over a region.
        case scroll
        case scrollToVisible
    }

    /// The routes `input` tries, in order; each one that reaches nothing falls to
    /// the next. Presenting keeps the app in front and uses real input, so only
    /// building and testing try a browser's scripting, Accessibility's stand-ins
    /// for keys and scrolling, or borrow the screen. `inWebArea` says whether the
    /// target (the focused element, for a key) is in a page. `recorded` is the
    /// route that worked while building, which replay starts from.
    static func routes(
        for input: Input, background: Bool, inWebArea: Bool = false, browser: DemoBrowserAccess = .none,
        from recorded: DemoStepRoute = .accessibility
    ) -> [DemoInputRoute] {
        let real: DemoInputRoute = background ? .borrowedScreen : .foreground
        let page: [DemoInputRoute] = background && inWebArea && browser.canRunPageScripts ? [.browser] : []
        // A page keeps its own script for keys and scrolling; the app's own views take Accessibility's.
        let native: [DemoInputRoute] = background && !inWebArea ? [.accessibility] : []
        let ladder: [DemoInputRoute]
        switch input {
        case .scrollToVisible:
            return [.accessibility]
        case .click:
            ladder = [.accessibility] + page + [real]
        case .type:
            ladder = [.accessibility] + page + (background ? [.selectedText] : []) + [real]
        case .submit:
            guard background else { return [real] }
            // A page's field submits through its form; a native field may confirm through Accessibility.
            return inWebArea ? page + [real] : [.accessibility, real]
        case .key(let key):
            let script = key.pageScriptActsLikeTheKey ? page : []
            ladder = (inWebArea ? script : key.accessibilityActsLikeTheKey ? native : []) + [real]
        case .scroll:
            ladder = (inWebArea ? page : native) + [real]
        case .navigate:
            return (background && browser.canOpenAddresses ? [.browser] : []) + [real]
        }
        return ladder.filter(recorded.allows)
    }

    /// The policy's kind for a page control's ARIA or implicit role.
    static func policyKind(webRole role: String?) -> DemoPolicyElement.Kind? {
        switch role {
        case "button": .button
        case "link": .link
        case "tab": .tab
        case "radio", "menuitemradio": .radio
        case "checkbox", "switch", "menuitemcheckbox": .checkbox
        case "menuitem": .menuItem
        case "textbox", "searchbox", "combobox": .field
        case "row": .row
        case "cell", "gridcell": .cell
        default: nil
        }
    }

    /// Whether the page's own click may click the control it read at the point: only
    /// when the policy allows it outright. The policy judges it by its web role, else
    /// by `fallback` (the kind Accessibility gives the target there), and as a dialog's
    /// control when the target sits in one. A control the policy would ask about, such
    /// as a dialog's button other than a dismissal, falls to the real click; one it
    /// denies throws, which stops the step.
    static func pageClickAllowed(
        webRole: String?, label: String, fallback: DemoPolicyElement.Kind?, inDialog: Bool
    ) throws -> Bool {
        guard let kind = policyKind(webRole: webRole) ?? fallback else { return false }
        let element = DemoPolicyElement(
            kind: kind, label: label, labelIsData: kind == .row || kind == .cell, inDialog: inDialog)
        switch DemoActionPolicy.evaluate(.click(element), prompt: "", startHost: nil, approved: false) {
        case .allow: return true
        case .needsApproval: return false
        case .deny(let reason): throw DemoError.policyDenied(reason)
        }
    }
}

/// What a delivered input is known to have done, beyond the route that carried it,
/// which decides whether a build or a test may send it again by another route.
enum DemoDelivery: Equatable, Sendable {
    /// It reached the app, and only the screen tells whether the app acted on it.
    case sent
    /// Accessibility read its effect back: the scroll bar or the list's selection
    /// moved, though the elements on screen may read the same, as a text view's do.
    case confirmed
    /// It may or may not have acted: Accessibility timed out, or a page script failed
    /// after it had touched the page. Another route never sends it again.
    case uncertain
}

extension DemoKey {
    /// The page script does what this key does by default too: Tab and Shift-Tab
    /// move focus, Escape closes a modal dialog, Page Up and Page Down scroll. A
    /// script's arrow keys move no caret, change no menu or radio group, and
    /// scroll nothing, so arrows always need the real key.
    var pageScriptActsLikeTheKey: Bool {
        switch self {
        case .tab, .shiftTab, .escape, .pageUp, .pageDown: true
        case .up, .down, .left, .right: false
        }
    }

    /// Accessibility can do what this key does in an app's own views: Escape
    /// cancels, Up and Down move a list's selection, Page Up and Page Down
    /// scroll. Tab, Shift-Tab, Left, and Right have no stand-in, so they get the real key.
    var accessibilityActsLikeTheKey: Bool {
        switch self {
        case .escape, .up, .down, .pageUp, .pageDown: true
        case .tab, .shiftTab, .left, .right: false
        }
    }
}

/// The arithmetic behind Accessibility's stand-ins for arrow keys and scrolling.
enum DemoAccessibilityMotion {
    /// How much of a scroll area Page Up and Page Down move, as AppKit pages.
    static let pageFraction = 0.875

    /// The row Up or Down selects among `count` rows when `selected` are selected:
    /// the one above the first or below the last, or the first (Down) or last (Up)
    /// row with none selected. Nil when the selection is already at that end.
    static func row(after selected: [Int], count: Int, down: Bool) -> Int? {
        guard count > 0 else { return nil }
        let valid = selected.filter { (0..<count).contains($0) }
        guard let first = valid.min(), let last = valid.max() else { return down ? 0 : count - 1 }
        let next = down ? last + 1 : first - 1
        return (0..<count).contains(next) ? next : nil
    }

    /// The vertical scroll bar's value (0 at the top, 1 at the bottom) after moving the
    /// content by `points` (positive moves it up, as scrolling down does) in a scroll
    /// area `visible` points tall over content `content` points tall. Nil when there
    /// is nothing to scroll that way: content that fits, or a bar already at that edge.
    static func scrollValue(from value: Double, by points: Double, visible: Double, content: Double) -> Double? {
        let range = content - visible
        guard range >= 1, points != 0, value.isFinite, points.isFinite else { return nil }
        let current = min(max(value, 0), 1)
        let next = min(max(current + points / range, 0), 1)
        // Less than a point's movement reads as already at the edge.
        return abs(next - current) * range >= 1 ? next : nil
    }
}

/// A browser setting that would have kept a web step in the background, shown
/// once after a step had to borrow the screen for want of it.
struct DemoBrowserTip: Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        /// Allow JavaScript from Apple Events is off.
        case javaScript
        /// BetterMeets may not control the browser.
        case automation

        /// The setting that would have kept a step from borrowing the screen, given
        /// what the browser's scripting allowed it; nil when none would have.
        /// `needsJavaScript` says the step needed a page script, not just an address.
        static func missing(in access: DemoBrowserAccess, needsJavaScript: Bool) -> Kind? {
            guard access.scriptable else { return nil }
            if access.automation == .denied { return .automation }
            return needsJavaScript && access.javaScript == .off ? .javaScript : nil
        }
    }

    var kind: Kind
    var browser: String
    var bundleID: String

    /// The key under which this browser's tip of this kind is remembered as shown.
    var key: String { "\(bundleID)|\(kind.rawValue)" }

    var message: String {
        switch kind {
        case .javaScript:
            "\(browser) had to come forward for some steps. Turn on Allow JavaScript from Apple Events in "
                + "\(developerSettings) to keep it in the background."
        case .automation:
            "\(browser) had to come forward for some steps. Allow BetterMeets to control it in System Settings → "
                + "Privacy & Security → Automation to keep it in the background."
        }
    }

    /// Where the browser keeps Allow JavaScript from Apple Events.
    private var developerSettings: String {
        if bundleID.hasPrefix("com.google.Chrome") { return "View › Developer" }
        if bundleID.hasPrefix("com.apple.Safari") { return "Develop › Developer Settings" }
        return "its Developer menu"
    }
}
