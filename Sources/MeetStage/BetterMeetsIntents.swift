import AppIntents

struct ShowControllerIntent: AppIntent {
    static let title: LocalizedStringResource = "Show BetterMeets Controller"
    static let description = IntentDescription("Brings the BetterMeets controller to the front.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        BetterMeetsWindowActions.showController()
        return .result()
    }
}

struct ShowDemoStageIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Demo Stage"
    static let description = IntentDescription("Brings the shareable Demo Stage to the front.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        BetterMeetsWindowActions.showStage()
        return .result()
    }
}

struct StopCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop BetterMeets Capture"
    static let description = IntentDescription("Stops sharing the current source window.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        CaptureManager.shared.stopCapture()
        return .result()
    }
}

struct ToggleAutoPolishIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Auto Polish"
    static let description = IntentDescription("Turns BetterMeets Auto Polish on or off.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        CaptureManager.shared.toggleAutoPresentation()
        return .result()
    }
}

struct BetterMeetsAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ShowControllerIntent(),
            phrases: ["Show the controller in \(.applicationName)"],
            shortTitle: "Show Controller",
            systemImageName: "switch.2"
        )
        AppShortcut(
            intent: ShowDemoStageIntent(),
            phrases: ["Show the Demo Stage in \(.applicationName)"],
            shortTitle: "Show Demo Stage",
            systemImageName: "rectangle.on.rectangle"
        )
        AppShortcut(
            intent: StopCaptureIntent(),
            phrases: ["Stop sharing in \(.applicationName)"],
            shortTitle: "Stop Capture",
            systemImageName: "stop.fill"
        )
        AppShortcut(
            intent: ToggleAutoPolishIntent(),
            phrases: ["Toggle Auto Polish in \(.applicationName)"],
            shortTitle: "Toggle Auto Polish",
            systemImageName: "wand.and.sparkles"
        )
    }
}
