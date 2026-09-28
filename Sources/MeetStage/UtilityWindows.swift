import AppKit
import SwiftUI

@MainActor
enum UtilityWindows {
    private static var settings: NSWindowController?
    private static var guide: NSWindowController?

    static func showSettings(manager: CaptureManager, tab: SettingsTab? = nil) {
        if let tab {
            UserDefaults.standard.set(tab.rawValue, forKey: SettingsTab.storageKey)
        }
        if settings == nil {
            settings = makeWindow(
                title: "BetterMeets Settings",
                identifier: "BetterMeets.settings",
                size: CGSize(width: 700, height: 440),
                content: BetterMeetsSettingsView(manager: manager)
            )
        }
        settings?.showWindow(nil)
        NSApp.activate()
    }

    static func showGuide() {
        if guide == nil {
            guide = makeWindow(
                title: "Present with BetterMeets",
                identifier: "BetterMeets.guide",
                size: CGSize(width: 440, height: 350),
                resizable: false,
                content: PresentationGuideView()
            )
        }
        guide?.showWindow(nil)
        NSApp.activate()
    }

    private static func makeWindow<Content: View>(
        title: String, identifier: String, size: CGSize, resizable: Bool = true, content: Content
    ) -> NSWindowController {
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: resizable ? [.titled, .closable, .miniaturizable, .resizable] : [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = title
        window.identifier = NSUserInterfaceItemIdentifier(identifier)
        window.isReleasedWhenClosed = false
        window.contentMinSize = size
        let host = NSHostingView(rootView: content)
        host.sizingOptions = []
        window.contentView = host
        window.setContentSize(size)
        window.center()
        if resizable { window.setFrameAutosaveName(identifier) }
        return NSWindowController(window: window)
    }
}

struct PresentationGuideView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("One window for your whole presentation")
                .font(.title2.weight(.semibold))
            SharingSteps()
            Text(
                "Controls are part of the BetterMeets window. Showing them again makes them visible in that window share."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            Text("Use the floating source tools to pause or resume. ⌃⌘S or Escape restores the workspace controls.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct SharingSteps: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Choose a source window in the sidebar.", systemImage: "1.circle")
            Label("Share BetterMeets in your meeting app.", systemImage: "2.circle")
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
    }
}
