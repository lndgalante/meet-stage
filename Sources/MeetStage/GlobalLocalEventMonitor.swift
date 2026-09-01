import AppKit

/// Owns matching global and local AppKit event monitors.
///
/// Local monitoring matters while BetterMeets' non-activating annotation panel
/// is receiving pointer events; global monitoring covers the selected source
/// application. The transform copies only a Sendable domain value before the
/// handler returns to the main actor.
@MainActor
final class GlobalLocalEventMonitor<Value: Sendable> {
    typealias Handler = @MainActor @Sendable (Value) -> Void
    typealias Transform = @Sendable (NSEvent) -> Value?

    private let eventMask: NSEvent.EventTypeMask
    private let coalescesEvents: Bool
    private let transform: Transform
    private let handler: Handler
    private let resources = GlobalLocalEventMonitorResources()
    private let latestDelivery: LatestMainActorDelivery<Value>

    init(
        eventMask: NSEvent.EventTypeMask,
        coalescingInterval: Duration? = nil,
        transform: @escaping Transform,
        handler: @escaping Handler
    ) {
        self.eventMask = eventMask
        coalescesEvents = coalescingInterval != nil
        self.transform = transform
        self.handler = handler
        latestDelivery = LatestMainActorDelivery(
            minimumInterval: coalescingInterval ?? .zero
        )
    }

    var observesLocalApplicationEvents: Bool {
        resources.localMonitor != nil
    }

    func start() {
        guard resources.globalMonitor == nil,
            resources.localMonitor == nil
        else { return }

        let transform = transform
        let handler = handler
        let coalescesEvents = coalescesEvents
        let latestDelivery = latestDelivery
        let dispatch: @Sendable (NSEvent) -> Void = { event in
            guard let value = transform(event) else { return }
            if coalescesEvents {
                latestDelivery.submit(value, to: handler)
            } else {
                Task { @MainActor in
                    handler(value)
                }
            }
        }

        resources.globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: eventMask,
            handler: dispatch
        )
        resources.localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: eventMask
        ) { event in
            dispatch(event)
            return event
        }
    }

    func stop() {
        resources.stop()
        latestDelivery.cancelPending()
    }
}

typealias GlobalMouseClickMonitor = GlobalLocalEventMonitor<GlobalClickLocation>
typealias GlobalPointerMonitor = GlobalLocalEventMonitor<CGPoint>

extension GlobalLocalEventMonitor where Value == GlobalClickLocation {
    convenience init(mouseClicks handler: @escaping Handler) {
        self.init(
            eventMask: [.leftMouseDown, .rightMouseDown, .otherMouseDown],
            transform: { event in
                guard let cgEvent = event.cgEvent else { return nil }
                let quartzPoint = cgEvent.location
                let appKitPoint = cgEvent.unflippedLocation
                return GlobalClickLocation(
                    quartzX: quartzPoint.x,
                    quartzY: quartzPoint.y,
                    appKitX: appKitPoint.x,
                    appKitY: appKitPoint.y
                )
            },
            handler: handler
        )
    }
}

extension GlobalLocalEventMonitor where Value == CGPoint {
    convenience init(pointerMovements handler: @escaping Handler) {
        self.init(
            eventMask: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged],
            coalescingInterval: .milliseconds(16),
            transform: { $0.cgEvent?.location },
            handler: handler
        )
    }
}

/// Prevents high-frequency pointer monitors from flooding the main actor. A
/// burst keeps only its newest position and schedules at most one display-paced
/// delivery, preserving direct tracking without stale backlog.
final class LatestMainActorDelivery<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var pendingValue: Value?
    private var deliveryGeneration: UInt64 = 0
    private var isDeliveryScheduled = false
    private let minimumInterval: Duration

    init(minimumInterval: Duration = .zero) {
        self.minimumInterval = minimumInterval
    }

    func submit(
        _ value: Value,
        to handler: @escaping @MainActor @Sendable (Value) -> Void
    ) {
        let generationToSchedule: UInt64? = lock.withLock {
            pendingValue = value
            guard !isDeliveryScheduled else { return nil }
            isDeliveryScheduled = true
            return deliveryGeneration
        }
        guard let generationToSchedule else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            if minimumInterval > .zero {
                try? await Task.sleep(for: minimumInterval)
            }
            let value: Value? = self.lock.withLock {
                guard generationToSchedule == self.deliveryGeneration else { return nil }
                self.isDeliveryScheduled = false
                defer { self.pendingValue = nil }
                return self.pendingValue
            }
            if let value {
                handler(value)
            }
        }
    }

    func cancelPending() {
        lock.withLock {
            deliveryGeneration &+= 1
            pendingValue = nil
            isDeliveryScheduled = false
        }
    }
}

/// AppKit monitor tokens are opaque, non-Sendable resources. This owner keeps
/// their cleanup safe even if deinitialization does not occur on the main actor.
private final class GlobalLocalEventMonitorResources: @unchecked Sendable {
    var globalMonitor: Any?
    var localMonitor: Any?

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    deinit {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }
}
