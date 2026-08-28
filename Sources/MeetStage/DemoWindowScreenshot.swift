import AppKit
import CoreMedia
import ScreenCaptureKit

/// Captures a downscaled JPEG of the source window to ground the Demo Mode brain,
/// mirroring how the thumbnail capture works. The image is the window's own
/// content (no letterbox), so a model coordinate maps to the window by dividing
/// by the image size.
enum DemoWindowScreenshot {
    /// Longest-edge pixel budget — small enough for fast, cheap vision calls.
    static let maximumEdge: CGFloat = 1024
    static let compressionQuality = 0.7

    struct Capture: Sendable {
        let base64JPEG: String
        let pixelSize: CGSize
    }

    @MainActor
    static func capture(source: WindowSource) async -> Capture? {
        let frame = WindowFrameResolver.currentFrame(
            for: source.id,
            fallback: source.window.frame
        )
        guard frame.width > 0, frame.height > 0 else { return nil }

        let scale = min(1, maximumEdge / max(frame.width, frame.height))
        let width = max(1, Int((frame.width * scale).rounded()))
        let height = max(1, Int((frame.height * scale).rounded()))

        let filter = SCContentFilter(desktopIndependentWindow: source.window)
        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = true
        configuration.ignoreShadowsSingleWindow = true
        configuration.ignoreGlobalClipSingleWindow = true

        do {
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            guard let jpeg = jpegData(from: image) else { return nil }
            return Capture(
                base64JPEG: jpeg.base64EncodedString(),
                pixelSize: CGSize(width: image.width, height: image.height)
            )
        } catch {
            AppLog.demoMode.error(
                "Demo screenshot failed: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    private static func jpegData(from image: CGImage) -> Data? {
        let bitmap = NSBitmapImageRep(cgImage: image)
        return bitmap.representation(
            using: .jpeg,
            properties: [.compressionFactor: compressionQuality]
        )
    }
}
