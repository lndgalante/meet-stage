import CoreGraphics
import Foundation

// MARK: - Roles

enum AXRoleClass: String, Codable, Sendable {
    case button, link, tab, radio, checkbox, menuItem, field
    case row, cell, heading, text, image, group
    case container, webArea, scrollArea, other

    init(role: String, subrole: String?) {
        switch role {
        case "AXButton", "AXMenuButton", "AXPopUpButton", "AXDisclosureTriangle", "AXToolbarButton":
            self = .button
        case "AXRadioButton": self = subrole == "AXTabButton" ? .tab : .radio
        case "AXCheckBox", "AXSwitch", "AXToggle": self = .checkbox
        case "AXLink": self = .link
        case "AXTab": self = .tab
        case "AXMenuItem", "AXMenuBarItem": self = .menuItem
        case "AXTextField", "AXTextArea", "AXComboBox", "AXSearchField", "AXSecureTextField": self = .field
        case "AXRow": self = .row
        case "AXCell", "AXColumnHeader": self = .cell
        case "AXHeading": self = .heading
        case "AXStaticText": self = .text
        case "AXImage": self = .image
        case "AXGroup", "AXSplitGroup", "AXRadioGroup": self = .group
        case "AXTable", "AXList", "AXOutline", "AXTabGroup", "AXGrid", "AXBrowser", "AXSheet", "AXDialog":
            self = .container
        case "AXWebArea": self = .webArea
        case "AXScrollArea": self = .scrollArea
        default: self = .other
        }
    }

    var isInteractive: Bool {
        switch self {
        case .button, .link, .tab, .radio, .checkbox, .menuItem, .field: true
        default: false
        }
    }

    var abbreviation: String {
        switch self {
        case .button: "btn"
        case .link: "link"
        case .tab: "tab"
        case .radio: "radio"
        case .checkbox: "chk"
        case .menuItem: "menu"
        case .field: "field"
        case .row: "row"
        case .cell: "cell"
        case .heading: "h"
        case .text: "text"
        case .image: "img"
        case .group: "group"
        case .container: "list"
        case .webArea: "web"
        case .scrollArea: "scroll"
        case .other: "other"
        }
    }

    var noun: String {
        switch self {
        case .button: "button"
        case .link: "link"
        case .tab: "tab"
        case .radio: "option"
        case .checkbox: "switch"
        case .menuItem: "menu item"
        case .field: "field"
        case .row: "row"
        case .cell: "cell"
        case .heading: "heading"
        case .text: "text"
        case .image: "image"
        case .group, .container, .webArea, .scrollArea, .other: "section"
        }
    }
}

// MARK: - Raw nodes

/// Attributes read from one Accessibility element in a single batched call.
struct AXRawNode: Sendable {
    var role = ""
    var subrole: String?
    var title: String?
    var description: String?
    var stringValue: String?
    var numberValue: Double?
    /// Global frame, top-left origin.
    var frame: CGRect?
    var enabled = true
    var identifier: String?
    var selected = false
    var focused = false
    var placeholder: String?
    var help: String?
    var url: String?
    var loaded: Bool?
    var loadingProgress: Double?
    var busy = false
}

/// A tree of Accessibility elements. The live implementation talks to another
/// process; tests supply recorded fixtures.
protocol AXNodeSource {
    associatedtype Handle: Hashable
    func read(_ handle: Handle) -> (node: AXRawNode, children: [Handle])?
}

// MARK: - Snapshot

struct AXNode: Sendable, Hashable, Identifiable {
    let id: Int
    let role: String
    let subrole: String?
    let roleClass: AXRoleClass
    var label: String
    let identifier: String?
    let placeholder: String?
    let help: String?
    let rect: NormRect
    let isVisible: Bool
    let isSelected: Bool
    let isFocused: Bool
    let isEnabled: Bool
    let isSecure: Bool
    /// Length of a field's text. The text itself is never kept.
    let textLength: Int?
    let toggleValue: Bool?
    let containerID: Int?
    let isContainer: Bool
    let inWebArea: Bool
    let url: String?
    /// Inside an open dialog, sheet or alert.
    var inDialog = false
    /// Nearest clickable ancestor, for text or images inside a link or button.
    var interactiveAncestorID: Int?
}

struct WebContentState: Sendable, Equatable {
    var hasChildren: Bool
    var loaded: Bool?
    var progress: Double?
    var busy: Bool

    var isReady: Bool {
        hasChildren && loaded != false && (progress ?? 1) >= 0.999 && !busy
    }
}

struct AXSnapshot: Sendable {
    let generation: Int
    /// Global window frame, top-left origin.
    let windowFrame: CGRect
    let nodes: [AXNode]
    let webURL: URL?
    let dialogOpen: Bool
    /// nil when the window has no web content.
    let webContent: WebContentState?

    var focusedID: Int? { nodes.first { $0.isFocused && $0.roleClass != .webArea }?.id }

    func node(_ id: Int) -> AXNode? {
        nodes.indices.contains(id) && nodes[id].id == id ? nodes[id] : nodes.first { $0.id == id }
    }

    func container(of node: AXNode) -> ContainerKey? {
        guard let id = node.containerID, let container = self.node(id) else { return nil }
        return Self.key(for: container)
    }

    /// Web-area titles and data labels change between runs, so they never identify a container.
    static func key(for container: AXNode) -> ContainerKey {
        let stable =
            container.roleClass != .webArea
            && LabelStability.isStable(roleClass: container.roleClass, label: container.label)
        return ContainerKey(
            role: container.role, subrole: container.subrole,
            label: stable ? LabelStability.matchKey(container.label) : "")
    }

    func containerNode(of node: AXNode) -> AXNode? {
        node.containerID.flatMap { self.node($0) }
    }

    /// Diagonal-relative distance between two normalized rects, in window points.
    /// Distance between two rect centres in window points.
    func pointDistance(_ a: NormRect, _ b: NormRect) -> Double {
        hypot((a.midX - b.midX) * windowFrame.width, (a.midY - b.midY) * windowFrame.height)
    }

    func distance(_ a: NormRect, _ b: NormRect) -> Double {
        let width = max(windowFrame.width, 1)
        let height = max(windowFrame.height, 1)
        return hypot((a.midX - b.midX) * width, (a.midY - b.midY) * height) / hypot(width, height)
    }

    /// A stable fingerprint of what is visibly on screen. Leaves out numbers so
    /// tickers and timestamps don't keep a screen from settling.
    var digest: Int {
        var hasher = Hasher()
        var parts: [String] = []
        for node in nodes where node.isVisible && !node.isContainer {
            if node.roleClass == .text, node.label.contains(where: \.isNumber) { continue }
            parts.append("\(node.roleClass.rawValue)|\(LabelStability.normalize(node.label))|\(node.isSelected)")
            if let toggle = node.toggleValue { parts.append("toggle|\(node.label)|\(toggle)") }
        }
        parts.sort()
        parts.forEach { hasher.combine($0) }
        hasher.combine(dialogOpen)
        hasher.combine(webURL?.absoluteString)
        return hasher.finalize()
    }

}

// MARK: - Builder

/// Walks a window's Accessibility tree into an `AXSnapshot`.
///
/// Web content is walked after a capped pass over the window chrome, so a
/// browser's toolbar and sidebars can't spend the element budget before the
/// page. Rows, cells, headings and unlabelled links get labels synthesized from
/// their descendant text. Field values never become labels.
struct AXSnapshotBuilder<Source: AXNodeSource> {
    struct Limits {
        var nodeBudget = 8_000
        var chromeNodeBudget = 2_400
        var maxKept = 1_000
        var maxDepth = 45
    }

    let source: Source
    let window: Source.Handle
    let windowFrame: CGRect
    var limits = Limits()
    var isExpired: () -> Bool = { false }

    private var nodes: [AXNode] = []
    private var handles: [Source.Handle] = []
    private var budget = 0
    private var offWindowKept = 0
    private var deferredWebAreas: [(handle: Source.Handle, frame: CGRect, context: Context)] = []
    private var webURL: URL?
    private var webContent: WebContentState?
    private var dialogOpen = false

    /// What a node inherits from its ancestors.
    private struct Context {
        var containerID: Int?
        var clip: CGRect
        var inWebArea = false
        var inDialog = false
        var interactiveAncestor: Int?
    }

    init(source: Source, window: Source.Handle, windowFrame: CGRect) {
        self.source = source
        self.window = window
        self.windowFrame = windowFrame
    }

    mutating func build(generation: Int) -> (snapshot: AXSnapshot, handles: [Source.Handle]) {
        walkWindow(budget: limits.chromeNodeBudget)
        if deferredWebAreas.isEmpty, budget == 0 {
            // A native window: the whole budget belongs to its controls.
            walkWindow(budget: limits.nodeBudget)
        }

        budget = max(0, limits.nodeBudget - (limits.chromeNodeBudget - budget))
        let areas = deferredWebAreas.sorted { area($0.frame) > area($1.frame) }
        for (index, webArea) in areas.enumerated() {
            let state = source.read(webArea.handle)
            if index == 0 {
                webURL = state?.node.url.flatMap(URL.init(string:))
                webContent = WebContentState(
                    hasChildren: !(state?.children.isEmpty ?? true), loaded: state?.node.loaded,
                    progress: state?.node.loadingProgress, busy: state?.node.busy ?? false)
            }
            var context = webArea.context
            context.inWebArea = true
            for child in state?.children ?? [] {
                _ = walk(child, depth: 1, context: context, deferWebAreas: false)
            }
        }
        let snapshot = AXSnapshot(
            generation: generation, windowFrame: windowFrame, nodes: nodes, webURL: webURL, dialogOpen: dialogOpen,
            webContent: webContent)
        return (snapshot, handles)
    }

    private mutating func walkWindow(budget: Int) {
        nodes = []
        handles = []
        deferredWebAreas = []
        offWindowKept = 0
        dialogOpen = false
        self.budget = budget
        _ = walk(window, depth: 0, context: Context(clip: windowFrame), deferWebAreas: true)
    }

    private func area(_ rect: CGRect) -> CGFloat {
        let visible = rect.intersection(windowFrame)
        return visible.isNull ? 0 : visible.width * visible.height
    }

    /// Returns descendant text fragments with their depth below this node.
    private mutating func walk(
        _ handle: Source.Handle, depth: Int, context: Context, deferWebAreas: Bool
    ) -> [(text: String, depth: Int)] {
        guard depth < limits.maxDepth, budget > 0, nodes.count < limits.maxKept, !isExpired() else { return [] }
        budget -= 1
        guard let (raw, children) = source.read(handle) else { return [] }

        // Skip subtrees far outside the window. Keep a little above the fold and
        // more below it, where reveals and "scroll down" look next.
        let reach = CGRect(
            x: windowFrame.minX, y: windowFrame.minY - windowFrame.height * 0.5,
            width: windowFrame.width, height: windowFrame.height * 3.5)
        if let frame = raw.frame, frame.width > 0, frame.height > 0, !frame.intersects(reach),
            raw.role != "AXWindow"
        {
            return []
        }

        let roleClass = AXRoleClass(role: raw.role, subrole: raw.subrole)
        let isDialog = raw.role == "AXSheet" || raw.role == "AXDialog" || raw.subrole?.contains("Dialog") == true
        if isDialog { dialogOpen = true }

        if roleClass == .webArea, deferWebAreas, let frame = raw.frame, area(frame) > 0 {
            let id = keep(raw, roleClass: roleClass, handle: handle, context: context, inWebArea: true)
            var deferred = context
            deferred.containerID = id ?? context.containerID
            deferred.clip = context.clip.intersection(frame)
            deferredWebAreas.append((handle, frame, deferred))
            return []
        }

        let id = keep(raw, roleClass: roleClass, handle: handle, context: context, inWebArea: context.inWebArea)
        var childContext = context
        if let id, nodes[id].isContainer { childContext.containerID = id }
        if let id, roleClass.isInteractive { childContext.interactiveAncestor = id }
        if isDialog { childContext.inDialog = true }
        if roleClass == .scrollArea, let frame = raw.frame { childContext.clip = context.clip.intersection(frame) }

        var fragments: [(text: String, depth: Int)] = []
        for child in children {
            guard budget > 0, nodes.count < limits.maxKept else { break }
            let childFragments = walk(child, depth: depth + 1, context: childContext, deferWebAreas: deferWebAreas)
            for fragment in childFragments where fragment.depth < 3 && fragments.count < 12 {
                fragments.append((fragment.text, fragment.depth + 1))
            }
        }

        if let id, nodes[id].label.isEmpty, Self.synthesizesLabel(roleClass) {
            var label = ""
            for fragment in fragments {
                let text = fragment.text
                let next = label.isEmpty ? text : "\(label) · \(text)"
                if next.count > 80 { break }
                label = next
            }
            nodes[id].label = label
        }

        if roleClass == .text, let text = Self.clean(raw.stringValue ?? raw.title), !text.isEmpty {
            return [(text, 0)] + fragments
        }
        if Self.synthesizesLabel(roleClass) || roleClass.isInteractive, let id, !nodes[id].label.isEmpty {
            // A labelled child contributes its label once instead of its whole subtree.
            return [(nodes[id].label, 0)]
        }
        return fragments
    }

    private static func synthesizesLabel(_ roleClass: AXRoleClass) -> Bool {
        switch roleClass {
        case .row, .cell, .heading, .link, .button, .tab, .menuItem, .radio: true
        default: false
        }
    }

    /// Appends a node when it is useful to the model or as a container. Returns its ID.
    private mutating func keep(
        _ raw: AXRawNode, roleClass: AXRoleClass, handle: Source.Handle, context: Context, inWebArea: Bool
    ) -> Int? {
        guard let frame = raw.frame, frame.width > 0, frame.height > 0, windowFrame.width > 0,
            windowFrame.height > 0
        else { return nil }
        let isSecure = raw.subrole == "AXSecureTextField" || raw.role == "AXSecureTextField"
        let isField = roleClass == .field
        var label: String
        if isField {
            label = Self.clean(raw.title) ?? Self.clean(raw.description) ?? Self.clean(raw.placeholder) ?? ""
        } else if roleClass == .text {
            label = Self.clean(raw.stringValue ?? raw.title) ?? ""
        } else {
            label = Self.clean(raw.title) ?? Self.clean(raw.description) ?? ""
            if label.isEmpty, roleClass == .image || roleClass == .heading, let help = Self.clean(raw.help) {
                label = help
            }
        }
        if label.count > 256 { label = String(label.prefix(256)) }

        let isLandmark = raw.subrole?.hasPrefix("AXLandmark") == true
        let isContainer =
            roleClass == .container || roleClass == .webArea || isLandmark
            || (roleClass == .group && !label.isEmpty)
        let isUseful: Bool =
            switch roleClass {
            case .button, .link, .tab, .radio, .checkbox, .menuItem, .field, .row, .cell, .heading: true
            case .text: !label.isEmpty && label.count <= 80
            case .image: !label.isEmpty
            case .group: !label.isEmpty
            default: false
            }
        guard isUseful || isContainer else { return nil }

        let rect = NormRect(
            x: (frame.minX - windowFrame.minX) / windowFrame.width,
            y: (frame.minY - windowFrame.minY) / windowFrame.height,
            w: frame.width / windowFrame.width, h: frame.height / windowFrame.height)
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let clip = context.clip
        // The root clip is the window, so a null clip always means fully scrolled away.
        let visible = windowFrame.contains(center) && !clip.isNull && clip.insetBy(dx: -1, dy: -1).contains(center)
        if !windowFrame.intersects(frame) {
            // Off-window content helps reveals but must never crowd out what's visible.
            guard offWindowKept < 300 else { return nil }
            offWindowKept += 1
        }
        let toggle: Bool? = roleClass == .checkbox ? raw.numberValue.map { $0 != 0 } : nil
        let id = nodes.count
        nodes.append(
            AXNode(
                id: id, role: raw.role, subrole: raw.subrole, roleClass: roleClass, label: label,
                identifier: Self.clean(raw.identifier), placeholder: isField ? Self.clean(raw.placeholder) : nil,
                help: Self.clean(raw.help).map { String($0.prefix(120)) }, rect: rect, isVisible: visible,
                isSelected: raw.selected, isFocused: raw.focused, isEnabled: raw.enabled, isSecure: isSecure,
                textLength: isField && !isSecure ? (raw.stringValue?.count ?? 0) : nil, toggleValue: toggle,
                containerID: context.containerID, isContainer: isContainer,
                inWebArea: inWebArea, url: roleClass == .link || roleClass == .webArea ? raw.url : nil,
                inDialog: context.inDialog, interactiveAncestorID: context.interactiveAncestor))
        handles.append(handle)
        return id
    }

    private static func clean(_ text: String?) -> String? {
        guard let text else { return nil }
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }
}

// MARK: - Model encoding

/// Encodes the visible part of a snapshot as compact lines for the model:
/// `id role "label" x,y,w,h [flags] [in:id]` with integer 0–999 coordinates.
enum DemoSceneEncoder {
    static let maximumLines = 200

    static func encode(_ snapshot: AXSnapshot) -> (text: String, listed: Set<Int>) {
        let candidates = snapshot.nodes.filter { node in
            node.isVisible && (!node.isContainer || node.roleClass == .group) && node.rect.isUsable
                && (!node.label.isEmpty || node.roleClass.isInteractive)
        }
        let ranked = candidates.sorted { a, b in
            let ra = rank(a)
            let rb = rank(b)
            if ra != rb { return ra < rb }
            if a.inWebArea != b.inWebArea { return a.inWebArea }
            if abs(a.rect.y - b.rect.y) > 0.005 { return a.rect.y < b.rect.y }
            return a.rect.x < b.rect.x
        }
        let chosen = Array(ranked.prefix(maximumLines))
        var listed = Set(chosen.map(\.id))
        var containers: [Int] = []
        for node in chosen {
            if let id = node.containerID, !listed.contains(id), let container = snapshot.node(id),
                container.roleClass != .webArea
            {
                listed.insert(id)
                containers.append(id)
            }
        }
        let ordered = (containers.compactMap { snapshot.node($0) } + chosen).sorted { a, b in
            if abs(a.rect.y - b.rect.y) > 0.005 { return a.rect.y < b.rect.y }
            return a.rect.x < b.rect.x
        }
        let lines = ordered.map { line(for: $0, in: snapshot, listed: listed) }
        return (lines.joined(separator: "\n"), listed)
    }

    private static func rank(_ node: AXNode) -> Int {
        if node.roleClass.isInteractive { return 0 }
        switch node.roleClass {
        case .heading: return 1
        case .row: return 2
        case .cell: return 3
        case .image, .group: return 4
        default: return 5
        }
    }

    static func line(for node: AXNode, in snapshot: AXSnapshot, listed: Set<Int>) -> String {
        func scaled(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 999).rounded()) }
        let r = node.rect.clampedToWindow
        var label = node.label.replacingOccurrences(of: "\"", with: "'")
        if label.count > 80 { label = String(label.prefix(79)) + "…" }
        var flags: [String] = []
        if node.isSelected { flags.append("sel") }
        if node.isFocused { flags.append("foc") }
        if !node.isEnabled { flags.append("disabled") }
        if node.isSecure { flags.append("secure") }
        if let length = node.textLength, length > 0 { flags.append("has-text(\(length))") }
        if let toggle = node.toggleValue { flags.append(toggle ? "on" : "off") }
        if node.isContainer, node.roleClass != .group { flags.append("container") }
        var text = "\(node.id) \(node.roleClass.abbreviation) \"\(label)\" \(scaled(r.x)),\(scaled(r.y)),\(scaled(r.w)),\(scaled(r.h))"
        if !flags.isEmpty { text += " [\(flags.joined(separator: " "))]" }
        if let container = node.containerID, listed.contains(container) { text += " in:\(container)" }
        return text
    }
}
