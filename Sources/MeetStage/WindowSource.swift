import AppKit
import ScreenCaptureKit

struct WindowSource: Identifiable {
    let id: CGWindowID
    let window: SCWindow
    let title: String
    let applicationName: String
    let bundleIdentifier: String
    var thumbnail: NSImage?
    var applicationIcon: NSImage?

    init(window: SCWindow) {
        id = window.windowID
        self.window = window
        title = window.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Untitled Window"
        applicationName = window.owningApplication?.applicationName ?? "Unknown Application"
        bundleIdentifier = window.owningApplication?.bundleIdentifier ?? ""

        if !bundleIdentifier.isEmpty,
           let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            applicationIcon = NSWorkspace.shared.icon(forFile: applicationURL.path)
        } else {
            applicationIcon = nil
        }
    }
}

enum CaptureState: Equatable {
    case idle
    case loading
    case switching
    case capturing
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
        case .failed:
            return "Needs attention"
        }
    }
}
