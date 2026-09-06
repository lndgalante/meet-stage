import Foundation

struct SourceSelectionGuidance {
    enum Status { case ready, busy, live, paused, warning }

    let title: String
    let hint: String
    let status: Status

    var message: String { "\(title). \(hint)" }

    init(
        state: CaptureState,
        selectedApplication: String?,
        pendingApplication: String?,
        suggestedApplication: String?,
        shortcut: String?
    ) {
        switch state {
        case .permissionRequired:
            title = String(localized: "Screen access needed")
            hint = String(localized: "Already allowed? Restart")
            status = .warning
        case .loading:
            title = String(localized: "Looking for app windows…")
            hint = String(localized: "Open an app to get started")
            status = .busy
        case .switching:
            title =
                pendingApplication.map { String(localized: "Preparing \($0)…") }
                ?? String(localized: "Preparing the stage…")
            hint = String(localized: "Switching windows")
            status = .busy
        case .paused:
            title =
                selectedApplication.map { String(localized: "\($0) paused") }
                ?? String(localized: "Stage paused")
            hint = String(localized: "Click again to resume")
            status = .paused
        case .capturing:
            title =
                selectedApplication.map { String(localized: "\($0) on stage") }
                ?? String(localized: "Showing on stage")
            hint = String(localized: "Click again to pause")
            status = .live
        case .failed:
            title = String(localized: "Window unavailable")
            hint = String(localized: "Choose an app to try again")
            status = .warning
        case .idle:
            title =
                suggestedApplication == nil
                ? String(localized: "No app windows open") : String(localized: "Choose a window")
            if let suggestedApplication, let shortcut {
                hint = String(localized: "Try \(suggestedApplication) · \(shortcut)")
            } else if suggestedApplication != nil {
                hint = String(localized: "Click a preview to start")
            } else {
                hint = String(localized: "Open an app to get started")
            }
            status = .ready
        }
    }
}
