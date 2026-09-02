import AppKit

struct WindowFrameSnapshot: Equatable, Sendable {
    let frame: CGRect
    let ownerPID: pid_t
    let isOnScreen: Bool
}

/// A point expressed as a fraction of a window's width and height.
///
/// Values normally fall in `0...1`. Callers that accept arbitrary input must
/// use `WindowCoordinateGeometry` to either reject or clamp out-of-bounds
/// coordinates explicitly.
struct NormalizedWindowPoint: Equatable, Sendable {
    let x: CGFloat
    let y: CGFloat
}

/// Canonical coordinate conversion for source-window presentation effects.
enum WindowCoordinateGeometry {
    /// Maps a global Quartz point into a source window, rejecting points that
    /// are outside the source or frames that cannot define a coordinate space.
    static func normalizedPoint(
        inside globalPoint: CGPoint,
        sourceFrame: CGRect
    ) -> NormalizedWindowPoint? {
        guard globalPoint.x.isFinite,
            globalPoint.y.isFinite,
            sourceFrame.minX.isFinite,
            sourceFrame.minY.isFinite,
            sourceFrame.width.isFinite,
            sourceFrame.height.isFinite,
            sourceFrame.width > 0,
            sourceFrame.height > 0,
            globalPoint.x >= sourceFrame.minX,
            globalPoint.x <= sourceFrame.maxX,
            globalPoint.y >= sourceFrame.minY,
            globalPoint.y <= sourceFrame.maxY
        else { return nil }

        return NormalizedWindowPoint(
            x: (globalPoint.x - sourceFrame.minX) / sourceFrame.width,
            y: (globalPoint.y - sourceFrame.minY) / sourceFrame.height
        )
    }

    /// Maps a local point into a canvas and clamps pointer overshoot to its
    /// edges. Drag gestures use this behavior so a stroke can end cleanly at a
    /// window boundary.
    static func normalizedPoint(
        clamping localPoint: CGPoint,
        in canvasSize: CGSize
    ) -> NormalizedWindowPoint? {
        guard localPoint.x.isFinite,
            localPoint.y.isFinite,
            canvasSize.width.isFinite,
            canvasSize.height.isFinite,
            canvasSize.width > 0,
            canvasSize.height > 0
        else { return nil }

        return NormalizedWindowPoint(
            x: min(max(localPoint.x / canvasSize.width, 0), 1),
            y: min(max(localPoint.y / canvasSize.height, 0), 1)
        )
    }
}

/// Resolves the current Quartz frame for a window that may have moved or
/// resized since ScreenCaptureKit discovery completed.
enum WindowFrameResolver {
    static func currentSnapshot(for windowID: CGWindowID) -> WindowFrameSnapshot? {
        guard
            let windowInfo = CGWindowListCopyWindowInfo(
                [.optionIncludingWindow, .excludeDesktopElements],
                windowID
            ) as? [[CFString: Any]],
            let info = windowInfo.first,
            let bounds = info[kCGWindowBounds] as? NSDictionary,
            let frame = CGRect(dictionaryRepresentation: bounds),
            frame.width > 0,
            frame.height > 0,
            let ownerPID = info[kCGWindowOwnerPID] as? NSNumber
        else { return nil }

        return WindowFrameSnapshot(
            frame: frame,
            ownerPID: pid_t(ownerPID.int32Value),
            isOnScreen: (info[kCGWindowIsOnscreen] as? NSNumber)?.boolValue == true
        )
    }

    static func currentFrame(for windowID: CGWindowID, fallback: CGRect) -> CGRect {
        currentSnapshot(for: windowID)?.frame ?? fallback
    }
}

/// Converts and resolves frames shared by source-window overlay presenters.
enum SourceOverlayGeometry {
    static func appKitFrame(
        forQuartzFrame sourceFrame: CGRect,
        primaryScreenFrame: CGRect
    ) -> CGRect {
        CGRect(
            x: sourceFrame.minX,
            y: primaryScreenFrame.maxY - sourceFrame.maxY,
            width: sourceFrame.width,
            height: sourceFrame.height
        )
    }

    @MainActor
    static func currentAppKitFrame(
        for sourceWindowID: CGWindowID,
        fallbackSourceFrame: CGRect
    ) -> CGRect {
        let sourceFrame = WindowFrameResolver.currentFrame(
            for: sourceWindowID,
            fallback: fallbackSourceFrame
        )
        let primaryScreenFrame =
            NSScreen.screens.first?.frame
            ?? CGRect(x: 0, y: 0, width: sourceFrame.width, height: sourceFrame.maxY)
        return appKitFrame(
            forQuartzFrame: sourceFrame,
            primaryScreenFrame: primaryScreenFrame
        )
    }
}

/// Keeps a source overlay aligned while its captured window moves or resizes.
/// Presenters own panel creation; this type owns the shared polling lifecycle.
@MainActor
final class SourceOverlayFrameTracker {
    typealias FrameHandler = @MainActor (CGRect) -> Void

    private static let refreshInterval = Duration.milliseconds(100)
    private var task: Task<Void, Never>?

    deinit {
        task?.cancel()
    }

    func start(
        sourceWindowID: CGWindowID,
        fallbackSourceFrame: CGRect,
        onFrameChange: @escaping FrameHandler
    ) {
        stop()
        task = Task {
            var previousFrame: CGRect?

            while !Task.isCancelled {
                let frame = SourceOverlayGeometry.currentAppKitFrame(
                    for: sourceWindowID,
                    fallbackSourceFrame: fallbackSourceFrame
                )
                if frame != previousFrame {
                    previousFrame = frame
                    onFrameChange(frame)
                }

                do {
                    try await Task.sleep(for: Self.refreshInterval)
                } catch {
                    return
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
