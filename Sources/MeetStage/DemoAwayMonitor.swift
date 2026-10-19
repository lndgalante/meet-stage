import AppKit
import Carbon
import Foundation

/// Why nobody can be using the Mac, so a background run waits instead of spending
/// model turns, screenshots and actions nobody sees.
enum DemoAwayReason: Equatable, Sendable {
    /// The displays went to sleep.
    case displaySleep
    /// The person switched to another user, or to the login window.
    case sessionInactive

    /// Why `run` paused, and that it goes on by itself: “Paused while your Mac
    /// sleeps. The build goes on once it wakes.”
    func message(resuming run: String) -> String {
        switch self {
        case .displaySleep: "Paused while your Mac sleeps. The \(run) goes on once it wakes."
        case .sessionInactive: "Paused while you’re switched to another user. The \(run) goes on once you’re back."
        }
    }
}

/// Follows the displays sleeping and waking and the person's session going to
/// the background and coming back, through NSWorkspace's documented
/// notifications. The screen locking has no public notification, so it counts
/// only once its displays sleep, and displays that wake to it read as back: the
/// session then waits for `isSecureInputOn()` to end, as the password field
/// there holds it, before a run goes on.
@MainActor
final class DemoAwayMonitor {
    /// Called with the new reason, or nil once the Mac is back, whenever it changes.
    var onChange: ((DemoAwayReason?) -> Void)?
    private var displaysAsleep = false
    private var sessionInactive = false
    private let observations: WorkspaceObservationBag

    private enum Event {
        case displaysSlept, displaysWoke, sessionResigned, sessionReturned
    }

    init(center: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        observations = WorkspaceObservationBag(center: center)
        let events: [(Notification.Name, Event)] = [
            (NSWorkspace.screensDidSleepNotification, .displaysSlept),
            (NSWorkspace.screensDidWakeNotification, .displaysWoke),
            (NSWorkspace.sessionDidResignActiveNotification, .sessionResigned),
            (NSWorkspace.sessionDidBecomeActiveNotification, .sessionReturned)
        ]
        observations.store(
            events.map { name, event in
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.handle(event) }
                }
            })
    }

    /// Whether an app holds secure keyboard entry, as a focused password field
    /// does, the lock screen's included.
    nonisolated static func isSecureInputOn() -> Bool {
        IsSecureEventInputEnabled()
    }

    /// A switched-out session outranks sleeping displays: it's the one to come back from.
    var reason: DemoAwayReason? {
        if sessionInactive { return .sessionInactive }
        return displaysAsleep ? .displaySleep : nil
    }

    private func handle(_ event: Event) {
        let before = reason
        switch event {
        case .displaysSlept: displaysAsleep = true
        case .displaysWoke: displaysAsleep = false
        case .sessionResigned: sessionInactive = true
        case .sessionReturned: sessionInactive = false
        }
        if reason != before { onChange?(reason) }
    }
}
