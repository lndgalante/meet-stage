import Carbon.HIToolbox
import Foundation

@MainActor
final class GlobalHotKeyManager {
    typealias Handler = @MainActor (Int) -> Void

    private static let signature: OSType = 0x4D_53_54_47 // "MSTG"
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
    private var eventHandler: EventHandlerRef?
    private var hotKeyReferences: [Int: EventHotKeyRef] = [:]

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    deinit {
        hotKeyReferences.values.forEach { reference in
            UnregisterEventHotKey(reference)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    func updateRegisteredSlots(_ slots: Set<Int>) -> Set<Int> {
        installEventHandlerIfNeeded()

        for slot in Set(hotKeyReferences.keys).subtracting(slots) {
            if let reference = hotKeyReferences.removeValue(forKey: slot) {
                UnregisterEventHotKey(reference)
            }
        }

        var failures: Set<Int> = []
        for slot in slots.sorted() where hotKeyReferences[slot] == nil {
            guard let keyCode = Self.numberKeyCodes[slot] else { continue }

            var reference: EventHotKeyRef?
            let identifier = EventHotKeyID(
                signature: Self.signature,
                id: UInt32(slot)
            )
            let status = RegisterEventHotKey(
                keyCode,
                UInt32(optionKey),
                identifier,
                GetApplicationEventTarget(),
                0,
                &reference
            )

            if status == noErr, let reference {
                hotKeyReferences[slot] = reference
            } else {
                failures.insert(slot)
            }
        }

        return failures
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            Self.hotKeyCallback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
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
