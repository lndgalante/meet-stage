import Carbon.HIToolbox
import Foundation

/// Owns Carbon registrations for the configurable app-wide source shortcuts.
@MainActor
final class GlobalHotKeyManager {
    typealias Handler = @MainActor (Int) -> Void

    private static let signature: OSType = 0x4D_53_54_47  // "MSTG"
    private static let numberKeyCodes: [Int: UInt32] = [
        1: UInt32(kVK_ANSI_1),
        2: UInt32(kVK_ANSI_2),
        3: UInt32(kVK_ANSI_3),
        4: UInt32(kVK_ANSI_4),
        5: UInt32(kVK_ANSI_5),
        6: UInt32(kVK_ANSI_6),
        7: UInt32(kVK_ANSI_7),
        8: UInt32(kVK_ANSI_8),
        9: UInt32(kVK_ANSI_9)
    ]

    private let handler: Handler
    private let resources = GlobalHotKeyResources()
    private var registeredModifier: GlobalShortcutModifier?

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func updateRegisteredSlots(
        _ slots: Set<Int>,
        modifier: GlobalShortcutModifier
    ) -> Set<Int> {
        let validSlots = Set(slots.filter(ShortcutSlot.isValid))
        guard let carbonModifiers = modifier.carbonModifiers else {
            resources.unregisterAllHotKeys()
            registeredModifier = modifier
            return []
        }
        guard installEventHandlerIfNeeded() else { return slots }

        if registeredModifier != modifier {
            resources.unregisterAllHotKeys()
            registeredModifier = modifier
        }

        for slot in Set(resources.hotKeyReferences.keys).subtracting(validSlots) {
            if let reference = resources.hotKeyReferences.removeValue(forKey: slot) {
                UnregisterEventHotKey(reference)
            }
        }

        var failures = slots.subtracting(validSlots)
        for slot in validSlots.sorted() where resources.hotKeyReferences[slot] == nil {
            guard let keyCode = Self.numberKeyCodes[slot] else { continue }

            var reference: EventHotKeyRef?
            let identifier = EventHotKeyID(
                signature: Self.signature,
                id: UInt32(slot)
            )
            let status = RegisterEventHotKey(
                keyCode,
                carbonModifiers,
                identifier,
                GetApplicationEventTarget(),
                0,
                &reference
            )

            if status == noErr, let reference {
                resources.hotKeyReferences[slot] = reference
            } else {
                failures.insert(slot)
            }
        }

        return failures
    }

    private func installEventHandlerIfNeeded() -> Bool {
        guard resources.eventHandler == nil else { return true }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.hotKeyCallback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &resources.eventHandler
        )
        return status == noErr && resources.eventHandler != nil
    }

    private static let hotKeyCallback: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }

        var identifier = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &identifier
        )
        guard status == noErr else { return status }
        guard identifier.signature == GlobalHotKeyManager.signature else {
            return OSStatus(eventNotHandledErr)
        }

        let manager = Unmanaged<GlobalHotKeyManager>
            .fromOpaque(userData)
            .takeUnretainedValue()
        let slot = Int(identifier.id)

        Task { @MainActor in
            manager.handler(slot)
        }

        return noErr
    }
}

/// Carbon's opaque references are not Sendable. Grouping them in one owner
/// keeps their lifetime independent from the manager's actor-isolated state.
private final class GlobalHotKeyResources: @unchecked Sendable {
    var eventHandler: EventHandlerRef?
    var hotKeyReferences: [Int: EventHotKeyRef] = [:]

    func unregisterAllHotKeys() {
        hotKeyReferences.values.forEach { reference in
            UnregisterEventHotKey(reference)
        }
        hotKeyReferences.removeAll()
    }

    deinit {
        unregisterAllHotKeys()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}
