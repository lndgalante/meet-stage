import Foundation

/// What an action visibly did, read by comparing the look before it with the one it
/// settled on, for the fact Claude reads next turn (`#3 clicked … → expected: … /
/// observed: …`). Built only from the two snapshots the scout already took, so it
/// costs no Accessibility read. Labels and titles in it are window content, which
/// the request sends inside `<untrusted_window_content>`. The fact is stored with
/// the demo, so it quotes only labels that name UI (`LabelStability.isStable`):
/// a row, and anything reading as data, is named by its place or not at all.
enum ScoutObservation {
    /// The summary is one line of at most this many characters, cut between clauses.
    static let maximumLength = 200

    static func summary(from before: AXSnapshot, to after: AXSnapshot) -> String {
        let parts =
            pageChange(before, after) + dialogChanges(before, after) + selectionChanges(before, after)
            + switchChanges(before, after) + headingChanges(before, after) + focusChange(before, after)
            + countChange(before, after)
        if parts.isEmpty { return "the screen changed in place" }
        let line = parts.joined(separator: "; ")
        guard line.count > maximumLength else { return line }
        let more = "; …"
        var kept = parts
        while kept.count > 1, kept.joined(separator: "; ").count + more.count > maximumLength { kept.removeLast() }
        let head = kept.joined(separator: "; ")
        return head.count + more.count > maximumLength ? String(head.prefix(maximumLength - 1)) + "…" : head + more
    }

    private static func pageChange(_ before: AXSnapshot, _ after: AXSnapshot) -> [String] {
        let page = ScreenSignatures.urlKey(after.webURL)
        guard page != ScreenSignatures.urlKey(before.webURL) else { return [] }
        guard let page else { return ["page changed"] }
        return ["page " + (page.count > 80 ? String(page.prefix(79)) + "…" : page)]
    }

    private static func dialogChanges(_ before: AXSnapshot, _ after: AXSnapshot) -> [String] {
        let wasOpen = dialogTitles(in: before)
        let nowOpen = dialogTitles(in: after)
        func named(_ title: String) -> String {
            LabelStability.isStable(roleClass: .container, label: title) ? "dialog \(quoted(title))" : "dialog"
        }
        return extra(in: nowOpen, over: wasOpen).map { "\(named($0)) opened" }
            + extra(in: wasOpen, over: nowOpen).map { "\(named($0)) closed" }
    }

    /// The selected tab, option or row, from what to what: by its label when that
    /// names UI, else by its place among those showing, as a row always is.
    private static func selectionChanges(_ before: AXSnapshot, _ after: AXSnapshot) -> [String] {
        [AXRoleClass.tab, .radio, .row].compactMap { roleClass in
            let noun = roleClass.noun
            func named(_ item: (label: String, place: Int), leading: Bool) -> String {
                guard LabelStability.isStable(roleClass: roleClass, label: item.label) else {
                    return "\(noun) \(item.place)"
                }
                return leading ? "\(noun) \(quoted(item.label))" : quoted(item.label)
            }
            return switch (selected(roleClass, in: before), selected(roleClass, in: after)) {
            case (let from?, let to?) where from.label != to.label:
                "\(named(from, leading: true)) → \(named(to, leading: false))"
            case (nil, let to?): "\(named(to, leading: true)) selected"
            case (let from?, nil): "\(named(from, leading: true)) no longer selected"
            default: nil
            }
        }
    }

    /// Switches that kept their name and flipped, up to two.
    private static func switchChanges(_ before: AXSnapshot, _ after: AXSnapshot) -> [String] {
        let was = Dictionary(
            switches(in: before).map { (LabelStability.normalize($0.label), $0.isOn) }, uniquingKeysWith: { a, _ in a })
        let flipped = switches(in: after).filter { now in
            was[LabelStability.normalize(now.label)].map { $0 != now.isOn } ?? false
        }
        return flipped.prefix(2).map { flip in
            let name = LabelStability.isStable(roleClass: .checkbox, label: flip.label) ? " \(quoted(flip.label))" : ""
            return "switch\(name) \(flip.isOn ? "on" : "off")"
        }
    }

    /// Headings that weren't showing, other than a dialog's title, up to two named.
    private static func headingChanges(_ before: AXSnapshot, _ after: AXSnapshot) -> [String] {
        let known = Set((headings(in: before) + dialogTitles(in: after)).map(LabelStability.normalize))
        let added = headings(in: after).filter { !known.contains(LabelStability.normalize($0)) }
        guard !added.isEmpty else { return [] }
        let named = added.prefix(2).filter { LabelStability.isStable(roleClass: .heading, label: $0) }
        let noun = added.count == 1 ? "heading" : "headings"
        return [named.isEmpty ? "new \(noun)" : "\(noun) " + named.map(quoted).joined(separator: ", ")]
    }

    private static func focusChange(_ before: AXSnapshot, _ after: AXSnapshot) -> [String] {
        // Element IDs number each look on its own, so the field is told apart by its name.
        guard let field = focusedField(in: after), focusedField(in: before)?.label != field.label else { return [] }
        return [
            LabelStability.isStable(roleClass: .field, label: field.label)
                ? "focus in field \(quoted(field.label))" : "focus in a field"
        ]
    }

    /// How many visible elements appeared and went, by role and words, leaving out
    /// text with numbers in it, which ticks on its own as the screen's digest does.
    private static func countChange(_ before: AXSnapshot, _ after: AXSnapshot) -> [String] {
        func counts(_ snapshot: AXSnapshot) -> [String: Int] {
            var counts: [String: Int] = [:]
            for node in snapshot.nodes where node.isVisible && !node.isContainer {
                if node.roleClass == .text, node.label.contains(where: \.isNumber) { continue }
                counts["\(node.roleClass.rawValue)|\(LabelStability.normalize(node.label))", default: 0] += 1
            }
            return counts
        }
        let was = counts(before)
        let now = counts(after)
        let added = now.reduce(0) { $0 + max(0, $1.value - (was[$1.key] ?? 0)) }
        let removed = was.reduce(0) { $0 + max(0, $1.value - (now[$1.key] ?? 0)) }
        func elements(_ count: Int) -> String { "\(count) element\(count == 1 ? "" : "s")" }
        return switch (added, removed) {
        case (0, 0): []
        case (_, 0): ["\(elements(added)) added"]
        case (0, _): ["\(elements(removed)) removed"]
        default: ["\(elements(added)) added, \(removed) removed"]
        }
    }

    private static func quoted(_ label: String) -> String {
        let text = label.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return "“\(text.count > 40 ? String(text.prefix(39)) + "…" : text)”"
    }

    /// Each open dialog, sheet or alert, by its own title or else the first heading
    /// in it; "" when it has neither.
    private static func dialogTitles(in snapshot: AXSnapshot) -> [String] {
        let dialogs = snapshot.nodes.filter { node in
            node.role == "AXSheet" || node.role == "AXDialog" || node.subrole?.contains("Dialog") == true
        }
        let titles = dialogs.map { dialog in
            dialog.label.isEmpty
                ? snapshot.nodes.first { $0.roleClass == .heading && $0.containerID == dialog.id }?.label ?? ""
                : dialog.label
        }
        guard titles.isEmpty, snapshot.dialogOpen else { return titles }
        // A web dialog with no name isn't kept as a node; its heading still names it.
        return [snapshot.nodes.first { $0.inDialog && $0.roleClass == .heading }?.label ?? ""]
    }

    /// `values` left once each of `others` takes away one equal to it.
    private static func extra(in values: [String], over others: [String]) -> [String] {
        var remaining = others
        return values.filter { value in
            guard let index = remaining.firstIndex(of: value) else { return true }
            remaining.remove(at: index)
            return false
        }
    }

    /// The first selected tab, option or row with a label, and its place (from 1)
    /// among the ones of its kind showing.
    private static func selected(_ roleClass: AXRoleClass, in snapshot: AXSnapshot) -> (label: String, place: Int)? {
        let showing = DemoLocatorMatcher.ordered(snapshot.nodes.filter { $0.isVisible && $0.roleClass == roleClass })
        guard let index = showing.firstIndex(where: { $0.isSelected && !$0.label.isEmpty }) else { return nil }
        return (showing[index].label, index + 1)
    }

    private static func switches(in snapshot: AXSnapshot) -> [(label: String, isOn: Bool)] {
        snapshot.nodes.compactMap { node in
            guard node.isVisible, node.roleClass == .checkbox, !node.label.isEmpty, let isOn = node.toggleValue
            else { return nil }
            return (node.label, isOn)
        }
    }

    private static func headings(in snapshot: AXSnapshot) -> [String] {
        DemoLocatorMatcher.ordered(snapshot.nodes.filter { $0.isVisible && $0.roleClass == .heading })
            .map(\.label).filter { !$0.isEmpty }
    }

    private static func focusedField(in snapshot: AXSnapshot) -> AXNode? {
        snapshot.focusedID.flatMap { snapshot.node($0) }.flatMap { $0.roleClass == .field ? $0 : nil }
    }
}

/// Cleans the short notes Claude writes with an action before the scout keeps them.
enum ScoutNote {
    /// Most characters a target note keeps.
    static let targetLength = 120

    /// What a target looks like and where it sits, kept on its locator for finding it
    /// again: one line of at most 120 characters, without numbers, amounts, dates,
    /// email addresses or handles, which are live data, and without anything that
    /// reads as markup. Nil when nothing is left.
    static func target(_ text: String) -> String? {
        // Whole words with an @ or a digit in them: addresses, handles, amounts, dates, times and counts.
        var note = line(text).replacingOccurrences(of: #"\S*[@\d]\S*"#, with: " ", options: .regularExpression)
        note = line(note)
        if note.count > targetLength {
            let cut = note.prefix(targetLength)
            note = String(cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut)
        }
        // What stripping left dangling at either end, like the comma after a removed amount.
        note = note.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-–—·"))
        return note.isEmpty ? nil : note
    }

    /// What Claude expects an action to do: one line of at most 12 words. Nil when it said nothing.
    static func expectation(_ text: String) -> String? {
        let kept = clipped(text, words: 12, characters: 100)
        return kept.isEmpty ? nil : kept
    }

    /// Why Claude judged its last action as it did: one line of at most 15 words.
    static func reason(_ text: String) -> String {
        clipped(text, words: 15, characters: 120)
    }

    /// At most `words` words and `characters` characters on one line.
    private static func clipped(_ text: String, words: Int, characters: Int) -> String {
        let kept = line(text).split(separator: " ").prefix(words).joined(separator: " ")
        return kept.count > characters ? String(kept.prefix(characters - 1)) + "…" : kept
    }

    /// One line with single spaces, no control characters, double quotes as single
    /// quotes and no angle brackets, so a note can't pass for markup around it.
    private static func line(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            let blank = CharacterSet.controlCharacters.contains(scalar) || scalar == "<" || scalar == ">"
            scalars.append(blank ? " " : scalar == "\"" ? "'" : scalar)
        }
        return String(scalars).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
