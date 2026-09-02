import AppKit
import ApplicationServices
import MeetStageCore

/// Proves that the selected CG window—not merely another window from the same
/// process—is the application's live focused Accessibility window.
enum SourceWindowFocusValidator {
    private static let messagingTimeout: Float = 0.2

    @MainActor
    static func isExactlyFocused(_ source: WindowSource) -> Bool {
        guard let snapshot = WindowFrameResolver.currentSnapshot(for: source.id) else {
            return false
        }

        let app = AXUIElementCreateApplication(source.processIdentifier)
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

        return ExactWindowFocusPolicy.allowsActuation(
            sourcePID: Int(source.processIdentifier),
            frontmostPID: NSWorkspace.shared.frontmostApplication.map {
                Int($0.processIdentifier)
            },
            windowOwnerPID: Int(snapshot.ownerPID),
            windowIsOnScreen: snapshot.isOnScreen,
            matchingWindowIndex: matchingIndex,
            focusedWindowIndex: focusedIndex
        )
    }
}
