import Carbon.HIToolbox
import CoreGraphics
import SwiftUI

/// The system-wide modifier chord used by source slots 1–9.
///
/// Option-only shortcuts were the original BetterMeets behavior, but they steal
/// useful characters on many keyboard layouts. New installs use a safer chord,
/// while existing users can still opt into the legacy behavior or disable global
/// shortcuts entirely.
enum GlobalShortcutModifier: String, CaseIterable, Identifiable, Sendable {
    case commandOption
    case controlCommand
    case commandShift
    case option
    case disabled

    var id: Self { self }

    var label: String {
        switch self {
        case .commandOption: "Command–Option"
        case .controlCommand: "Control–Command"
        case .commandShift: "Command–Shift"
        case .option: "Option only (legacy)"
        case .disabled: "Off"
        }
    }

    var symbolPrefix: String {
        switch self {
        case .commandOption: "⌘⌥"
        case .controlCommand: "⌃⌘"
        case .commandShift: "⇧⌘"
        case .option: "⌥"
        case .disabled: ""
        }
    }

    var spokenPrefix: String {
        switch self {
        case .commandOption: "Command Option"
        case .controlCommand: "Control Command"
        case .commandShift: "Command Shift"
        case .option: "Option"
        case .disabled: ""
        }
    }

    var carbonModifiers: UInt32? {
        switch self {
        case .commandOption: UInt32(cmdKey | optionKey)
        case .controlCommand: UInt32(controlKey | cmdKey)
        case .commandShift: UInt32(cmdKey | shiftKey)
        case .option: UInt32(optionKey)
        case .disabled: nil
        }
    }

    var eventModifiers: SwiftUI.EventModifiers? {
        switch self {
        case .commandOption: [.command, .option]
        case .controlCommand: [.control, .command]
        case .commandShift: [.command, .shift]
        case .option: [.option]
        case .disabled: nil
        }
    }

    func displayName(for slot: Int) -> String {
        carbonModifiers == nil ? "Slot \(slot)" : "\(symbolPrefix)\(slot)"
    }

    func spokenName(for slot: Int) -> String {
        carbonModifiers == nil ? "source slot \(slot)" : "\(spokenPrefix) \(slot)"
    }
}

/// The global keyboard-shortcut slots supported by BetterMeets.
enum ShortcutSlot {
    static let all = 1...9
    static let defaultVisible = 1...4

    static func isValid(_ slot: Int) -> Bool {
        all.contains(slot)
    }

    static func visibleSlots(including additionalSlots: Set<Int> = []) -> [Int] {
        all.filter { defaultVisible.contains($0) || additionalSlots.contains($0) }
    }
}

/// The stable subset of a window source needed to assign shortcuts.
///
/// Keeping this value independent from `SCWindow` makes shortcut assignment a
/// deterministic policy that can be exercised without ScreenCaptureKit.
struct ShortcutCandidate: Equatable {
    let id: CGWindowID
    let identity: PinnedWindow

    init(id: CGWindowID, identity: PinnedWindow) {
        self.id = id
        self.identity = identity
    }

    init(source: WindowSource) {
        self.init(id: source.id, identity: PinnedWindow(source: source))
    }
}

/// The complete result of reconciling saved pins with the current windows.
struct ShortcutResolution: Equatable {
    let assignments: [Int: CGWindowID]
    let pinnedAssignments: [Int: CGWindowID]
    let pins: [Int: PinnedWindow]
}

/// Assigns pinned and automatic shortcuts while preserving stable assignments.
enum ShortcutAssignmentPolicy {
    static func resolve(
        candidates: [ShortcutCandidate],
        pins: [Int: PinnedWindow],
        exclusions: Set<PinnedWindow>,
        previousAssignments: [Int: CGWindowID],
        previousPinnedAssignments: [Int: CGWindowID]
    ) -> ShortcutResolution {
        // Treat callers and persisted data as untrusted at the policy boundary.
        let validPins = pins.filter { ShortcutSlot.isValid($0.key) }
        var seenWindowIDs: Set<CGWindowID> = []
        let uniqueCandidates = candidates.filter { seenWindowIDs.insert($0.id).inserted }
        let candidatesByID = Dictionary(
            uniqueKeysWithValues: uniqueCandidates.map { ($0.id, $0) }
        )
        var resolvedPins = validPins
        var assignments: [Int: CGWindowID] = [:]
        var pinnedAssignments: [Int: CGWindowID] = [:]
        var usedWindowIDs: Set<CGWindowID> = []

        for slot in validPins.keys.sorted() {
            guard let pin = validPins[slot] else { continue }

            let resolvedCandidate: ShortcutCandidate?
            if let previousWindowID = previousPinnedAssignments[slot],
                let existingCandidate = candidatesByID[previousWindowID],
                !usedWindowIDs.contains(previousWindowID)
            {
                // A window title can change while the app is running. Preserve
                // the already-resolved window and refresh its saved identity.
                resolvedCandidate = existingCandidate
            } else {
                let matches = uniqueCandidates.filter {
                    !usedWindowIDs.contains($0.id) && pin.matches($0.identity)
                }
                resolvedCandidate = matches.count == 1 ? matches[0] : nil
            }

            guard let resolvedCandidate else { continue }
            assignments[slot] = resolvedCandidate.id
            pinnedAssignments[slot] = resolvedCandidate.id
            usedWindowIDs.insert(resolvedCandidate.id)
            resolvedPins[slot] = resolvedCandidate.identity
        }

        let reservedSlots = Set(validPins.keys)
        let automaticSlots = ShortcutSlot.all.filter { !reservedSlots.contains($0) }

        // Preserve an automatic assignment while its window remains eligible.
        for slot in automaticSlots {
            guard let previousWindowID = previousAssignments[slot],
                let existingCandidate = candidatesByID[previousWindowID],
                !usedWindowIDs.contains(previousWindowID),
                !exclusions.contains(existingCandidate.identity)
            else {
                continue
            }
            assignments[slot] = previousWindowID
            usedWindowIDs.insert(previousWindowID)
        }

        var remainingCandidates = uniqueCandidates.filter {
            !usedWindowIDs.contains($0.id) && !exclusions.contains($0.identity)
        }.makeIterator()

        for slot in automaticSlots where assignments[slot] == nil {
            guard let candidate = remainingCandidates.next() else { break }
            assignments[slot] = candidate.id
            usedWindowIDs.insert(candidate.id)
        }

        return ShortcutResolution(
            assignments: assignments,
            pinnedAssignments: pinnedAssignments,
            pins: resolvedPins
        )
    }
}
