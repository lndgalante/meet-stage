import Foundation

/// Persists shortcut preferences using the legacy keys shipped by MeetStage.
///
/// The keys and encoded property names are part of the on-disk compatibility
/// contract. Keep them stable across product renames and model refactors.
struct ShortcutPreferencesStore {
    static let pinsKey = "MeetStage.shortcutPins.v1"
    static let exclusionsKey = "MeetStage.shortcutExclusions.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func loadPins() -> [Int: PinnedWindow] {
        guard let data = defaults.data(forKey: Self.pinsKey),
            let pins = try? JSONDecoder().decode([ShortcutPin].self, from: data)
        else {
            return [:]
        }
        return Dictionary(
            pins.filter { ShortcutSlot.isValid($0.slot) }.map { ($0.slot, $0.window) },
            uniquingKeysWith: { _, newest in newest }
        )
    }

    func loadExclusions() -> Set<PinnedWindow> {
        guard let data = defaults.data(forKey: Self.exclusionsKey),
            let exclusions = try? JSONDecoder().decode([PinnedWindow].self, from: data)
        else {
            return []
        }
        return Set(exclusions)
    }

    func savePins(_ pins: [Int: PinnedWindow]) {
        let values =
            pins
            .map { ShortcutPin(slot: $0.key, window: $0.value) }
            .sorted { $0.slot < $1.slot }
        guard let data = try? JSONEncoder().encode(values) else {
            assertionFailure("Shortcut pins must remain JSON encodable")
            return
        }
        defaults.set(data, forKey: Self.pinsKey)
    }

    func saveExclusions(_ exclusions: Set<PinnedWindow>) {
        let values = exclusions.sorted {
            $0.description.localizedCaseInsensitiveCompare($1.description) == .orderedAscending
        }
        guard let data = try? JSONEncoder().encode(values) else {
            assertionFailure("Shortcut exclusions must remain JSON encodable")
            return
        }
        defaults.set(data, forKey: Self.exclusionsKey)
    }
}
