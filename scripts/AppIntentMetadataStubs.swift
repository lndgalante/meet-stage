// Packaging-only declarations used while extracting App Intents metadata.
//
// SwiftPM doesn't run Xcode's ExtractAppIntentsMetadata build phase. Compiling
// BetterMeetsIntents.swift with these no-op collaborators lets the official
// compiler extract its static intent constants without rebuilding the app.

@MainActor
enum BetterMeetsWindowActions {
    static func showController() {}
    static func showStage() {}
}

@MainActor
final class CaptureManager {
    static let shared = CaptureManager()

    func stopCapture() {}
    func toggleAutoPresentation() {}
}
