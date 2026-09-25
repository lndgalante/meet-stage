import AppKit
import ScreenCaptureKit

struct StageCaptureFormat: Equatable {
    let width: Int
    let height: Int

    var aspectRatio: CGFloat {
        CGFloat(width) / CGFloat(height)
    }
}

enum StageWindowAspectRatioPolicy {
    static func displayedAspectRatio(
        for state: CaptureState,
        sourceAspectRatio: CGFloat,
        inactiveAspectRatio: CGFloat
    ) -> CGFloat {
        switch state {
        case .switching, .capturing:
            return sourceAspectRatio
        case .idle, .loading, .paused, .permissionRequired, .failed:
            return inactiveAspectRatio
        }
    }
}

enum StageWindowSizing {
    /// A 2560px surface leaves useful detail for the strongest stage zoom while
    /// avoiding the bandwidth and GPU cost of processing full 4K/5K windows.
    private static let maximumCaptureEdge: CGFloat = 2_560

    @MainActor
    static func currentScreenAspectRatio() -> CGFloat {
        let size = currentScreen()?.frame.size ?? NSSize(width: 16, height: 10)
        return validAspectRatio(for: size)
    }

    @MainActor
    static func captureFormat(for filter: SCContentFilter) -> StageCaptureFormat {
        let screen = currentScreen()
        let screenScale = screen?.backingScaleFactor ?? 1
        let screenSize = screen?.frame.size ?? NSSize(width: 1_920, height: 1_080)
        let contentSize = filter.contentRect.size
        let contentScale = max(CGFloat(filter.pointPixelScale), 1)
        let measuredSize = NSSize(
            width: contentSize.width * contentScale,
            height: contentSize.height * contentScale
        )
        let fallbackSize = NSSize(
            width: screenSize.width * screenScale,
            height: screenSize.height * screenScale
        )
        let baseSize =
            measuredSize.width > 0 && measuredSize.height > 0
            ? measuredSize
            : fallbackSize
        return captureFormat(forPixelSize: baseSize)
    }

    static func captureFormat(forPixelSize baseSize: NSSize) -> StageCaptureFormat {
        let longestEdge = max(baseSize.width, baseSize.height)
        let scale = longestEdge > maximumCaptureEdge ? maximumCaptureEdge / longestEdge : 1

        return StageCaptureFormat(
            width: evenPixelCount(baseSize.width * scale),
            height: evenPixelCount(baseSize.height * scale)
        )
    }

    @MainActor
    private static func currentScreen() -> NSScreen? {
        NSScreen.main ?? NSScreen.screens.first
    }

    private static func validAspectRatio(for size: NSSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return 16 / 10 }
        return normalizedAspectRatio(size.width / size.height)
    }

    static func normalizedAspectRatio(_ aspectRatio: CGFloat) -> CGFloat {
        guard aspectRatio.isFinite, aspectRatio > 0 else { return 16 / 10 }
        return min(max(aspectRatio, 0.75), 3)
    }

    static func evenPixelCount(_ value: CGFloat) -> Int {
        guard value.isFinite, value > 0 else { return 2 }
        let rounded = max(2, Int(value.rounded()))
        return rounded.isMultiple(of: 2) ? rounded : rounded - 1
    }
}
