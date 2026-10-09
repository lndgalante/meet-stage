import AppKit
import SwiftUI

struct WindowConfigurator: NSViewRepresentable {
    /// Stage Only hides the window's buttons with the rest of the controls.
    var hidesWindowButtons = false

    func makeNSView(context: Context) -> WorkspaceWindowProbe { WorkspaceWindowProbe() }

    func updateNSView(_ nsView: WorkspaceWindowProbe, context: Context) {
        nsView.windowButtons.isHidden = hidesWindowButtons
    }

    @MainActor
    static func configure(_ window: NSWindow) {
        window.identifier = BetterMeetsWindowID.stage
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = false
        window.contentMinSize = WorkspaceMetrics.minimumSize
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.setFrameAutosaveName("BetterMeets.Workspace")
    }
}

final class WorkspaceWindowProbe: NSView {
    let windowButtons = WindowButtonsPlacement()

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else {
            windowButtons.detach()
            return
        }
        WindowConfigurator.configure(window)
        windowButtons.attach(to: window)
    }
}

/// Keeps the window's close, minimize and zoom buttons centered on
/// `WorkspaceMetrics.windowButtonsCenter`, inside the rail, instead of in the
/// hidden title bar's corner. AppKit has no API for this, so it moves the title
/// bar view that holds them, narrowed to the buttons so it never covers the
/// header's controls, and lays the buttons out in it the way AppKit does. AppKit
/// lays them out again on resize and after full screen, so this puts them back
/// whenever they move.
@MainActor
final class WindowButtonsPlacement {
    var isHidden = false {
        didSet { if isHidden != oldValue { place() } }
    }

    private weak var window: NSWindow?
    private var observers: [NSObjectProtocol] = []
    /// AppKit animates the buttons into and out of the menu bar; moving them
    /// mid-way strands them, so they stay hidden until it's done.
    private var isChangingFullScreen = false
    private var fullScreenChanges = 0
    /// It puts the buttons back right away, before the window draws, and again on the
    /// next turn of the run loop: AppKit ignores a move made while its own layout
    /// pass is moving that button.
    private var isScheduled = false
    /// Moving the buttons posts the notifications that call this again.
    private var isPlacing = false
    /// AppKit's own button size, spacing and title bar height, read before anything moved them.
    private var layout: (size: CGSize, pitch: CGFloat, height: CGFloat)?

    func attach(to window: NSWindow) {
        guard window !== self.window, let container = container(in: window) else { return }
        detach()
        self.window = window
        let views = [container] + buttons(in: window)
        views.forEach { $0.postsFrameChangedNotifications = true }
        let watched: [(Notification.Name, AnyObject, Bool?)] =
            views.map { (NSView.frameDidChangeNotification, $0, nil) } + [
                (NSWindow.didResizeNotification, window, nil),
                (NSWindow.willEnterFullScreenNotification, window, true),
                (NSWindow.didEnterFullScreenNotification, window, false),
                (NSWindow.willExitFullScreenNotification, window, true),
                (NSWindow.didExitFullScreenNotification, window, false),
            ]
        observers = watched.map { name, object, changing in
            NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    if let changing { self?.fullScreenChange(started: changing) }
                    self?.place()
                    self?.schedulePlacement()
                }
            }
        }
        place()
    }

    func detach() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        window = nil
    }

    private func container(in window: NSWindow) -> NSView? {
        window.standardWindowButton(.closeButton)?.superview?.superview
    }

    private func buttons(in window: NSWindow) -> [NSView] {
        [.closeButton, .miniaturizeButton, .zoomButton].compactMap { window.standardWindowButton($0) }
    }

    private func fullScreenChange(started: Bool) {
        isChangingFullScreen = started
        guard started else { return }
        fullScreenChanges += 1
        let change = fullScreenChanges
        // A change that fails posts no notification we can see, so don't wait for one forever.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isChangingFullScreen, self.fullScreenChanges == change else { return }
                self.isChangingFullScreen = false
                self.place()
            }
        }
    }

    private func schedulePlacement() {
        guard !isScheduled else { return }
        isScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.isScheduled = false
                self?.place()
            }
        }
    }

    private func place() {
        guard !isPlacing, let window, let container = container(in: window) else { return }
        isPlacing = true
        defer { isPlacing = false }
        container.isHidden = isHidden
        container.alphaValue = isChangingFullScreen ? 0 : 1
        let buttons = buttons(in: window)
        // In full screen the buttons live in the menu bar's own window.
        let inRail = !isChangingFullScreen && container.window === window && !window.styleMask.contains(.fullScreen)
        // Beside the buttons AppKit draws the window's top-edge highlight, which reads as a band inside the rail.
        for view in container.subviews where view !== buttons.first?.superview {
            view.isHidden = inRail
        }
        guard inRail, let frame = container.superview, buttons.count == 3 else { return }
        if layout == nil {
            let size = buttons[0].frame.size
            let pitch = buttons[1].frame.minX - buttons[0].frame.minX
            let height = container.frame.height
            guard pitch > size.width, height >= size.height else { return }
            layout = (size, pitch, height)
        }
        guard let (size, pitch, height) = layout else { return }
        let margin = ((height - size.height) / 2).rounded()
        let width = 2 * margin + 2 * pitch + size.width
        let center = WorkspaceMetrics.windowButtonsCenter
        let target = NSRect(
            x: (center.x - width / 2).rounded(),
            y: (frame.isFlipped ? center.y - height / 2 : frame.bounds.height - center.y - height / 2).rounded(),
            width: width, height: height)
        if container.frame != target { container.frame = target }
        for (index, button) in buttons.enumerated() {
            let origin = NSPoint(x: margin + CGFloat(index) * pitch, y: margin)
            if button.frame.origin != origin { button.setFrameOrigin(origin) }
        }
    }
}

/// Empty space that acts like a title bar, since the window has none: dragging
/// moves the window, and a double-click does what System Settings › Desktop &
/// Dock asks of a title bar.
struct WindowDragArea: NSViewRepresentable {
    /// Shown on hover, for a title the drag area covers.
    var help: String?

    func makeNSView(context: Context) -> NSView { WindowDragView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.toolTip = help
    }
}

private final class WindowDragView: NSView {
    /// `performDrag` moves the window, so AppKit shouldn't try as well.
    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        if event.clickCount == 2 {
            TitleBarDoubleClick(setting: UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick"))
                .perform(on: window)
        } else {
            window.performDrag(with: event)
        }
    }

    /// Kept from the hidden title bar, which would act on the same double-click again.
    override func mouseUp(with event: NSEvent) {}
}

/// What a double-click on a title bar does, as chosen in System Settings › Desktop & Dock.
enum TitleBarDoubleClick: Equatable {
    case zoom, fill, minimize, nothing

    init(setting: String?) {
        switch setting {
        case "Fill": self = .fill
        case "Minimize": self = .minimize
        case "None": self = .nothing
        default: self = .zoom
        }
    }

    @MainActor
    func perform(on window: NSWindow) {
        switch self {
        case .zoom: window.zoom(nil)
        case .minimize: window.miniaturize(nil)
        case .nothing: break
        case .fill:
            // Fill has no public API; the title bar sends AppKit's own action.
            let fill = NSSelectorFromString("_zoomFill:")
            if window.responds(to: fill) {
                window.perform(fill, with: nil)
            } else {
                window.zoom(nil)
            }
        }
    }
}
