import AppKit

enum BetterMeetsWindowID {
    static let control = NSUserInterfaceItemIdentifier("BetterMeets.control")
    static let stage = NSUserInterfaceItemIdentifier("BetterMeets.stage")
}

/// Observable window state for command titles and validation. SwiftUI does not
/// otherwise know when AppKit-only actions hide, minimize, or full-screen one
/// of the app's windows.
@MainActor
final class BetterMeetsWindowState: ObservableObject {
    static let shared = BetterMeetsWindowState()

    @Published private(set) var controllerIsVisible = false
    @Published private(set) var stageCanMinimize = false
    @Published private(set) var stageIsFullScreen = false

    private var notificationTokens: [NSObjectProtocol] = []

    private init(center: NotificationCenter = .default) {
        let notifications: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didExitFullScreenNotification,
            NSWindow.willCloseNotification
        ]

        notificationTokens = notifications.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refresh()
                }
            }
        }
    }

    var controllerMenuTitle: String {
        controllerIsVisible
            ? String(localized: "Hide Controller")
            : String(localized: "Show Controller")
    }

    var stageFullScreenMenuTitle: String {
        stageIsFullScreen
            ? String(localized: "Exit Demo Stage Full Screen")
            : String(localized: "Enter Demo Stage Full Screen")
    }

    func refresh() {
        let controller = BetterMeetsWindowActions.controllerWindow
        let stage = BetterMeetsWindowActions.stageWindow
        let stageIsFullScreen = stage?.styleMask.contains(.fullScreen) == true
        update(
            \.controllerIsVisible,
            to: controller?.isVisible == true && controller?.isMiniaturized == false
        )
        update(
            \.stageCanMinimize,
            to: stage?.isVisible == true
                && stage?.isMiniaturized == false
                && !stageIsFullScreen
        )
        update(\.stageIsFullScreen, to: stageIsFullScreen)
    }

    private func update(
        _ property: ReferenceWritableKeyPath<BetterMeetsWindowState, Bool>,
        to newValue: Bool
    ) {
        guard self[keyPath: property] != newValue else { return }
        self[keyPath: property] = newValue
    }
}

@MainActor
enum BetterMeetsWindowActions {
    static func showController() {
        showWindow(identifier: BetterMeetsWindowID.control)
    }

    static func toggleController() {
        guard let controllerWindow else {
            NSSound.beep()
            return
        }
        if controllerWindow.isVisible, !controllerWindow.isMiniaturized {
            controllerWindow.orderOut(nil)
        } else {
            showController()
        }
        BetterMeetsWindowState.shared.refresh()
    }

    static func hideController() {
        controllerWindow?.orderOut(nil)
        BetterMeetsWindowState.shared.refresh()
    }

    static func minimizeController() {
        controllerWindow?.miniaturize(nil)
        BetterMeetsWindowState.shared.refresh()
    }

    static func showStage() {
        showWindow(identifier: BetterMeetsWindowID.stage)
    }

    static func minimizeStage() {
        stageWindow?.miniaturize(nil)
        BetterMeetsWindowState.shared.refresh()
    }

    static func closeStage() {
        stageWindow?.performClose(nil)
        BetterMeetsWindowState.shared.refresh()
    }

    static func toggleStageFullScreen() {
        guard let stageWindow else { return }
        stageWindow.makeKeyAndOrderFront(nil)
        stageWindow.toggleFullScreen(nil)
        BetterMeetsWindowState.shared.refresh()
    }

    static func openHelp() {
        guard let url = URL(string: "https://github.com/lndgalante/meet-stage#readme") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    static var stageWindow: NSWindow? {
        window(identifier: BetterMeetsWindowID.stage)
    }

    static var controllerWindow: NSWindow? {
        window(identifier: BetterMeetsWindowID.control)
    }

    private static func showWindow(identifier: NSUserInterfaceItemIdentifier) {
        guard let window = window(identifier: identifier) else {
            NSSound.beep()
            return
        }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        BetterMeetsWindowState.shared.refresh()
    }

    private static func window(identifier: NSUserInterfaceItemIdentifier) -> NSWindow? {
        NSApp.windows.first { $0.identifier == identifier }
    }
}

@MainActor
final class BetterMeetsAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(
            withTitle: String(localized: "Show Controller"),
            action: #selector(showController),
            keyEquivalent: ""
        )
        menu.addItem(
            withTitle: String(localized: "Show Demo Stage"),
            action: #selector(showStage),
            keyEquivalent: ""
        )
        menu.addItem(.separator())

        let stopItem = NSMenuItem(
            title: String(localized: "Stop Capture"),
            action: #selector(stopCapture),
            keyEquivalent: ""
        )
        stopItem.isEnabled = CaptureManager.shared.isCapturing
        menu.addItem(stopItem)
        return menu
    }

    @objc private func showController() {
        BetterMeetsWindowActions.showController()
    }

    @objc private func showStage() {
        BetterMeetsWindowActions.showStage()
    }

    @objc private func stopCapture() {
        CaptureManager.shared.stopCapture()
    }
}

@MainActor
final class StageWindowActionTarget: NSObject {
    weak var window: NSWindow?

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(
            withTitle: String(localized: "Show Controller"),
            action: #selector(showController),
            keyEquivalent: ""
        ).target = self
        menu.addItem(.separator())

        let minimizeItem = menu.addItem(
            withTitle: String(localized: "Minimize Demo Stage"),
            action: #selector(minimize),
            keyEquivalent: ""
        )
        minimizeItem.target = self

        let fullScreenTitle =
            window?.styleMask.contains(.fullScreen) == true
            ? String(localized: "Exit Full Screen")
            : String(localized: "Enter Full Screen")
        let fullScreenItem = menu.addItem(
            withTitle: fullScreenTitle,
            action: #selector(toggleFullScreen),
            keyEquivalent: ""
        )
        fullScreenItem.target = self

        let closeItem = menu.addItem(
            withTitle: String(localized: "Close Demo Stage"),
            action: #selector(close),
            keyEquivalent: ""
        )
        closeItem.target = self
        return menu
    }

    @objc private func showController() {
        BetterMeetsWindowActions.showController()
    }

    @objc private func minimize() {
        window?.miniaturize(nil)
    }

    @objc private func toggleFullScreen() {
        window?.toggleFullScreen(nil)
    }

    @objc private func close() {
        window?.performClose(nil)
    }
}
