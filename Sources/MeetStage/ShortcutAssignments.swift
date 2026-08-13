import CoreGraphics

/// The global keyboard-shortcut slots supported by BetterDemos.
enum ShortcutSlot {
    static let all = 1...9

    static func isValid(_ slot: Int) -> Bool {
        all.contains(slot)
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
        var seenWindowIDs: Set<CGWindowID> = []
        let uniqueCandidates = candidates.filter { seenWindowIDs.insert($0.id).inserted }
        let candidatesByID = Dictionary(
            uniqueKeysWithValues: uniqueCandidates.map { ($0.id, $0) }
        )
        var resolvedPins = pins
        var assignments: [Int: CGWindowID] = [:]
        var pinnedAssignments: [Int: CGWindowID] = [:]
        var usedWindowIDs: Set<CGWindowID> = []

        for slot in pins.keys.sorted() {
            guard let pin = pins[slot] else { continue }

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

        let reservedSlots = Set(pins.keys)
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
