import Foundation

/// Suppresses repeated Demo Mode actions when the transcriber re-emits an
/// overlapping phrase or the presenter lingers on one control. The gate is pure
/// and time-injected so its debounce behavior is fully testable.
///
/// A command is keyed by the target label and intent, so escalating from a
/// highlight to a click on the same control still fires while a duplicate
/// highlight within the cooldown does not.
struct DemoCommandGate {
    /// Default per-target debounce interval, in seconds.
    static let defaultCooldown: TimeInterval = 2.5

    private var lastFired: [Key: TimeInterval] = [:]

    private struct Key: Hashable {
        let label: String
        let action: String
    }

    /// Returns true and records the command when it should fire; false when it
    /// duplicates a recent identical command.
    mutating func admit(
        _ command: DemoResolvedCommand,
        at now: TimeInterval,
        cooldown: TimeInterval = defaultCooldown
    ) -> Bool {
        admit(label: command.element.label, action: command.kind.rawValue, at: now, cooldown: cooldown)
    }

    /// Generalized debounce keyed by (target label, action). Covers every action
    /// kind — highlight, click, type, circle, spotlight, zoom — so a re-emitted
    /// utterance cannot double-fire a paid call or, worse, type the text twice.
    mutating func admit(
        label: String,
        action: String,
        at now: TimeInterval,
        cooldown: TimeInterval = defaultCooldown
    ) -> Bool {
        let key = Key(label: label, action: action)
        if let previous = lastFired[key], now - previous < cooldown {
            return false
        }
        lastFired[key] = now
        return true
    }

    /// Clears history so a new source or a re-armed session starts fresh.
    mutating func reset() {
        lastFired.removeAll()
    }
}
