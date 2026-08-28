import Foundation
import OSLog

/// Centralized, privacy-aware diagnostics for failures that are not presented
/// directly in the UI. Categories make production reports easy to filter in
/// Console without scattering subsystem strings throughout the app.
enum AppLog {
    private static let subsystem =
        Bundle.main.bundleIdentifier ?? "dev.poc.meetstage.v2"

    static let application = Logger(subsystem: subsystem, category: "application")
    static let capture = Logger(subsystem: subsystem, category: "capture")
    static let preferences = Logger(subsystem: subsystem, category: "preferences")
    static let shortcuts = Logger(subsystem: subsystem, category: "shortcuts")
    static let demoMode = Logger(subsystem: subsystem, category: "demoMode")
}
