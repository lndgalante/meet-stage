import Foundation

// MARK: - Label stability

enum LabelStability {
    static func normalize(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .lowercased()
    }

    /// The comparable form of a control's label: normalized, without a trailing
    /// count badge, so “Inbox 3” and “Inbox 4” stay the same control.
    static func matchKey(_ text: String) -> String {
        let normalized = normalize(text)
        guard
            let range = normalized.range(
                of: #"(\s+\d{1,3}|\s*\(\d{1,3}\)|\s*\[\d{1,3}\])$"#, options: .regularExpression),
            normalized[..<range.lowerBound].contains(where: \.isLetter)
        else { return normalized }
        return String(normalized[..<range.lowerBound])
    }

    /// Amounts, long numbers, percentages, times and handles. Checked after a
    /// trailing count badge is removed.
    private static let dataPattern =
        #"[$€£¥₿]|\d{2,}|\d\s?%|\d[\d,.]*\s?(k|m|bn|btc|eth|sol|usd|usdc|usdt|eur)\b|\b\d{1,2}[:/.\-]\d{1,2}\b|@"#

    /// Dates and relative times, checked on the whole label since “Mar 5” ends
    /// in what would otherwise look like a count badge.
    private static let datePattern =
        #"\b(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec|ene|abr|ago|dic)[a-z]*\.? \d{1,2}\b"#
        + #"|\b(today|yesterday|ago|am|pm|hoy|ayer|hace|aujourd'hui|hier|heute|gestern)\b"#

    /// Whether a label names UI rather than showing data. Data labels (amounts,
    /// dates, names in rows) change between runs, so they are never matched by text.
    static func isStable(roleClass: AXRoleClass, label: String) -> Bool {
        switch roleClass {
        case .row, .cell, .image: return false
        default: break
        }
        let text = matchKey(label)
        guard !text.isEmpty, text.count <= 48 else { return false }
        return text.range(of: dataPattern, options: [.regularExpression, .caseInsensitive]) == nil
            && normalize(label).range(of: datePattern, options: [.regularExpression, .caseInsensitive]) == nil
    }

    private static let generatedIdentifierPattern =
        #"^:r|^«r|^_r_|^_R_|[0-9a-f]{8,}|\d{3,}|^(radix|headlessui|mui|react-aria|ember|ext-gen)[-_]|^ember\d+$|^(mat|cdk)-[a-z-]+-\d+$"#

    static func isStableIdentifier(_ identifier: String) -> Bool {
        !identifier.isEmpty && identifier.count <= 64
            && identifier.range(of: generatedIdentifierPattern, options: [.regularExpression, .caseInsensitive]) == nil
    }
}

// MARK: - Matching

enum MatchResult: Equatable, Sendable {
    case unique(Int)
    case ambiguous
    case none

    var nodeID: Int? {
        if case .unique(let id) = self { id } else { nil }
    }
}

/// Resolves a recorded locator against a live snapshot with ordered rules and
/// no weights. A result is returned only when exactly one element qualifies.
enum DemoLocatorMatcher {
    /// How far, as a fraction of the window diagonal, a data element found by
    /// position may sit from where it was recorded. Farther means the list moved.
    static let positionTolerance = 0.35

    /// How close, in points, an element found by position must be to where it
    /// was recorded. Below half a typical row, so a shifted row never stands in.
    static let unlabeledControlTolerance = 18.0
    static let textTolerance = 14.0
    /// How far apart, in points, a position-matched target and its nearest
    /// look-alike must be when the target is recorded.
    static let minimumSeparation = 30.0

    /// Visual order identifies items only inside real lists and tables. Anywhere
    /// else (the whole page, a toolbar) an index shifts whenever content changes.
    static func ordersByIndex(_ container: ContainerKey?) -> Bool {
        guard let container else { return false }
        return ["AXTable", "AXList", "AXOutline", "AXGrid", "AXBrowser"].contains(container.role)
    }

    static func match(_ locator: DemoElementLocator, in snapshot: AXSnapshot) -> MatchResult {
        let roleClass = locator.roleClass
        let candidates = snapshot.nodes.filter { $0.roleClass == roleClass && !($0.isContainer && $0.roleClass != .group) }
        let label = LabelStability.matchKey(locator.label)

        // R1: a stable identifier names exactly one element, and agrees with its label.
        if let identifier = locator.identifier {
            let matches = candidates.filter { $0.identifier == identifier }
            if matches.count == 1, !locator.labelIsStable || LabelStability.matchKey(matches[0].label) == label {
                return .unique(matches[0].id)
            }
        }

        let container = locator.container
        if locator.labelIsStable {
            // R2: same role and text, scoped to the container when it still exists. A
            // control's own label outranks the same words borrowed by another control,
            // which demos saved before borrowing never saw.
            var matches = candidates.filter { LabelStability.matchKey($0.label) == label }
            if matches.contains(where: { !$0.labelIsBorrowed }) { matches.removeAll(where: \.labelIsBorrowed) }
            if let container {
                let scoped = matches.filter { snapshot.container(of: $0) == container }
                if !scoped.isEmpty { matches = scoped }
            }
            if matches.count == 1 { return .unique(matches[0].id) }
            if matches.isEmpty {
                // A caption or value whose words changed is still the text in that spot.
                // Another caption in that spot is a different field, never a stand-in.
                guard roleClass == .text else { return .none }
                let data = candidates.filter { !LabelStability.isStable(roleClass: .text, label: $0.label) }
                return nearestInPoints(scope(data, container, snapshot), to: locator.rect, within: textTolerance, in: snapshot)
            }
            if ordersByIndex(container), let visualIndex = locator.visualIndex, let container {
                let ordered = ordered(candidates.filter { snapshot.container(of: $0) == container }, in: snapshot)
                let byIndex = ordered.indices.contains(visualIndex) ? ordered[visualIndex] : nil
                if let byIndex, matches.contains(where: { $0.id == byIndex.id }) { return .unique(byIndex.id) }
            }
            return nearest(matches, to: locator.rect, within: 0.15, in: snapshot)
        }


        // R3: rows of a list or table are found by visual order, never by text.
        if ordersByIndex(container), let visualIndex = locator.visualIndex {
            let scoped = ordered(candidates.filter { snapshot.container(of: $0) == container }, in: snapshot)
            if !scoped.isEmpty {
                guard scoped.indices.contains(visualIndex) else { return .none }
                let found = scoped[visualIndex]
                return snapshot.distance(found.rect, locator.rect) < positionTolerance ? .unique(found.id) : .none
            }
        }
        // R4: anything else without a usable label (icon buttons, values) must
        // sit almost exactly where it was recorded, and be clearly the closest. A
        // recorded label that's empty never constrains the match, so an icon button
        // saved unlabelled is still found once it borrows a label.
        return nearestInPoints(
            scope(candidates, container, snapshot), to: locator.rect, within: positionTolerance(for: roleClass),
            in: snapshot)
    }

    static func positionTolerance(for roleClass: AXRoleClass) -> Double {
        roleClass.isInteractive ? unlabeledControlTolerance : textTolerance
    }

    /// Position-only matches stay inside the recorded container. When it is gone
    /// (a panel didn't open) the answer is "not found", never something nearby elsewhere.
    static func scope(_ nodes: [AXNode], _ container: ContainerKey?, _ snapshot: AXSnapshot) -> [AXNode] {
        guard let container else { return nodes }
        return nodes.filter { snapshot.container(of: $0) == container }
    }

    /// Whether this locator resolves by where it sits rather than by name or list position.
    static func isPositional(_ locator: DemoElementLocator) -> Bool {
        locator.identifier == nil && !locator.labelIsStable
            && !(ordersByIndex(locator.container) && locator.visualIndex != nil)
    }

    /// Reading order: elements grouped into visual rows (vertical centres within
    /// half the smaller height, in points), rows top to bottom, each left to right.
    static func ordered(_ nodes: [AXNode], in snapshot: AXSnapshot? = nil) -> [AXNode] {
        let height = max(snapshot?.windowFrame.height ?? 1_000, 1)
        let byY = nodes.sorted { ($0.rect.midY, $0.rect.x, $0.id) < ($1.rect.midY, $1.rect.x, $1.id) }
        var rows: [[AXNode]] = []
        for node in byY {
            if let anchor = rows.last?.first,
                abs(node.rect.midY - anchor.rect.midY) * height < min(node.rect.h, anchor.rect.h) * height / 2
            {
                rows[rows.count - 1].append(node)
            } else {
                rows.append([node])
            }
        }
        return rows.flatMap { $0.sorted { ($0.rect.x, $0.id) < ($1.rect.x, $1.id) } }
    }

    private static func nearestInPoints(
        _ nodes: [AXNode], to rect: NormRect, within limit: Double, in snapshot: AXSnapshot
    ) -> MatchResult {
        let ranked = nodes.map { ($0, snapshot.pointDistance($0.rect, rect)) }.sorted { $0.1 < $1.1 }
        guard let best = ranked.first, best.1 < limit else { return .none }
        if ranked.count > 1, best.1 >= ranked[1].1 * 0.5 { return .ambiguous }
        return .unique(best.0.id)
    }

    private static func nearest(
        _ nodes: [AXNode], to rect: NormRect, within limit: Double, in snapshot: AXSnapshot
    ) -> MatchResult {
        let ranked = nodes.map { ($0, snapshot.distance($0.rect, rect)) }.sorted { $0.1 < $1.1 }
        guard let best = ranked.first, best.1 < limit else { return .none }
        if ranked.count > 1, best.1 >= ranked[1].1 * 0.5 { return .ambiguous }
        return .unique(best.0.id)
    }
}

// MARK: - Capture

enum DemoLocatorFactory {
    /// Builds a locator for `nodeID` and proves it finds the same element in the
    /// snapshot it came from. Returns nil when no unique description exists.
    static func locator(for nodeID: Int, in snapshot: AXSnapshot) -> DemoElementLocator? {
        guard let node = snapshot.node(nodeID), node.rect.isUsable else { return nil }
        if let locator = locator(for: node, named: true, in: snapshot) { return locator }
        // A borrowed label another control owns can't find this one; its position still may.
        return node.labelIsBorrowed ? locator(for: node, named: false, in: snapshot) : nil
    }

    private static func locator(for node: AXNode, named: Bool, in snapshot: AXSnapshot) -> DemoElementLocator? {
        let stable = named && LabelStability.isStable(roleClass: node.roleClass, label: node.label)
        let identifier = node.identifier.flatMap { LabelStability.isStableIdentifier($0) ? $0 : nil }
        let container = snapshot.container(of: node)
        let indexed = DemoLocatorMatcher.ordersByIndex(container)
        var locator = DemoElementLocator(
            role: node.role, subrole: node.subrole, identifier: identifier, label: stable ? node.label : "",
            labelIsStable: stable, container: container,
            visualIndex: !stable && indexed ? visualIndex(of: node, in: snapshot) : nil, rect: node.rect)
        if DemoLocatorMatcher.match(locator, in: snapshot) == .unique(node.id) {
            // Found by position: a look-alike close by would make replay guess.
            if DemoLocatorMatcher.isPositional(locator), !isWellSeparated(node, locator: locator, in: snapshot) {
                return nil
            }
            return locator
        }
        guard indexed else { return nil }
        locator.visualIndex = visualIndex(of: node, in: snapshot)
        if locator.visualIndex != nil, DemoLocatorMatcher.match(locator, in: snapshot) == .unique(node.id) {
            return locator
        }
        return nil
    }

    private static func isWellSeparated(_ node: AXNode, locator: DemoElementLocator, in snapshot: AXSnapshot) -> Bool {
        let peers = DemoLocatorMatcher.scope(
            snapshot.nodes.filter { $0.roleClass == node.roleClass && $0.id != node.id }, locator.container, snapshot)
        let closest = peers.map { snapshot.pointDistance($0.rect, node.rect) }.min() ?? .infinity
        return closest >= DemoLocatorMatcher.minimumSeparation
    }

    static func visualIndex(of node: AXNode, in snapshot: AXSnapshot) -> Int? {
        guard let container = snapshot.container(of: node) else { return nil }
        let peers = DemoLocatorMatcher.ordered(
            snapshot.nodes.filter {
                $0.roleClass == node.roleClass && snapshot.container(of: $0) == container
                    && !($0.isContainer && $0.roleClass != .group)
            }, in: snapshot)
        return peers.firstIndex { $0.id == node.id }
    }

    /// Identity used to compare recorded actions. It includes a coarse position so
    /// two same-labelled switches in different rows never count as one.
    static func identity(_ locator: DemoElementLocator) -> String {
        [
            locator.role, locator.subrole ?? "", locator.identifier ?? "", LabelStability.matchKey(locator.label),
            locator.container.map { "\($0.role)/\($0.label)" } ?? "", locator.visualIndex.map(String.init) ?? "",
            String(format: "%.0f,%.0f", locator.rect.midX * 50, locator.rect.midY * 50),
        ].joined(separator: "|")
    }
}

// MARK: - Screen signatures

enum ScreenSignatures {
    static func make(_ snapshot: AXSnapshot) -> ScreenSignature {
        let visible = DemoLocatorMatcher.ordered(snapshot.nodes.filter(\.isVisible))
        // Borrowed labels are left out, so screens still match demos saved before borrowing.
        let selected = visible.filter { node in
            node.isSelected && !node.labelIsBorrowed
                && [.tab, .link, .radio, .menuItem, .button, .row].contains(node.roleClass)
                && LabelStability.isStable(roleClass: node.roleClass, label: node.label)
        }
        let headings = visible.filter { node in
            node.roleClass == .heading && LabelStability.isStable(roleClass: .heading, label: node.label)
        }
        return ScreenSignature(
            urlKey: urlKey(snapshot.webURL),
            selected: Array(unique(selected.map { LabelStability.matchKey($0.label) }).prefix(4)),
            headings: Array(unique(headings.map { LabelStability.matchKey($0.label) }).prefix(3)),
            dialogOpen: snapshot.dialogOpen)
    }

    static func urlKey(_ url: URL?) -> String? {
        guard let url, let scheme = url.scheme?.lowercased() else { return nil }
        if scheme == "file" || scheme == "app" {
            let route =
                url.fragment?.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first
                .map(String.init) ?? ""
            return route.isEmpty ? nil : "#" + route
        }
        guard ["http", "https"].contains(scheme), let host = url.host?.lowercased() else { return nil }
        var path = url.path
        if path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return "\(host)\(path.isEmpty ? "/" : path)"
    }

    /// The URL must agree whenever it was recorded. The rest of the signature is
    /// only enforced once a verification run has confirmed it. Headings can sit
    /// below the fold, so callers skip them until they have tried scrolling.
    static func matches(
        _ recorded: ScreenSignature, live: ScreenSignature, includeHeadings: Bool = true, strict: Bool = false
    ) -> Bool {
        if let url = recorded.urlKey, url != live.urlKey { return false }
        guard recorded.confirmed else {
            // Strict (the start of a demo): the selected navigation item is reliable
            // even before a check confirms the rest, and tells Home from Transactions.
            return !strict || Set(recorded.selected).isSubset(of: Set(live.selected))
        }
        guard Set(recorded.selected).isSubset(of: Set(live.selected)), recorded.dialogOpen == live.dialogOpen
        else { return false }
        return !includeHeadings || recorded.headings.isEmpty
            || !Set(recorded.headings).isDisjoint(with: Set(live.headings))
    }

    /// Keeps only the evidence that held in both the scouting and checking runs.
    static func confirm(_ recorded: ScreenSignature, with live: ScreenSignature) -> ScreenSignature {
        ScreenSignature(
            urlKey: recorded.urlKey == live.urlKey ? recorded.urlKey : nil,
            selected: recorded.selected.filter(live.selected.contains),
            headings: recorded.headings.filter(live.headings.contains),
            dialogOpen: live.dialogOpen, confirmed: true)
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}

// MARK: - Compaction

/// Turns the scout's raw records into replayable steps: drops rejected and
/// unobserved actions, retries, repeated clicks, and toggles undone with
/// nothing shown in between, and turns scrolls into reveal hints. Pruning also
/// cuts lone clicks that showed nothing and detours that came back to the screen
/// they left. Scrolling a dropped step's framing did is carried to the next step
/// on that page. Records never change, so a draft compiles again without pruning.
enum ScoutCompaction {
    /// `cited` holds the turns Claude's finish said show a beat, which pruning never
    /// cuts: Claude saw the screenshot, and a sort or a changed number shows there
    /// though the screen's digest reads the same.
    static func compact(_ records: [ScoutRecord], pruning: Bool = true, keeping cited: Set<Int> = []) -> [DemoStep] {
        steps(from: records, kept: kept(records, pruning: pruning, keeping: cited))
    }

    /// A draft's steps, keeping the turns its finish cited.
    static func compact(_ draft: ScoutDraft, pruning: Bool = true) -> [DemoStep] {
        compact(draft.records, pruning: pruning, keeping: draft.citedTurns)
    }

    /// The indices of the records the demo keeps, in order.
    static func kept(_ records: [ScoutRecord], pruning: Bool = true, keeping cited: Set<Int> = []) -> [Int] {
        var kept = records.indices.filter { index in
            let outcome = records[index].outcome
            return outcome != .rejected && outcome != .unobserved && outcome != .pending
        }

        // An action that changed nothing and was then retried on the same element: keep the retry.
        var index = 0
        while index < kept.count {
            if let current = mutatingKey(records[kept[index]]), records[kept[index]].outcome == .noEffect,
                let nextIndex = kept[(index + 1)...].firstIndex(where: { mutatingKey(records[$0]) != nil }),
                mutatingKey(records[kept[nextIndex]]) == current
            {
                kept.remove(at: index)
                continue
            }
            index += 1
        }

        // A toggle switched on and back off with nothing shown in between.
        index = 0
        while index < kept.count {
            if let key = toggleKey(records[kept[index]]),
                let nextIndex = kept[(index + 1)...].firstIndex(where: { mutatingKey(records[$0]) != nil }),
                toggleKey(records[kept[nextIndex]]) == key,
                !kept[(index + 1)..<nextIndex].contains(where: { records[$0].steps.contains { !$0.action.isMutating } })
            {
                kept.removeSubrange(index...nextIndex)
                continue
            }
            index += 1
        }

        guard pruning else { return kept }
        // A click that showed nothing and wasn't tried again would show nothing live either.
        kept.removeAll { isSilentClick(records[$0]) && !cited.contains(records[$0].turn) }
        return withoutDetours(kept, in: records, keeping: cited)
    }

    /// The steps the records at `kept` make, in order.
    static func steps(from records: [ScoutRecord], kept: [Int]) -> [DemoStep] {
        let keptSet = Set(kept)
        var steps: [DemoStep] = []
        var pendingReveal: RevealHint?
        var owed: (page: String?, amount: Double)?
        for (offset, record) in records.enumerated() {
            guard keptSet.contains(offset) else {
                for step in record.steps {
                    guard let framing = step.framing, framing != 0 else { continue }
                    let earlier = owed?.page == step.pre.urlKey ? owed?.amount ?? 0 : 0
                    owed = (step.pre.urlKey, earlier + framing)
                }
                continue
            }
            if var scroll = record.scroll {
                if let pending = pendingReveal, pending.directionDown == scroll.directionDown {
                    scroll.count = (pending.count ?? 1) + (scroll.count ?? 1)
                    scroll.route = scroll.route ?? pending.route
                }
                pendingReveal = scroll
                continue
            }
            for var step in record.steps {
                if let reveal = pendingReveal {
                    step.reveal = reveal
                    pendingReveal = nil
                }
                if let debt = owed {
                    if debt.page == step.pre.urlKey { step.priorFraming = (step.priorFraming ?? 0) + debt.amount }
                    owed = nil
                }
                if step.action.isMutating {
                    step.changedScreen =
                        switch record.outcome {
                        case .changed: true
                        case .noEffect: false
                        default: nil
                        }
                }
                steps.append(step)
            }
        }
        return Array(steps.prefix(RealTimeDemo.maximumSteps))
    }

    /// Cuts every detour: steps i..<j when step j began on the screen step i did,
    /// each of them a click on a tab, link, button or menu item that changed the
    /// screen, with nothing highlighted, scrolled, typed, toggled or approved between.
    /// The same screen is the same visible content and address (`ScoutRecord.screen`).
    /// When Claude called one of those clicks a wrong turn, the same screen
    /// signature counts too, given an address or a selected item to go by; the
    /// verdict never cuts anything on its own.
    private static func withoutDetours(_ kept: [Int], in records: [ScoutRecord], keeping cited: Set<Int>) -> [Int] {
        var kept = kept
        var start = 0
        while start < kept.count {
            var end: Int?
            var wrongTurn = false
            var index = start
            while index < kept.count, isDetourStep(records[kept[index]], cited: cited) {
                wrongTurn = wrongTurn || records[kept[index]].judgement?.verdict == .wrongTurn
                index += 1
                if index < kept.count, sameScreen(records[kept[start]], records[kept[index]], wrongTurn: wrongTurn) {
                    end = index
                }
            }
            if let end {
                kept.removeSubrange(start..<end)
            } else {
                start += 1
            }
        }
        return kept
    }

    /// A click a detour may be made of. One that scrolled its target into view moved
    /// the page, which the screens around it can't vouch for, so it stays.
    private static func isDetourStep(_ record: ScoutRecord, cited: Set<Int>) -> Bool {
        guard record.outcome == .changed, record.steps.count == 1, !cited.contains(record.turn),
            let step = record.steps.first, case .click(let locator) = step.action, !step.approved,
            [.tab, .link, .button, .menuItem].contains(locator.roleClass), !locator.isToggleLike
        else { return false }
        return (step.framing ?? 0) == 0
    }

    private static func sameScreen(_ first: ScoutRecord, _ later: ScoutRecord, wrongTurn: Bool) -> Bool {
        if let screen = first.screen, screen == later.screen { return true }
        guard wrongTurn, let before = first.steps.first?.pre, let after = later.steps.first?.pre else { return false }
        return before == after && (before.urlKey != nil || !before.selected.isEmpty)
    }

    private static func isSilentClick(_ record: ScoutRecord) -> Bool {
        guard record.outcome == .noEffect, record.steps.count == 1, case .click = record.steps[0].action else {
            return false
        }
        return true
    }

    private static func mutatingKey(_ record: ScoutRecord) -> String? {
        guard record.steps.count == 1, let step = record.steps.first, step.action.isMutating else { return nil }
        switch step.action {
        case .click(let locator): return "click|" + DemoLocatorFactory.identity(locator)
        case .typeText(let field, let text, let submit):
            return "type|\(DemoLocatorFactory.identity(field))|\(text)|\(submit)"
        case .press(let key): return "press|\(key.rawValue)"
        case .navigate(let url): return "open|\(url.absoluteString)"
        case .present: return nil
        }
    }

    private static func toggleKey(_ record: ScoutRecord) -> String? {
        guard case .click(let locator) = record.steps.first?.action, locator.roleClass == .checkbox,
            record.outcome == .changed
        else { return nil }
        return DemoLocatorFactory.identity(locator)
    }
}
