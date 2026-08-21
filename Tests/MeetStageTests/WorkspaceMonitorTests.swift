import AppKit
import Testing
@testable import MeetStage

@Suite("Workspace monitoring")
struct WorkspaceMonitorTests {
    @Test("Translates workspace notifications into domain callbacks")
    @MainActor
    func forwardsWorkspaceEvents() async {
        let center = NotificationCenter()
        let currentApplication = NSRunningApplication.current
        var activatedProcessID: pid_t?
        var deactivatedProcessID: pid_t?
        var sourceListChangeCount = 0
        let monitor = WorkspaceMonitor(
            center: center,
            onApplicationActivated: { application in
                activatedProcessID = application.processIdentifier
            },
            onApplicationDeactivated: { application in
                deactivatedProcessID = application.processIdentifier
            },
            onSourceListChanged: {
                sourceListChangeCount += 1
            }
        )

        center.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: currentApplication]
        )
        center.post(
            name: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: currentApplication]
        )
        center.post(
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )

        await waitUntil {
            activatedProcessID != nil
                && deactivatedProcessID != nil
                && sourceListChangeCount == 1
        }

        #expect(activatedProcessID == currentApplication.processIdentifier)
        #expect(deactivatedProcessID == currentApplication.processIdentifier)
        #expect(sourceListChangeCount == 1)
        withExtendedLifetime(monitor) {}
    }

    @MainActor
    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<1_000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(condition())
    }
}
