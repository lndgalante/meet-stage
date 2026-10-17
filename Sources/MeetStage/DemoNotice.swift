import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Content

/// What the notice over the presenter's app says when a build or test run they
/// started has finished, or needs them, while BetterMeets is in the background.
struct DemoNoticeContent: Equatable {
    enum Kind: Equatable {
        case ready, attention
    }

    var kind: Kind
    /// Beside the camera: Demo ready, Build paused, Test waiting, or Test stopped.
    var badge: String
    var title: String
    var detail: String
    /// The app the demo runs in, whose icon leads the notice.
    var bundleID: String
    /// What VoiceOver says as the notice appears, since the notice never takes focus.
    var announcement: String

    /// What the notice says for `phase`, or nil when the phase isn't worth calling the presenter back for.
    static func make(phase: DemoPhase, demo: RealTimeDemo?, isChecked: Bool) -> DemoNoticeContent? {
        let app = demo?.app.appName ?? ""
        let bundleID = demo?.app.bundleID ?? ""
        func attention(_ badge: String, _ title: String, _ detail: String) -> DemoNoticeContent {
            DemoNoticeContent(
                kind: .attention, badge: badge, title: title, detail: detail, bundleID: bundleID,
                announcement: "\(badge): \(title). \(detail)")
        }
        switch phase {
        case .ready:
            let title = demo?.title ?? "Your demo"
            let count = demo?.steps.count ?? 0
            let steps = count == 1 ? "1 step" : "\(count) steps"
            let status = isChecked ? "Tested" : "Not tested"
            return DemoNoticeContent(
                kind: .ready, badge: "Demo ready", title: title,
                detail: [status, steps, app].filter { !$0.isEmpty }.joined(separator: " · "),
                bundleID: bundleID, announcement: "Demo ready: \(title), \(status.lowercased()), \(steps)")
        case .scoutPaused(let stop) where stop != .user:
            return attention("Build paused", "Your demo build needs you", stop.message)
        case .needsStart(_, .verify):
            let start = demo?.start?.description ?? "The screen where the build started"
            return attention("Test waiting", "Go back to the start to finish the test run", start)
        case .offTrack(.verify, let index, let mismatch):
            return attention("Test stopped", "The test run stopped at step \(index + 1)", mismatch.message)
        default:
            return nil
        }
    }
}

/// Whether the notice shows, worked out without windows: what the phase calls
/// for while BetterMeets is in the background, unless the presenter already put
/// that same notice away.
struct DemoNoticeState: Equatable {
    enum Change: Equatable {
        case none
        /// Shows the notice, or replaces what it says in place.
        case show(DemoNoticeContent)
        case hide
    }

    /// What's on screen, or on its way.
    private(set) var shown: DemoNoticeContent?
    /// What the presenter put away, so it doesn't come back for the same phase.
    private(set) var dismissed: DemoNoticeContent?

    /// Follows `announcement`, what the session's phase calls for, if anything.
    mutating func update(to announcement: DemoNoticeContent?, isActive: Bool) -> Change {
        // Once the phase moves on, the same notice later (a resumed build pausing again) is news.
        if announcement != dismissed { dismissed = nil }
        let target = isActive || announcement == dismissed ? nil : announcement
        guard target != shown else { return .none }
        shown = target
        return target.map(Change.show) ?? .hide
    }

    /// Open BetterMeets, Dismiss, or switching to BetterMeets.
    mutating func presenterDismissed() {
        if let shown { dismissed = shown }
        shown = nil
    }

    /// A new build or test run: whatever it ends in is news again.
    mutating func forgetDismissed() {
        dismissed = nil
    }
}

// MARK: - Layout

/// Where the notice hangs and how wide it is. Like the teleprompter, it grows
/// out of the camera notch, or hangs from the menu bar without one; with the
/// teleprompter on the same display it's a card just below it instead.
struct DemoNoticeLayout: Equatable {
    /// The camera the notice grows out of; nil without one, and for a card.
    var notch: CGRect?
    /// A rounded card under the teleprompter, rather than an island of its own.
    var isCard: Bool
    /// The y the notice hangs from.
    var top: CGFloat
    var midX: CGFloat
    /// The badge's row, beside the camera when there is one.
    var band: CGFloat
    var width: CGFloat
    var scale: CGFloat

    /// From the frame's sides to the content: 12 points inside the body, as in
    /// the teleprompter, so a card's text lines up with the teleprompter's above.
    var inset: CGFloat { isCard ? 12 : 28 }
    /// Below the buttons, about as far as they are from the side.
    static let bottomInset: CGFloat = 14
    /// Room above a card, inside its window, to slide out from under the teleprompter.
    var headroom: CGFloat { isCard ? 8 : 0 }

    static func make(screen: IslandScreen, island: DockedIsland?) -> DemoNoticeLayout {
        let notch = screen.notch
        guard let island, screen.frame.intersects(island.frame) else {
            return DemoNoticeLayout(
                notch: notch, isCard: false, top: screen.islandTop, midX: screen.islandMidX, band: screen.band,
                width: notch.map { min(520, max(440, $0.width + 300)) } ?? 440, scale: screen.scale)
        }
        // As wide as the teleprompter's body at any size, so the two stack and their text lines up.
        return DemoNoticeLayout(
            notch: nil, isCard: true, top: island.frame.minY - 8, midX: island.frame.midX, band: 34,
            width: island.bodyWidth, scale: screen.scale)
    }

    /// At rest, `height` tall: the expanded teleprompter's shoulders and corners, or a card's.
    func shape(height: CGFloat) -> IslandShapeState {
        IslandShapeState(size: CGSize(width: width, height: height), shoulder: isCard ? 0 : 16, bottomRadius: 20)
    }

    /// Where growing starts and folding ends: the notch itself.
    var collapsed: IslandShapeState? {
        notch.map { .notch($0.size) }
    }

    /// How wide the badge may be: up to 8 points short of the camera.
    var badgeWidth: CGFloat {
        guard let notch else { return width - 2 * inset }
        return max(0, (width - notch.width) / 2 - 8 - inset)
    }

    /// The window frame for a shape of `size` hanging from the top, centered, on
    /// whole backing pixels, with a card's headroom above it.
    func frame(for size: CGSize) -> CGRect {
        .hanging(
            CGSize(width: size.width, height: size.height + headroom), from: top + headroom, midX: midX, scale: scale)
    }
}

// MARK: - Controller

/// How the notice looks right now. The controller moves it; `DemoNoticeView` draws it.
@MainActor
@Observable
final class DemoNoticeChrome {
    var content: DemoNoticeContent?
    var layout: DemoNoticeLayout?
    var shape = IslandShapeState(size: .zero, shoulder: 6, bottomRadius: 10)
    var contentOpacity = 0.0
    /// How far a card is still tucked up under the teleprompter.
    var lift: CGFloat = 0

    init() {}

    /// At rest showing `content`.
    init(resting content: DemoNoticeContent, in layout: DemoNoticeLayout) {
        self.content = content
        self.layout = layout
        shape = layout.shape(height: DemoNoticeView.height(of: content, in: layout))
        contentOpacity = 1
    }
}

/// The demo notice: a black island like the teleprompter's, grown out of the
/// camera notch on the display under the pointer, or a card just below the
/// teleprompter. It stays until the presenter acts on it or the session moves
/// on. It never takes focus or activates BetterMeets; only Open BetterMeets
/// does, because the presenter clicked it.
@MainActor
final class DemoNoticeController: DemoInputObstruction {
    private struct Rest: Equatable {
        var content: DemoNoticeContent
        var layout: DemoNoticeLayout
        var height: CGFloat
    }

    let chrome = DemoNoticeChrome()
    /// The presenter clicked Open BetterMeets; the notice is already folding away.
    var onOpen: (() -> Void)?
    /// The presenter put the notice away: Dismiss, or switching to BetterMeets.
    var onDismiss: (() -> Void)?

    /// The teleprompter while it's shown, to hang below.
    private let island: () -> DockedIsland?
    private var panel: IslandPanel?
    /// Where the notice is, or is heading; nil once it's folding away.
    private var resting: Rest?
    /// The display it's on, so it stays there as it changes.
    private var displayID: CGDirectDisplayID?
    /// Bumped by every move, so the completion of a move a newer one overtook does nothing.
    private var transition = 0
    private var observers: [NSObjectProtocol] = []

    init(island: @escaping () -> DockedIsland?) {
        self.island = island
    }

    /// Grows the notice with `content`, or changes what it says in place.
    func show(_ content: DemoNoticeContent) {
        let panel = panel ?? makePanel()
        // It stays on its display while it's up; else it goes where the presenter
        // is looking: the display under the pointer.
        let screens = NSScreen.screens
        let current = resting == nil ? nil : screens.first { $0.cgDirectDisplayID == displayID }
        let pointer = screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
        guard let screen = current ?? pointer ?? NSScreen.main else { return }
        displayID = screen.cgDirectDisplayID
        let layout = DemoNoticeLayout.make(screen: IslandScreen(screen), island: island())
        let rest = Rest(content: content, layout: layout, height: DemoNoticeView.height(of: content, in: layout))
        guard let shown = resting, panel.isVisible else { return grow(rest, in: panel) }
        guard rest != shown else { return }
        if rest.content != shown.content { announce(content, from: panel) }
        if rest.layout == shown.layout { replace(with: rest, in: panel) } else { move(to: rest, in: panel) }
    }

    /// Docks the notice again where it belongs, as when the teleprompter shows, hides or changes size.
    func redock() {
        if let content = resting?.content { show(content) }
    }

    /// Folds the notice back into the notch, or fades it.
    func hide() {
        guard resting != nil, let panel, let layout = chrome.layout else { return }
        resting = nil
        transition &+= 1
        let id = transition
        let finish = { [weak self] in
            guard let self, self.transition == id else { return }
            self.finishHiding(panel)
        }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if let collapsed = layout.collapsed, !reduceMotion {
            withAnimation(.easeIn(duration: 0.12)) { chrome.contentOpacity = 0 }
            withAnimation(.smooth(duration: 0.3).delay(0.08), completionCriteria: .logicallyComplete) {
                chrome.shape = collapsed
            } completion: {
                finish()
            }
            return
        }
        if layout.isCard, !reduceMotion { withAnimation(.smooth(duration: 0.3)) { chrome.lift = layout.headroom } }
        Task { @MainActor in
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                panel.animator().alphaValue = 0
            }
            finish()
        }
    }

    private func finishHiding(_ panel: NSPanel) {
        panel.orderOut(nil)
        panel.alphaValue = 1
        chrome.contentOpacity = 0
        chrome.lift = 0
    }

    // MARK: Panel

    private func makePanel() -> IslandPanel {
        let panel = IslandPanel.make(
            title: "Demo notice",
            rootView: DemoNoticeView(
                chrome: chrome, open: { [weak self] in self?.presenterDismissed(opening: true) },
                dismiss: { [weak self] in self?.presenterDismissed() }))
        self.panel = panel
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated { self?.presenterDismissed() }
            },
            center.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.redock() }
            }
        ]
        return panel
    }

    private func presenterDismissed(opening: Bool = false) {
        guard resting != nil else { return }
        hide()
        if opening { onOpen?() } else { onDismiss?() }
    }

    /// The panel never takes focus, so VoiceOver hears the notice this way.
    private func announce(_ content: DemoNoticeContent, from panel: NSPanel) {
        NSAccessibility.post(
            element: panel, notification: .announcementRequested,
            userInfo: [
                .announcement: content.announcement, .priority: NSAccessibilityPriorityLevel.high.rawValue
            ])
    }

    // MARK: Moves

    /// Grows the notice out of the notch, as the teleprompter does, then fades its
    /// content in. Without a notch, or with Reduce Motion, it fades in instead, a
    /// card sliding out from under the teleprompter.
    private func grow(_ rest: Rest, in panel: IslandPanel) {
        transition &+= 1
        let id = transition
        // Still folding away, it grows back from where it is.
        let folding = panel.isVisible
        resting = rest
        // Announces once the panel is up.
        defer { announce(rest.content, from: panel) }
        let target = rest.layout.shape(height: rest.height)
        chrome.content = rest.content
        chrome.layout = rest.layout
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard let collapsed = rest.layout.collapsed, !reduceMotion else {
            settle(rest, fadesIn: false)
            let slides = rest.layout.isCard && !reduceMotion && !folding
            if !folding { panel.alphaValue = 0 }
            if slides { chrome.lift = rest.layout.headroom }
            panel.orderFrontRegardless()
            // Draws the tucked-up card before it slides.
            panel.contentView?.layoutSubtreeIfNeeded()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                panel.animator().alphaValue = 1
            }
            guard slides else { return }
            Task { @MainActor [weak self] in
                await Task.yield()
                guard let self, self.transition == id else { return }
                withAnimation(.smooth(duration: 0.35)) { self.chrome.lift = 0 }
            }
            return
        }
        let current = folding ? panel.frame.size : .zero
        panel.setFrame(rest.layout.frame(for: current.covering(target.size)), display: false)
        panel.alphaValue = 1
        if !folding {
            chrome.shape = collapsed
            chrome.contentOpacity = 0
            chrome.lift = 0
            panel.orderFrontRegardless()
            // Draws the notch-sized shape before it grows.
            panel.contentView?.layoutSubtreeIfNeeded()
        }
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.transition == id else { return }
            withAnimation(.smooth(duration: 0.4), completionCriteria: .logicallyComplete) {
                self.chrome.shape = target
            } completion: { [weak self] in
                guard let self, self.transition == id else { return }
                self.settle(rest, fadesIn: true)
            }
        }
    }

    /// New content in the same place: the old content fades out, the shape morphs
    /// to the new size if it changed, and the new content fades in.
    private func replace(with rest: Rest, in panel: IslandPanel) {
        transition &+= 1
        let id = transition
        resting = rest
        // A move this overtook may be fading the panel out; this takes over that fade.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 1
        }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            chrome.contentOpacity = 0
            return settle(rest, fadesIn: true)
        }
        let morph = { [weak self] in
            guard let self, self.transition == id else { return }
            self.chrome.content = rest.content
            let target = rest.layout.shape(height: rest.height)
            guard self.chrome.shape != target else { return self.settle(rest, fadesIn: true) }
            panel.setFrame(rest.layout.frame(for: panel.frame.size.covering(target.size)), display: true)
            withAnimation(.smooth(duration: 0.3), completionCriteria: .logicallyComplete) {
                self.chrome.shape = target
            } completion: { [weak self] in
                guard let self, self.transition == id else { return }
                self.settle(rest, fadesIn: true)
            }
        }
        // Still growing, the content hasn't shown yet.
        guard chrome.contentOpacity > 0 else { return morph() }
        withAnimation(.easeIn(duration: 0.12), completionCriteria: .logicallyComplete) {
            chrome.contentOpacity = 0
        } completion: {
            morph()
        }
    }

    /// Somewhere else, as when the teleprompter shows or hides: fades out and back in there.
    private func move(to rest: Rest, in panel: IslandPanel) {
        transition &+= 1
        let id = transition
        resting = rest
        Task { @MainActor [weak self] in
            guard self?.transition == id else { return }
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                panel.animator().alphaValue = 0
            }
            guard let self, self.transition == id else { return }
            self.settle(rest, fadesIn: false)
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                panel.animator().alphaValue = 1
            }
        }
    }

    /// The notice at rest: the frame fits the shape, and the content shows.
    private func settle(_ rest: Rest, fadesIn: Bool) {
        guard let panel else { return }
        let shape = rest.layout.shape(height: rest.height)
        panel.setFrame(rest.layout.frame(for: shape.size), display: true)
        chrome.shape = shape
        chrome.layout = rest.layout
        chrome.content = rest.content
        chrome.lift = 0
        withAnimation(fadesIn ? .easeOut(duration: 0.2) : nil) { chrome.contentOpacity = 1 }
    }

    // MARK: Demo input

    /// The notice is never at rest while a demo acts, but a run can start while
    /// it folds away: a real click or scroll under it ends the fold at once.
    func stepAside(at point: CGPoint) async -> (@MainActor () -> Void)? {
        guard resting == nil, let panel, panel.isVisible, let primary = NSScreen.screens.first else { return nil }
        let location = IslandLayout.appKitPoint(point, primaryMaxY: primary.frame.maxY)
        guard panel.frame.insetBy(dx: -8, dy: -8).contains(location) else { return nil }
        transition &+= 1
        finishHiding(panel)
        // Gives the window server time to drop the panel before the hit test.
        try? await Task.sleep(for: .milliseconds(32))
        return {}
    }
}

// MARK: - Views

/// The notice as `chrome` says: the island or card, with the content over it.
struct DemoNoticeView: View {
    let chrome: DemoNoticeChrome
    let open: () -> Void
    let dismiss: () -> Void

    /// How tall the notice is for `content` at the layout's width.
    static func height(of content: DemoNoticeContent, in layout: DemoNoticeLayout) -> CGFloat {
        let host = NSHostingView(
            rootView: DemoNoticeBody(content: content, layout: layout, open: {}, dismiss: {})
                .environment(\.colorScheme, .dark))
        return ceil(host.fittingSize.height)
    }

    var body: some View {
        let shape = chrome.shape
        ZStack(alignment: .top) {
            if chrome.layout?.isCard == true {
                NoticeCard()
                    .frame(width: shape.size.width, height: shape.size.height)
            } else {
                IslandShape(shoulder: shape.shoulder, bottomRadius: shape.bottomRadius)
                    .fill(.black)
                    .overlay {
                        IslandEdge(shoulder: shape.shoulder, bottomRadius: shape.bottomRadius, stopped: false)
                    }
                    .frame(width: shape.size.width, height: shape.size.height)
            }
            if let layout = chrome.layout, let content = chrome.content {
                DemoNoticeBody(content: content, layout: layout, open: open, dismiss: dismiss)
                    .opacity(chrome.contentOpacity)
                    .allowsHitTesting(chrome.contentOpacity > 0)
            }
        }
        .offset(y: (chrome.layout?.headroom ?? 0) - chrome.lift)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Demo notice")
    }
}

/// Black with continuous corners, and Increase Contrast's faint edge all round.
private struct NoticeCard: View {
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let card = RoundedRectangle(cornerRadius: 20, style: .continuous)
        card.fill(.black)
            .overlay {
                if contrast == .increased {
                    card.strokeBorder(.white.opacity(0.35), lineWidth: 1)
                }
            }
    }
}

/// What the notice says: the badge beside the camera, the app's icon with the
/// title and detail, then Open BetterMeets and Dismiss.
private struct DemoNoticeBody: View {
    let content: DemoNoticeContent
    let layout: DemoNoticeLayout
    let open: () -> Void
    let dismiss: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast

    /// An attention card hangs under the teleprompter's status pill, so it leads
    /// with its title rather than a second status line.
    private var showsBadge: Bool { !(layout.isCard && content.kind == .attention) }

    var body: some View {
        let raised = contrast == .increased
        VStack(alignment: .leading, spacing: 0) {
            if showsBadge {
                NoticeBadge(content: content)
                    .frame(width: layout.badgeWidth, height: layout.band, alignment: .leading)
            }
            HStack(spacing: 12) {
                NoticeAppIcon(bundleID: content.bundleID)
                VStack(alignment: .leading, spacing: 3) {
                    Text(content.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(content.detail)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(raised ? 0.8 : 0.6))
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, showsBadge ? 6 : DemoNoticeLayout.bottomInset)
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Open BetterMeets", action: open)
                    .buttonStyle(IslandButtonStyle(isProminent: true, fitsLabel: true))
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(IslandButtonStyle())
                .help("Dismiss")
                .accessibilityLabel("Dismiss")
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, layout.inset)
        .padding(.bottom, DemoNoticeLayout.bottomInset)
        .frame(width: layout.width, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The glyph and short badge beside the camera.
private struct NoticeBadge: View {
    let content: DemoNoticeContent
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: content.kind == .ready ? "checkmark.seal.fill" : "exclamationmark.bubble.fill")
                .foregroundStyle(content.kind == .ready ? Color.green : Color.orange)
            Text(content.badge)
                .foregroundStyle(.white.opacity(contrast == .increased ? 1 : 0.85))
                .lineLimit(1)
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.badge)
    }
}

/// The app the demo runs in, from its bundle ID, or a generic app icon.
private struct NoticeAppIcon: View {
    let bundleID: String

    var body: some View {
        let workspace = NSWorkspace.shared
        let icon =
            workspace.urlForApplication(withBundleIdentifier: bundleID).map { workspace.icon(forFile: $0.path) }
            ?? workspace.icon(for: .application)
        Image(nsImage: icon)
            .resizable()
            .interpolation(.high)
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)
    }
}
