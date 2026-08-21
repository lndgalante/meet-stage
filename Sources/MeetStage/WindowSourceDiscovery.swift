import AppKit
import ScreenCaptureKit

/// The platform-independent window facts used to decide whether a source
/// belongs in the picker.
struct WindowDiscoveryCandidate: Equatable, Sendable {
    let layer: Int
    let frame: CGRect
    let title: String?
    let hasOwningApplication: Bool
    let bundleIdentifier: String?
}

/// Centralizes the picker eligibility rules so source discovery and tests use
/// one definition of a shareable app window.
enum WindowDiscoveryPolicy {
    static let minimumSize = CGSize(width: 160, height: 100)

    static func isEligible(
        _ candidate: WindowDiscoveryCandidate,
        excludingBundleIdentifier ownBundleIdentifier: String?
    ) -> Bool {
        let normalizedTitle = candidate.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let belongsToAnotherApplication =
            ownBundleIdentifier.map {
                candidate.bundleIdentifier != $0
            } ?? true

        return candidate.layer == 0
            && candidate.frame.width >= minimumSize.width
            && candidate.frame.height >= minimumSize.height
            && !normalizedTitle.isEmpty
            && candidate.hasOwningApplication
            && belongsToAnotherApplication
    }
}

/// Owns ScreenCaptureKit source enumeration and preview capture. This keeps
/// discovery details out of the capture lifecycle coordinator.
@MainActor
enum WindowSourceDiscovery {
    // SCStreamConfiguration.backgroundColor is unretained, so this object must
    // outlive every screenshot configuration that references it.
    private static let thumbnailBackground = CGColor(gray: 0, alpha: 1)
    private static let thumbnailSize = CGSize(width: 480, height: 270)

    static func discover(reusing existingWindows: [CGWindowID: WindowSource]) async throws
        -> [WindowSource]
    {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        let ownBundleIdentifier = Bundle.main.bundleIdentifier

        return content.windows
            .filter { window in
                WindowDiscoveryPolicy.isEligible(
                    WindowDiscoveryCandidate(
                        layer: window.windowLayer,
                        frame: window.frame,
                        title: window.title,
                        hasOwningApplication: window.owningApplication != nil,
                        bundleIdentifier: window.owningApplication?.bundleIdentifier
                    ),
                    excludingBundleIdentifier: ownBundleIdentifier
                )
            }
            .map { window in
                WindowSource(window: window, reusing: existingWindows[window.windowID])
            }
            .sorted(by: areInDisplayOrder)
    }

    static func thumbnail(for source: WindowSource) async throws -> NSImage {
        let filter = SCContentFilter(desktopIndependentWindow: source.window)
        let configuration = SCStreamConfiguration()
        configuration.width = Int(thumbnailSize.width)
        configuration.height = Int(thumbnailSize.height)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = true
        configuration.backgroundColor = thumbnailBackground
        configuration.ignoreShadowsSingleWindow = true
        configuration.ignoreGlobalClipSingleWindow = true

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
        return NSImage(
            cgImage: image,
            size: NSSize(width: image.width, height: image.height)
        )
    }

    private static func areInDisplayOrder(_ first: WindowSource, _ second: WindowSource) -> Bool {
        let firstDescription = "\(first.applicationName) \(first.title)"
        let secondDescription = "\(second.applicationName) \(second.title)"
        return firstDescription.localizedCaseInsensitiveCompare(secondDescription) == .orderedAscending
    }
}
