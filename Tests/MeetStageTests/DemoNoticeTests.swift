import AppKit
import Testing

@testable import MeetStage

@Suite("Demo notice")
struct DemoNoticeTests {
    private let signature = ScreenSignature(urlKey: nil, selected: [], headings: [], dialogOpen: false)

    private func demo(steps count: Int = 4) -> RealTimeDemo {
        RealTimeDemo(
            prompt: "Show the Cannes case study",
            app: DemoAppKey(bundleID: "company.thebrowser.dia", appName: "Dia", engine: .chromium, isBrowser: true),
            title: "El Gran Premio de Cannes",
            start: DemoStartPoint(
                signature: signature, url: nil, returnAnchor: nil, toggles: [],
                description: "The Paisanos home page, scrolled to the top", sizeClass: .regular),
            steps: (0..<count).map { index in
                DemoStep(
                    title: "Step \(index + 1)", script: "", holdSeconds: 2, action: .press(.tab), pre: signature)
            },
            status: .recorded)
    }

    private func content(_ phase: DemoPhase) -> DemoNoticeContent? {
        DemoNoticeContent.make(phase: phase, demo: demo(), isChecked: true)
    }

    // MARK: Content

    @Test("A ready demo's notice names it, whether it's tested, its steps, and its app")
    func readyContent() throws {
        let tested = try #require(content(.ready))
        #expect(tested.kind == .ready)
        #expect(tested.badge == "Demo ready")
        #expect(tested.title == "El Gran Premio de Cannes")
        #expect(tested.detail == "Tested · 4 steps · Dia")
        #expect(tested.bundleID == "company.thebrowser.dia")
        #expect(tested.announcement == "Demo ready: El Gran Premio de Cannes, tested, 4 steps")

        let untested = try #require(DemoNoticeContent.make(phase: .ready, demo: demo(steps: 1), isChecked: false))
        #expect(untested.detail == "Not tested · 1 step · Dia")
        #expect(untested.announcement == "Demo ready: El Gran Premio de Cannes, not tested, 1 step")
    }

    @Test("A build that needs the presenter, a test waiting at the start, and a stopped test each get a notice")
    func attentionContent() throws {
        let pending = PendingApproval(
            action: .press(.tab), title: "Send", script: "", message: "Click “Send” in this dialog?", rect: nil)
        let approval = try #require(content(.scoutPaused(.needsApproval(pending))))
        #expect(approval.kind == .attention)
        #expect(approval.badge == "Build paused")
        #expect(approval.title == "Your demo build needs you")
        #expect(approval.detail == "Click “Send” in this dialog?")
        #expect(approval.announcement == "Build paused: Your demo build needs you. Click “Send” in this dialog?")

        let blocked = try #require(content(.scoutPaused(.blocked(reason: "It needs a login.", alternative: ""))))
        #expect(blocked.badge == "Build paused")
        #expect(blocked.detail == "It needs a login.")

        let waiting = try #require(content(.needsStart(.wrongScreen, then: .verify)))
        #expect(waiting.badge == "Test waiting")
        #expect(waiting.title == "Go back to the start to finish the test run")
        #expect(waiting.detail == "The Paisanos home page, scrolled to the top")

        let stopped = try #require(content(.offTrack(.verify, index: 2, .wrongScreen(onStep: 3))))
        #expect(stopped.badge == "Test stopped")
        #expect(stopped.title == "The test run stopped at step 3")
        #expect(stopped.detail == "You’re on step 4’s screen.")
        #expect(stopped.bundleID == "company.thebrowser.dia")
    }

    @Test("Phases the presenter started themselves, or that need nothing, have no notice")
    func noContent() {
        let phases: [DemoPhase] = [
            .composing, .scouting, .scoutPaused(.user), .returning(then: .verify),
            .running(.verify, next: 1, current: 1), .paused(.verify, next: 1, current: 1, reason: .user),
            .needsStart(.wrongScreen, then: .play), .running(.present, next: 0, current: 0),
            .offTrack(.present, index: 1, .wrongScreen(onStep: 2)), .finished
        ]
        for phase in phases {
            #expect(content(phase) == nil, "\(phase)")
        }
    }

    // MARK: State

    @Test("No notice while BetterMeets is active")
    func activeShowsNothing() throws {
        var state = DemoNoticeState()
        let ready = try #require(content(.ready))
        #expect(state.update(to: ready, isActive: true) == .none)
        #expect(state.shown == nil)
    }

    @Test("A new announcement replaces the notice in place; a phase with none hides it")
    func replaceAndHide() throws {
        var state = DemoNoticeState()
        let waiting = try #require(content(.needsStart(.wrongScreen, then: .verify)))
        let ready = try #require(content(.ready))
        #expect(state.update(to: waiting, isActive: false) == .show(waiting))
        #expect(state.update(to: waiting, isActive: false) == .none)
        #expect(state.update(to: ready, isActive: false) == .show(ready))
        #expect(state.shown == ready)
        #expect(state.update(to: nil, isActive: false) == .hide)
        #expect(state.shown == nil)
        #expect(state.update(to: nil, isActive: false) == .none)
    }

    @Test("Switching to BetterMeets hides the notice")
    func activationHides() throws {
        var state = DemoNoticeState()
        let ready = try #require(content(.ready))
        _ = state.update(to: ready, isActive: false)
        #expect(state.update(to: ready, isActive: true) == .hide)
    }

    @Test("A notice the presenter put away doesn't come back for the same phase, until a new run")
    func dismissedStaysAway() throws {
        var state = DemoNoticeState()
        let stopped = try #require(content(.offTrack(.verify, index: 2, .wrongScreen(onStep: 3))))
        let ready = try #require(content(.ready))
        _ = state.update(to: stopped, isActive: false)
        state.presenterDismissed()
        #expect(state.shown == nil)
        #expect(state.update(to: stopped, isActive: false) == .none)
        // Something new is news.
        #expect(state.update(to: ready, isActive: false) == .show(ready))
        state.presenterDismissed()
        #expect(state.update(to: ready, isActive: false) == .none)
        state.forgetDismissed()
        #expect(state.update(to: ready, isActive: false) == .show(ready))
    }

    @Test("Once the phase moves on, the same notice put away earlier is news again")
    func dismissalEndsWithItsPhase() throws {
        var state = DemoNoticeState()
        let paused = try #require(content(.scoutPaused(.userInput)))
        _ = state.update(to: paused, isActive: false)
        state.presenterDismissed()
        // Keep Building: the build runs, then pauses the same way.
        #expect(state.update(to: nil, isActive: false) == .none)
        #expect(state.update(to: paused, isActive: false) == .show(paused))
    }

    // MARK: Layout

    /// A 14-inch MacBook Pro: a 185-point notch and a 33-point menu bar.
    private let builtIn = IslandScreen(
        frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
        visibleFrame: CGRect(x: 0, y: 94, width: 1728, height: 990), safeTop: 32, auxLeftWidth: 771,
        auxRightWidth: 772)

    private let external = IslandScreen(
        frame: CGRect(x: 1728, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 1728, y: 0, width: 1920, height: 1055), safeTop: 0, auxLeftWidth: nil,
        auxRightWidth: nil)

    @Test("With a notch, the notice grows out of it, flush with the top and 300 points wider")
    func notchedLayout() {
        let layout = DemoNoticeLayout.make(screen: builtIn, island: nil)
        #expect(!layout.isCard)
        #expect(layout.notch == CGRect(x: 771, y: 1085, width: 185, height: 32))
        #expect(layout.width == 485)
        #expect(layout.band == 33)
        #expect(layout.badgeWidth == 114)
        #expect(layout.headroom == 0)
        #expect(layout.collapsed == .notch(CGSize(width: 185, height: 32)))
        #expect(
            layout.shape(height: 150)
                == IslandShapeState(size: CGSize(width: 485, height: 150), shoulder: 16, bottomRadius: 20))
        #expect(layout.frame(for: CGSize(width: 485, height: 150)) == CGRect(x: 621, y: 967, width: 485, height: 150))
    }

    @Test("Without a notch, it hangs from the menu bar, 440 points wide, and fades")
    func externalLayout() {
        let layout = DemoNoticeLayout.make(screen: external, island: nil)
        #expect(!layout.isCard)
        #expect(layout.notch == nil)
        #expect(layout.collapsed == nil)
        #expect(layout.width == 440)
        #expect(layout.band == 28)
        #expect(layout.badgeWidth == 384)
        #expect(layout.frame(for: CGSize(width: 440, height: 140)) == CGRect(x: 2468, y: 915, width: 440, height: 140))
    }

    private func teleprompter(_ screen: IslandScreen, size: Double = 26) -> IslandLayout {
        IslandLayout.make(
            screen: screen, fontSize: size, rowHeight: IslandType.rowHeight(IslandType.font(size: size, bold: false)))
    }

    @Test("With the teleprompter on the same display, it's a card 8 points below it, as wide as its body")
    func belowTeleprompter() {
        let expanded = teleprompter(builtIn)
        let island = DockedIsland(.expanded(expanded), in: expanded)
        #expect(island.frame.width == 500)
        let layout = DemoNoticeLayout.make(screen: builtIn, island: island)
        #expect(layout.isCard)
        #expect(layout.collapsed == nil)
        #expect(layout.width == 468)
        #expect(layout.inset == 12)
        #expect(layout.top == island.frame.minY - 8)
        // The window reaches up to the teleprompter, so the card slides out from under it unclipped.
        #expect(layout.headroom == 8)
        #expect(
            layout.frame(for: CGSize(width: 468, height: 150))
                == CGRect(x: 629.5, y: island.frame.minY - 158, width: 468, height: 158))
        #expect(layout.shape(height: 150).shoulder == 0)

        // Its text lines up with the teleprompter's at any text size.
        for size in [16.0, 24, 30, 40] {
            let larger = teleprompter(builtIn, size: size)
            let card = DemoNoticeLayout.make(screen: builtIn, island: DockedIsland(.expanded(larger), in: larger))
            #expect(card.width == larger.width - 32, "\(size)")
            #expect(card.inset + (larger.width - card.width) / 2 == (larger.width - larger.textWidth) / 2, "\(size)")
        }

        // Under the compact pill it matches the pill's body, with a notch or without.
        let compact = DemoNoticeLayout.make(screen: builtIn, island: DockedIsland(.compact(expanded), in: expanded))
        #expect(compact.width == 393)
        #expect(compact.top == 1076)
        let noNotch = teleprompter(external)
        let pill = DemoNoticeLayout.make(screen: external, island: DockedIsland(.compact(noNotch), in: noNotch))
        #expect(pill.width == 284)

        // A teleprompter on another display leaves this one's notch free.
        #expect(!DemoNoticeLayout.make(screen: external, island: island).isCard)
    }

    @Test("A demo input steps around every floating window in its way")
    @MainActor
    func obstructionsStepAside() async {
        final class Obstruction: DemoInputObstruction {
            let inTheWay: Bool
            var stepped = 0
            var restored = 0
            init(inTheWay: Bool) { self.inTheWay = inTheWay }
            func stepAside(at point: CGPoint) async -> (@MainActor () -> Void)? {
                guard inTheWay else { return nil }
                stepped += 1
                return { self.restored += 1 }
            }
        }
        let teleprompter = Obstruction(inTheWay: true)
        let notice = Obstruction(inTheWay: true)
        let restore = await DemoInputObstructions([teleprompter, notice]).stepAside(at: .zero)
        #expect(teleprompter.stepped == 1 && notice.stepped == 1)
        restore?()
        #expect(teleprompter.restored == 1 && notice.restored == 1)
        #expect(await DemoInputObstructions([Obstruction(inTheWay: false)]).stepAside(at: .zero) == nil)
    }
}
