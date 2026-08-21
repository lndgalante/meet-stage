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
    private let transform: Transform
    private let handler: Handler
    private let resources = GlobalLocalEventMonitorResources()

    init(
        eventMask: NSEvent.EventTypeMask,
        transform: @escaping Transform,
        handler: @escaping Handler
    ) {
        self.eventMask = eventMask
        self.transform = transform
        self.handler = handler
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
        let dispatch: @Sendable (NSEvent) -> Void = { event in
            guard let value = transform(event) else { return }
            Task { @MainActor in
                handler(value)
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
            transform: { $0.cgEvent?.location },
            handler: handler
        )
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
