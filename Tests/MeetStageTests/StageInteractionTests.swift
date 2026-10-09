import AppKit
import SwiftUI
import Testing
@testable import MeetStage

@Suite("Unified workspace", .serialized)
struct StageInteractionTests {
    @Test("Landscape and portrait sources fit without cropping or stretching")
    func sourceFitsViewport() {
        let viewport = CGSize(width: 960, height: 600)
        #expect(WorkspaceMetrics.stageSize(fitting: viewport, aspectRatio: 16 / 9) == CGSize(width: 960, height: 540))
        #expect(WorkspaceMetrics.stageSize(fitting: viewport, aspectRatio: 0.5) == CGSize(width: 300, height: 600))
        #expect(WorkspaceMetrics.stageSize(fitting: .zero, aspectRatio: 1) == .zero)
        #expect(WorkspaceMetrics.stageSize(fitting: viewport, aspectRatio: .nan) == CGSize(width: 960, height: 600))
    }

    @Test("Window configuration preserves native controls and the user's chosen size")
    @MainActor
    func nativeWindowBehavior() throws {
        let window = NSWindow(
            contentRect: CGRect(x: 100, y: 100, width: 1000, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        WindowConfigurator.configure(window)
        let size = window.frame.size
        WindowConfigurator.configure(window)

        #expect(window.frame.size == size)
        #expect(window.styleMask.contains(.resizable))
        #expect(window.collectionBehavior.contains(.fullScreenPrimary))
        #expect(!window.isMovableByWindowBackground)
        #expect(window.contentAspectRatio == .zero)
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            let button = try #require(window.standardWindowButton(type))
            #expect(!button.isHidden)
        }
        window.setFrameAutosaveName("")
    }

    @Test("The window's buttons sit in the rail, level with the header, and stay there through a resize")
    @MainActor
    func windowButtonsInRail() throws {
        let window = NSWindow(
            contentRect: CGRect(x: 100, y: 100, width: 1000, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        WindowConfigurator.configure(window)
        defer { window.setFrameAutosaveName("") }
        let placement = WindowButtonsPlacement()
        placement.attach(to: window)
        defer { placement.detach() }

        func buttonsCenter() throws -> CGPoint {
            let rects = try [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].map { type in
                let button = try #require(window.standardWindowButton(type))
                return button.convert(button.bounds, to: nil)
            }
            let union = rects.dropFirst().reduce(rects[0]) { $0.union($1) }
            return CGPoint(x: union.midX, y: window.frame.height - union.midY)
        }
        let center = WorkspaceMetrics.windowButtonsCenter
        #expect(try buttonsCenter() == center)
        let container = try #require(window.standardWindowButton(.closeButton)?.superview?.superview)
        // Narrowed to the buttons, so it never covers the header beside the rail.
        #expect(container.frame.maxX <= WorkspaceMetrics.gutter + WorkspaceMetrics.sidebarWidth)

        window.setFrame(CGRect(x: 120, y: 120, width: 820, height: 600), display: true)
        #expect(try buttonsCenter() == center)

        placement.isHidden = true
        #expect(container.isHidden)
        placement.isHidden = false
        #expect(!container.isHidden)
    }

    @Test("A double-click on the drag areas does what System Settings asks of a title bar")
    func titleBarDoubleClick() {
        #expect(TitleBarDoubleClick(setting: nil) == .zoom)
        #expect(TitleBarDoubleClick(setting: "Maximize") == .zoom)
        #expect(TitleBarDoubleClick(setting: "Fill") == .fill)
        #expect(TitleBarDoubleClick(setting: "Minimize") == .minimize)
        #expect(TitleBarDoubleClick(setting: "None") == .nothing)
    }

    @Test("Stage rendering never installs a separate control or action window")
    @MainActor
    func stageRemainsEmbedded() throws {
        let suite = "WorkspaceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = CaptureManager(defaults: defaults)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 800, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let windowsBefore = Set(NSApp.windows.map(ObjectIdentifier.init))
        window.contentView = NSHostingView(rootView: StageView(manager: manager))
        window.contentView?.layoutSubtreeIfNeeded()
        #expect(Set(NSApp.windows.map(ObjectIdentifier.init)) == windowsBefore)
        #expect(window.identifier != BetterMeetsWindowID.stage)
    }

    @Test("Pause and resume cannot start a missing source or interrupt a pending switch")
    @MainActor
    func pauseAvailability() throws {
        let suite = "WorkspacePauseTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = CaptureManager(defaults: defaults)
        for state in [CaptureState.idle, .loading, .paused, .switching, .permissionRequired] {
            manager.state = state
            #expect(!manager.canToggleCapturePause)
            manager.toggleCapturePause()
            #expect(manager.state == state)
        }
    }
}
