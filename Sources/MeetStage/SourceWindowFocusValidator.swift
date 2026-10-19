import AppKit
import ApplicationServices
import MeetStageCore

/// Proves that the selected CG window—not merely another window from the same
/// process—is the application's live focused Accessibility window.
enum SourceWindowFocusValidator {
    private static let messagingTimeout: Float = 0.2

    @MainActor
    static func isExactlyFocused(_ source: WindowSource) -> Bool {
        isExactlyFocused(windowID: source.id, pid: source.processIdentifier)
    }

    /// The same for the window `windowID` of the app `pid`. `logsFailure` is off for
    /// checks that fail all the time, like a key the presenter types in another window.
    @MainActor
    static func isExactlyFocused(windowID: CGWindowID, pid: pid_t, logsFailure: Bool = true) -> Bool {
        guard let snapshot = WindowFrameResolver.currentSnapshot(for: windowID) else {
            return false
        }

        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        let windows = AccessibilityWindowResolver.windows(in: app)
        let candidates = windows.map { window in
            AccessibilityWindowResolver.frame(of: window).map(CaptureWindowBounds.init)
                ?? CaptureWindowBounds(x: .nan, y: .nan, width: .nan, height: .nan)
        }
        let matchingIndex = ExactWindowFocusPolicy.uniqueBestMatch(
            source: CaptureWindowBounds(snapshot.frame),
            candidates: candidates
        )
        let focusedIndex = AccessibilityWindowResolver.focusedWindow(in: app).flatMap {
            focusedWindow in
            windows.firstIndex { CFEqual($0, focusedWindow) }
        }

        let frontmostPID = NSWorkspace.shared.frontmostApplication.map { Int($0.processIdentifier) }
        let allows = ExactWindowFocusPolicy.allowsActuation(
            sourcePID: Int(pid),
            frontmostPID: frontmostPID,
            windowOwnerPID: Int(snapshot.ownerPID),
            windowIsOnScreen: snapshot.isOnScreen,
            matchingWindowIndex: matchingIndex,
            focusedWindowIndex: focusedIndex
        )
        if !allows, logsFailure {
            AppLog.demoMode.error(
                "Demo focus check failed: sourcePID=\(pid) frontmostPID=\(frontmostPID ?? -1) ownerPID=\(snapshot.ownerPID) onScreen=\(snapshot.isOnScreen) matching=\(matchingIndex ?? -1) focused=\(focusedIndex ?? -1)"
            )
        }
        return allows
    }
}
