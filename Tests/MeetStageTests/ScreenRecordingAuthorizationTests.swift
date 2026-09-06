import Foundation
import Testing
@testable import MeetStage

@Suite("Screen recording consent")
@MainActor
struct ScreenRecordingAuthorizationTests {
    @Test("Launching and refreshing never open a system permission dialog")
    func refreshingDoesNotRequestPermission() throws {
        let name = "ScreenRecordingAuthorizationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let authorization = DeniedScreenRecordingAuthorization()
        let manager = CaptureManager(defaults: defaults, screenRecordingAuthorization: authorization)

        manager.refreshWindows()
        manager.refreshWindowsAutomatically()
        manager.refreshWindows()

        #expect(manager.needsScreenRecordingPermission)
        #expect(manager.windows.isEmpty)
        #expect(!manager.isRefreshing)
        #expect(authorization.requests == 0)
        #expect(!manager.requestedPermissionThisLaunch)

        manager.requestScreenRecordingPermission()

        #expect(authorization.requests == 1)
        #expect(manager.requestedPermissionThisLaunch)
        #expect(manager.needsScreenRecordingPermission)
    }
}

@MainActor
private final class DeniedScreenRecordingAuthorization: ScreenRecordingAuthorizing {
    let isAuthorized = false
    var requests = 0

    func requestAccess() -> Bool {
        requests += 1
        return false
    }
}
