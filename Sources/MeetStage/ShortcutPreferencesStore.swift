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
        guard let data = defaults.data(forKey: Self.pinsKey) else {
            return [:]
        }
        let pins: [ShortcutPin]
        do {
            pins = try JSONDecoder().decode([ShortcutPin].self, from: data)
        } catch {
            AppLog.preferences.warning(
                "Ignoring invalid shortcut pins: \(error.localizedDescription, privacy: .public)"
            )
            return [:]
        }
        return Dictionary(
            pins.filter { ShortcutSlot.isValid($0.slot) }.map { ($0.slot, $0.window) },
            uniquingKeysWith: { _, newest in newest }
        )
    }

    func loadExclusions() -> Set<PinnedWindow> {
        guard let data = defaults.data(forKey: Self.exclusionsKey) else {
            return []
        }
        do {
            return Set(try JSONDecoder().decode([PinnedWindow].self, from: data))
        } catch {
            AppLog.preferences.warning(
                "Ignoring invalid shortcut exclusions: \(error.localizedDescription, privacy: .public)"
            )
            return []
        }
    }

    func savePins(_ pins: [Int: PinnedWindow]) {
        let values =
            pins
            .map { ShortcutPin(slot: $0.key, window: $0.value) }
            .sorted { $0.slot < $1.slot }
        do {
            defaults.set(try JSONEncoder().encode(values), forKey: Self.pinsKey)
        } catch {
            AppLog.preferences.fault(
                "Could not encode shortcut pins: \(error.localizedDescription, privacy: .public)"
            )
            assertionFailure("Shortcut pins must remain JSON encodable")
        }
    }

    func saveExclusions(_ exclusions: Set<PinnedWindow>) {
        let values = exclusions.sorted {
            $0.description.localizedCaseInsensitiveCompare($1.description) == .orderedAscending
        }
        do {
            defaults.set(try JSONEncoder().encode(values), forKey: Self.exclusionsKey)
        } catch {
            AppLog.preferences.fault(
                "Could not encode shortcut exclusions: \(error.localizedDescription, privacy: .public)"
            )
            assertionFailure("Shortcut exclusions must remain JSON encodable")
        }
    }
}
