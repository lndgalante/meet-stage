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

    nonisolated static func thumbnailImage(for window: SCWindow) async throws -> CGImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        let backgroundColor = CGColor(gray: 0, alpha: 1)
        defer { withExtendedLifetime(backgroundColor) {} }
        configuration.width = 480
        configuration.height = 270
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = true
        configuration.backgroundColor = backgroundColor
        configuration.ignoreShadowsSingleWindow = true
        configuration.ignoreGlobalClipSingleWindow = true

        return try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
    }

    private static func areInDisplayOrder(_ first: WindowSource, _ second: WindowSource) -> Bool {
        let firstDescription = "\(first.applicationName) \(first.title)"
        let secondDescription = "\(second.applicationName) \(second.title)"
        return firstDescription.localizedCaseInsensitiveCompare(secondDescription) == .orderedAscending
    }
}
