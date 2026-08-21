import AppKit
import Foundation

/// Owns non-Sendable Objective-C notification tokens so `CaptureManager` does
/// not access them from its nonisolated deinitializer.
private final class WorkspaceObservationBag: @unchecked Sendable {
    private let center: NotificationCenter
    private var tokens: [NSObjectProtocol] = []

    init(center: NotificationCenter) {
        self.center = center
    }

    func store(_ tokens: [NSObjectProtocol]) {
        self.tokens.append(contentsOf: tokens)
    }

    deinit {
        tokens.forEach(center.removeObserver)
    }
}

/// Converts AppKit workspace notifications into two domain-level callbacks.
/// Notification token ownership stays in `WorkspaceObservationBag` so the
/// coordinator does not need to manage Objective-C resources directly.
@MainActor
final class WorkspaceMonitor {
    typealias ApplicationHandler = @MainActor @Sendable (NSRunningApplication) -> Void
    typealias SourceListHandler = @MainActor @Sendable () -> Void

    private let observationBag: WorkspaceObservationBag

    init(
        center: NotificationCenter = NSWorkspace.shared.notificationCenter,
        onApplicationActivated: @escaping ApplicationHandler,
        onApplicationDeactivated: @escaping ApplicationHandler,
        onSourceListChanged: @escaping SourceListHandler
    ) {
        let observationBag = WorkspaceObservationBag(center: center)
        self.observationBag = observationBag

        let activationToken = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let application = Self.application(from: notification) else { return }
            Task { @MainActor in
                onApplicationActivated(application)
            }
        }
        let deactivationToken = center.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let application = Self.application(from: notification) else { return }
            Task { @MainActor in
                onApplicationDeactivated(application)
            }
        }
        let sourceListTokens = Self.sourceListNotificationNames.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in
                    onSourceListChanged()
                }
            }
        }

        observationBag.store([activationToken, deactivationToken] + sourceListTokens)
    }

    private static let sourceListNotificationNames: [Notification.Name] = [
        NSWorkspace.didLaunchApplicationNotification,
        NSWorkspace.didTerminateApplicationNotification,
        NSWorkspace.didHideApplicationNotification,
        NSWorkspace.didUnhideApplicationNotification
    ]

    private nonisolated static func application(
        from notification: Notification
    ) -> NSRunningApplication? {
        notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    }
}
