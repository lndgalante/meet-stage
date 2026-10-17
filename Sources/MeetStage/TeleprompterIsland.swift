import AppKit
import Combine
import SwiftUI

/// How the island looks right now. The controller moves it; `TeleprompterIslandView` draws it.
@MainActor
@Observable
final class IslandChrome {
    /// The layout the content is drawn in. Like `contentMode`, it changes only while the content is hidden.
    var layout: IslandLayout?
    var shape = IslandShapeState(size: .zero, shoulder: 6, bottomRadius: 10)
    var contentMode = IslandMode.compact
    var contentSize = CGSize.zero
    var contentOpacity = 0.0

    init() {}

    /// At rest in `mode`, as between moves.
    init(resting mode: IslandMode, in layout: IslandLayout) {
        self.layout = layout
        shape = mode == .expanded ? .expanded(layout) : .compact(layout)
        contentMode = mode
        contentSize = shape.size
        contentOpacity = 1
    }
}

/// The teleprompter: a black island that grows out of the camera notch, so
/// reading it looks like talking to the audience. It docks on the display with
/// the camera and docks again when displays change; it can't be dragged or
/// resized. It never activates BetterMeets, stays on every Space, and asks
/// macOS to leave it out of screen capture where supported; sharing the
/// BetterMeets window, not the whole screen, keeps it private.
@MainActor
final class TeleprompterController: DemoInputObstruction {
    private enum Presence: Equatable {
        case hidden, compact, expanded
    }

    let chrome = IslandChrome()

    private var panel: IslandPanel?
    private weak var demo: DemoSession?
    private var layout: IslandLayout?
    private var presence = Presence.hidden
    /// Bumped by every move, so the completion of a move a newer one overtook does nothing.
    private var transition = 0
    /// Demo inputs the panel is out of the way of; it comes back after the last one.
    private var ducked = 0
    private var changes: AnyCancellable?
    private var screenObserver: NSObjectProtocol?
    /// Where the panel rests, as last reported to `onDockedChange`.
    private var reported: DockedIsland?

    /// Where the panel rests changed, so the demo notice hangs clear of it again.
    /// Folding away, it reports once the panel is gone.
    var onDockedChange: (() -> Void)?

    /// Shown as far as the presenter is concerned, even while folding away or out of a demo input's way.
    var isVisible: Bool { presence != .hidden }

    /// Where the panel rests while it's shown, for what the demo is doing now, so
    /// the demo notice can hang clear of it even before a morph has caught up.
    /// Out of a demo input's way it's back in a moment, so it still counts.
    var docked: DockedIsland? {
        guard isVisible, let demo, let layout else { return nil }
        return DockedIsland(shape(for: Self.presence(for: demo), in: layout), in: layout)
    }

    func show(demo: DemoSession) {
        self.demo = demo
        if panel == nil { makePanel(for: demo) }
        measure()
        move(to: Self.presence(for: demo))
        reportDocked()
    }

    func hide() {
        move(to: .hidden)
    }

    // MARK: Panel

    private func makePanel(for demo: DemoSession) {
        panel = IslandPanel.make(title: "Teleprompter", rootView: TeleprompterIslandView(demo: demo, chrome: chrome))
        // The panel used to remember where it was dragged; it docks itself now.
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame BetterMeetsTeleprompter")

        // What the demo does, its line and the text size all decide the island's size. The
        // values arrive before they're set, so the island reads them a turn later.
        let prompter = demo.prompter
        changes = demo.$phase.map { _ in () }
            .merge(with: prompter.$line.map { _ in () }, prompter.$fontSize.map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.update() }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.redock() }
        }
    }

    private static func presence(for demo: DemoSession) -> Presence {
        IslandMode.make(phase: demo.phase, line: demo.prompter.line) == .expanded ? .expanded : .compact
    }

    private func update() {
        guard presence != .hidden, let demo else { return }
        measure()
        move(to: Self.presence(for: demo))
        reportDocked()
    }

    private func reportDocked() {
        let docked = docked
        guard docked != reported else { return }
        reported = docked
        onDockedChange?()
    }

    /// Measures the display with the camera at the current text size.
    private func measure() {
        guard let demo, let screen = IslandScreen.camera() else { return }
        let size = demo.prompter.fontSize
        layout = IslandLayout.make(
            screen: IslandScreen(screen), fontSize: size,
            rowHeight: IslandType.rowHeight(IslandType.font(size: size, bold: false)))
    }

    /// Displays changed: docks again at once, finishing any move in its final state.
    private func redock() {
        guard let panel else { return }
        defer { reportDocked() }
        measure()
        transition &+= 1
        guard let layout, presence != .hidden else {
            panel.orderOut(nil)
            chrome.contentOpacity = 0
            return
        }
        rest(presence, in: layout, fadesIn: false)
        panel.alphaValue = 1
    }

    // MARK: Moves

    private func shape(for presence: Presence, in layout: IslandLayout) -> IslandShapeState {
        switch presence {
        case .hidden: .collapsed(layout)
        case .compact: .compact(layout)
        case .expanded: .expanded(layout)
        }
    }

    /// Grows the island out of the notch, morphs it between its sizes, or folds
    /// it back in. While the shape morphs, the frame covers both shapes and the
    /// content is hidden; the frame fits the shape again once it's done.
    private func move(to target: Presence) {
        guard let panel, let layout else { return }
        let onScreen = panel.isVisible || ducked > 0
        let from = onScreen ? chrome.shape : .collapsed(layout)
        let to = shape(for: target, in: layout)
        // Already there, or on the way.
        guard target != presence || from != to else {
            // From 40 points up every text size makes the largest island, so a new
            // size changes only the content. A move under way, with its content
            // hidden, rests in the newest layout itself.
            if target == .expanded, chrome.contentOpacity > 0, chrome.layout != layout { restyle(target) }
            return
        }
        transition &+= 1
        let id = transition
        presence = target
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        // Without a notch there's nothing to grow out of or fold into, so the island fades as well.
        let fades = layout.notch == nil
        let current = onScreen ? panel.frame.size : from.size
        panel.setFrame(layout.frame(for: current.covering(to.size)), display: true)

        if target == .hidden {
            fold(panel, into: to, fades: fades || reduceMotion, animates: !reduceMotion, id: id)
            return
        }
        if !onScreen {
            chrome.shape = from
            chrome.contentOpacity = 0
            if reduceMotion {
                rest(target, in: layout, fadesIn: false)
                fadePanel(panel, from: 0)
                return
            }
            panel.alphaValue = fades ? 0 : 1
            if ducked == 0 { panel.orderFrontRegardless() }
            // Draws the notch-sized shape before it grows.
            panel.contentView?.layoutSubtreeIfNeeded()
        } else {
            if panel.alphaValue < 1 { fadePanel(panel, from: nil) }
            if reduceMotion {
                chrome.contentOpacity = 0
                rest(target, in: layout, fadesIn: true)
                return
            }
            withAnimation(.easeIn(duration: 0.12)) { chrome.contentOpacity = 0 }
        }
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.transition == id else { return }
            if fades, !onScreen { self.fadePanel(panel, from: nil, duration: 0.4) }
            withAnimation(.smooth(duration: 0.4).delay(0.08), completionCriteria: .logicallyComplete) {
                self.chrome.shape = to
            } completion: { [weak self] in
                guard let self, self.transition == id else { return }
                self.rest(target, in: self.layout ?? layout, fadesIn: true)
            }
        }
    }

    /// Hides the content and brings it back in the current layout, for a new
    /// text size that leaves the island's shape as it is.
    private func restyle(_ target: Presence) {
        transition &+= 1
        let id = transition
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            chrome.contentOpacity = 0
            if let layout { rest(target, in: layout, fadesIn: true) }
            return
        }
        withAnimation(.easeIn(duration: 0.12), completionCriteria: .logicallyComplete) {
            chrome.contentOpacity = 0
        } completion: { [weak self] in
            guard let self, self.transition == id, let layout = self.layout else { return }
            self.rest(target, in: layout, fadesIn: true)
        }
    }

    /// Hides the content, then folds the shape into the notch, or fades it, and orders the panel out.
    private func fold(_ panel: NSPanel, into collapsed: IslandShapeState, fades: Bool, animates: Bool, id: Int) {
        let finish = { [weak self] in
            guard let self, self.transition == id else { return }
            panel.orderOut(nil)
            self.chrome.shape = collapsed
            self.chrome.contentOpacity = 0
            self.reportDocked()
        }
        if fades {
            Task { @MainActor in
                await NSAnimationContext.runAnimationGroup { context in
                    context.duration = animates ? 0.38 : 0.15
                    panel.animator().alphaValue = 0
                }
                if !animates { finish() }
            }
        }
        guard animates else { return }
        withAnimation(.easeIn(duration: 0.12)) { chrome.contentOpacity = 0 }
        withAnimation(.smooth(duration: 0.3).delay(0.08), completionCriteria: .logicallyComplete) {
            chrome.shape = collapsed
        } completion: {
            finish()
        }
    }

    /// Fades the panel in, from `alpha` when given, else from where it is.
    private func fadePanel(_ panel: NSPanel, from alpha: CGFloat?, duration: TimeInterval = 0.2) {
        if let alpha { panel.alphaValue = alpha }
        if !panel.isVisible, ducked == 0 { panel.orderFrontRegardless() }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            panel.animator().alphaValue = 1
        }
    }

    /// The island at rest: the frame fits the shape, and the content for the mode shows.
    private func rest(_ target: Presence, in layout: IslandLayout, fadesIn: Bool) {
        guard let panel else { return }
        let shape = shape(for: target, in: layout)
        panel.setFrame(layout.frame(for: shape.size), display: true)
        chrome.shape = shape
        chrome.layout = layout
        chrome.contentMode = target == .expanded ? .expanded : .compact
        chrome.contentSize = shape.size
        withAnimation(fadesIn ? .easeOut(duration: 0.2) : nil) { chrome.contentOpacity = 1 }
    }

    // MARK: Demo input

    /// Orders the panel out while a demo's real click or scroll lands under it,
    /// then fades it back. Overlapping inputs nest, and the panel never toggles
    /// `ignoresMouseEvents`, which would let the presenter's own clicks through.
    func stepAside(at point: CGPoint) async -> (@MainActor () -> Void)? {
        guard let panel, panel.isVisible || ducked > 0, let primary = NSScreen.screens.first else { return nil }
        let location = IslandLayout.appKitPoint(point, primaryMaxY: primary.frame.maxY)
        guard panel.frame.insetBy(dx: -8, dy: -8).contains(location) else { return nil }
        ducked += 1
        panel.orderOut(nil)
        // Gives the window server time to drop the panel before the hit test.
        try? await Task.sleep(for: .milliseconds(32))
        return { [weak self] in
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                guard let self else { return }
                self.ducked -= 1
                guard self.ducked == 0, self.isVisible, let panel = self.panel else { return }
                let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                panel.alphaValue = reduceMotion ? 1 : 0
                panel.orderFrontRegardless()
                guard !reduceMotion else { return }
                await NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    panel.animator().alphaValue = 1
                }
            }
        }
    }
}
