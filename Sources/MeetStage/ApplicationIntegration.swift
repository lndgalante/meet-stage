import AppKit

// Keep the stage identity stable so saved window-sharing choices still resolve.
enum BetterMeetsWindowID {
    static let stage = NSUserInterfaceItemIdentifier("BetterMeets.stage")
    static let stageActions = NSUserInterfaceItemIdentifier("BetterMeets.stageActions")
}

@MainActor
final class BetterMeetsWindowState: ObservableObject {
    static let shared = BetterMeetsWindowState()
    @Published var stageOnly = false
    private init() {}

    func toggleStageOnly() { stageOnly.toggle() }

}

@MainActor
enum BetterMeetsWindowActions {
    static var stageWindow: NSWindow? {
        NSApp.windows.first { $0.identifier == BetterMeetsWindowID.stage }
    }

    static func showStage() {
        guard let window = stageWindow else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    static func minimizeStage() { stageWindow?.miniaturize(nil) }
    static func toggleStageFullScreen() { stageWindow?.toggleFullScreen(nil) }

    static func showStageActions() {
        guard let panel = NSApp.windows.first(where: { $0.identifier == BetterMeetsWindowID.stageActions }) else {
            return
        }
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    static func openHelp() {
        guard let url = URL(string: "https://github.com/lndgalante/meet-stage#readme") else { return }
        NSWorkspace.shared.open(url)
    }
}

@MainActor
final class BetterMeetsAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        BetterMeetsWindowActions.showStage()
        return true
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: String(localized: "Show BetterMeets"), action: #selector(showStage), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: String(localized: "Show Controls"), action: #selector(showControls), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        let stop = menu.addItem(
            withTitle: String(localized: "Stop Capture"), action: #selector(stopCapture), keyEquivalent: "")
        stop.target = self
        stop.isEnabled = CaptureManager.shared.canStopCapture
        return menu
    }

    @objc private func showStage() { BetterMeetsWindowActions.showStage() }
    @objc private func showControls() {
        BetterMeetsWindowState.shared.stageOnly = false
        BetterMeetsWindowActions.showStage()
    }
    @objc private func stopCapture() { CaptureManager.shared.stopCapture() }
}
