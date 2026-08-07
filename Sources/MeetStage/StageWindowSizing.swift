import AppKit
import ScreenCaptureKit

struct StageCaptureFormat: Equatable {
    let width: Int
    let height: Int

    var aspectRatio: CGFloat {
        CGFloat(width) / CGFloat(height)
    }
}

@MainActor
enum StageWindowSizing {
    private static let windowScale: CGFloat = 0.68
    private static let maximumCaptureEdge: CGFloat = 4_096

    static func currentScreenAspectRatio() -> CGFloat {
        let size = currentScreen()?.frame.size ?? NSSize(width: 16, height: 10)
        return validAspectRatio(for: size)
    }

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
        let baseSize = measuredSize.width > 0 && measuredSize.height > 0
            ? measuredSize
            : fallbackSize
        let longestEdge = max(baseSize.width, baseSize.height)
        let scale = longestEdge > maximumCaptureEdge ? maximumCaptureEdge / longestEdge : 1

        return StageCaptureFormat(
            width: evenPixelCount(baseSize.width * scale),
            height: evenPixelCount(baseSize.height * scale)
        )
    }

    static func defaultWindowContentSize(
        aspectRatio: CGFloat? = nil,
        on screen: NSScreen? = nil
    ) -> NSSize {
        let targetScreen = screen ?? currentScreen()
        let visibleSize = targetScreen?.visibleFrame.size ?? NSSize(width: 1_440, height: 900)
        let safeAspectRatio = normalized(aspectRatio ?? currentScreenAspectRatio())
        let maximumWidth = visibleSize.width * windowScale
        let maximumHeight = visibleSize.height * windowScale

        var width = maximumWidth
        var height = width / safeAspectRatio
        if height > maximumHeight {
            height = maximumHeight
            width = height * safeAspectRatio
        }

        if width < 640, maximumWidth >= 640 {
            width = 640
            height = width / safeAspectRatio
        }

        return NSSize(width: width.rounded(), height: height.rounded())
    }

    private static func currentScreen() -> NSScreen? {
        NSScreen.main ?? NSScreen.screens.first
    }

    private static func validAspectRatio(for size: NSSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return 16 / 10 }
        return normalized(size.width / size.height)
    }

    private static func normalized(_ aspectRatio: CGFloat) -> CGFloat {
        guard aspectRatio.isFinite, aspectRatio > 0 else { return 16 / 10 }
        return min(max(aspectRatio, 0.75), 3)
    }

    private static func evenPixelCount(_ value: CGFloat) -> Int {
        let rounded = max(2, Int(value.rounded()))
        return rounded.isMultiple(of: 2) ? rounded : rounded - 1
    }
}
