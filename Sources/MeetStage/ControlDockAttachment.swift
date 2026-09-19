import AppKit

@MainActor
final class ControlDockAttachment: WindowDragHandling {
    static let preferenceKey = "BetterMeets.ControllerDockSide"

    private weak var window: NSWindow?
    private let defaults: UserDefaults
    private let resolveTargets: @MainActor (CGSize) -> [DockSnapTarget]
    private var attachedSide: DockSide?
    private var dragTargets: [DockSnapTarget] = []
    private var bypassSnap = false
    private var trackingTask: Task<Void, Never>?

    init(
        window: NSWindow,
        defaults: UserDefaults = .standard,
        resolveTargets: @escaping @MainActor (CGSize) -> [DockSnapTarget] = ControlDockAttachment.currentTargets
    ) {
        self.window = window
        self.defaults = defaults
        self.resolveTargets = resolveTargets
    }

    deinit {
        trackingTask?.cancel()
    }

    func restore() {
        attachedSide = defaults.string(forKey: Self.preferenceKey).flatMap(DockSide.init(rawValue:))
        followDock()
        startTracking()
    }

    @discardableResult
    func attach() -> Bool {
        guard let window, let target = resolveTargets(window.frame.size).first else { return false }
        attachedSide = target.side
        window.setFrameOrigin(target.frame.origin)
        save()
        startTracking()
        return true
    }

    func beginDragging() {
        trackingTask?.cancel()
        trackingTask = nil
        attachedSide = nil
        bypassSnap = false
        // AX queries happen once at pickup, never in the pointer's hot path.
        dragTargets = window.map { resolveTargets($0.frame.size) } ?? []
    }

    func dragOrigin(for proposedOrigin: NSPoint, bypassSnap: Bool) -> NSPoint {
        self.bypassSnap = bypassSnap
        return proposedOrigin
    }

    func endDragging() {
        if let window, !bypassSnap,
            let target = DockSnap.target(for: window.frame.origin, among: dragTargets)
        {
            attachedSide = target.side
            window.setFrameOrigin(target.frame.origin)
        }
        dragTargets = []
        save()
        startTracking()
    }

    private func startTracking() {
        trackingTask?.cancel()
        trackingTask = nil
        guard attachedSide != nil else { return }
        trackingTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(500))
                } catch {
                    return
                }
                guard let self, let window = self.window else { return }
                if window.isVisible && !window.isMiniaturized { self.followDock() }
            }
        }
    }

    private func followDock() {
        guard let attachedSide, let window,
            let target = resolveTargets(window.frame.size).first(where: { $0.side == attachedSide }),
            window.frame.origin != target.frame.origin
        else { return }
        window.setFrameOrigin(target.frame.origin)
        save()
    }

    private func save() {
        if let attachedSide {
            defaults.set(attachedSide.rawValue, forKey: Self.preferenceKey)
        } else {
            defaults.removeObject(forKey: Self.preferenceKey)
        }
        if let window, !window.frameAutosaveName.isEmpty {
            window.saveFrame(usingName: window.frameAutosaveName)
        }
    }

    private static func currentTargets(size: CGSize) -> [DockSnapTarget] {
        guard let dock = DockFrameResolver.currentFrame(),
            let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: dock.midX, y: dock.midY)) })
        else { return [] }
        return DockSnap.targets(size: size, dock: dock, screen: screen.frame, visibleScreen: screen.visibleFrame)
    }
}
