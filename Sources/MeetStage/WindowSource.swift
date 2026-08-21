import AppKit
import ScreenCaptureKit

/// A shareable ScreenCaptureKit window plus presentation data for the picker.
struct WindowSource: Identifiable {
    let id: CGWindowID
    let window: SCWindow
    let title: String
    let applicationName: String
    let bundleIdentifier: String
    let processIdentifier: pid_t
    var thumbnail: NSImage?
    var applicationIcon: NSImage?

    init(window: SCWindow, reusing presentation: WindowSource? = nil) {
        id = window.windowID
        self.window = window
        title = window.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Untitled Window"
        applicationName = window.owningApplication?.applicationName ?? "Unknown Application"
        bundleIdentifier = window.owningApplication?.bundleIdentifier ?? ""
        processIdentifier = window.owningApplication?.processID ?? 0

        let matchesExistingWindow =
            presentation?.id == id
            && presentation?.title == title
            && presentation?.bundleIdentifier == bundleIdentifier
        thumbnail = matchesExistingWindow ? presentation?.thumbnail : nil

        if presentation?.bundleIdentifier == bundleIdentifier,
            presentation?.applicationName == applicationName
        {
            applicationIcon = presentation?.applicationIcon
        } else if !bundleIdentifier.isEmpty,
            let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        {
            applicationIcon = NSWorkspace.shared.icon(forFile: applicationURL.path)
        } else {
            applicationIcon = nil
        }
    }
}

/// A persisted window identity that deliberately excludes transient window IDs.
struct PinnedWindow: Codable, Hashable {
    let bundleIdentifier: String
    let applicationName: String
    let title: String

    init(bundleIdentifier: String, applicationName: String, title: String) {
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.title = title
    }

    init(source: WindowSource) {
        self.init(
            bundleIdentifier: source.bundleIdentifier,
            applicationName: source.applicationName,
            title: source.title
        )
    }

    func matches(_ candidate: PinnedWindow) -> Bool {
        let sameApplication =
            bundleIdentifier.isEmpty
            ? applicationName == candidate.applicationName
            : bundleIdentifier == candidate.bundleIdentifier
        return sameApplication && title == candidate.title
    }

    var description: String {
        "\(applicationName) — \(title)"
    }
}

struct ShortcutPin: Codable, Equatable {
    let slot: Int
    let window: PinnedWindow
}

enum CaptureState: Equatable {
    case idle
    case loading
    case switching
    case capturing
    case paused
    case permissionRequired
    case failed(String)
}
