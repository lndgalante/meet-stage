import AppKit
import ScreenCaptureKit

struct WindowSource: Identifiable {
    let id: CGWindowID
    let window: SCWindow
    let title: String
    let applicationName: String
    let bundleIdentifier: String
    let processIdentifier: pid_t
    var thumbnail: NSImage?
    var applicationIcon: NSImage?

    init(window: SCWindow) {
        id = window.windowID
        self.window = window
        title = window.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Untitled Window"
        applicationName = window.owningApplication?.applicationName ?? "Unknown Application"
        bundleIdentifier = window.owningApplication?.bundleIdentifier ?? ""
        processIdentifier = window.owningApplication?.processID ?? 0

        if !bundleIdentifier.isEmpty,
           let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            applicationIcon = NSWorkspace.shared.icon(forFile: applicationURL.path)
        } else {
            applicationIcon = nil
        }
    }
}

struct PinnedWindow: Codable, Hashable {
    let bundleIdentifier: String
    let applicationName: String
    let title: String

    init(source: WindowSource) {
        bundleIdentifier = source.bundleIdentifier
        applicationName = source.applicationName
        title = source.title
    }

    func matches(_ source: WindowSource) -> Bool {
        let sameApplication = bundleIdentifier.isEmpty
            ? applicationName == source.applicationName
            : bundleIdentifier == source.bundleIdentifier
        return sameApplication && title == source.title
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
    case permissionRequired
    case failed(String)

    var label: String {
        switch self {
        case .idle:
            return "Choose a window"
        case .loading:
            return "Finding windows…"
        case .switching:
            return "Switching…"
        case .capturing:
            return "Live"
        case .permissionRequired:
            return "Permission needed"
        case .failed:
            return "Needs attention"
        }
    }
}
