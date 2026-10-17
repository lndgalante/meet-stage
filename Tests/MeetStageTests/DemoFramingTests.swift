import CoreGraphics
import Foundation
import Testing

@testable import MeetStage

/// The page area below a browser toolbar 80 points tall, in an 1200×800 window.
private let page = NormRect(x: 0, y: 0.1, w: 1, h: 0.9)
private let point = 1 / 800.0

@Suite("Demo framing")
struct DemoFramingTests {
    private func node(
        _ id: Int, _ r: NormRect, label: String = "", role: String = "AXGroup", viewport: NormRect? = page,
        container: Int? = nil
    ) -> AXNode {
        AXNode(
            id: id, role: role, subrole: nil, roleClass: AXRoleClass(role: role, subrole: nil), label: label,
            identifier: nil, placeholder: nil, help: nil, rect: r, isVisible: true, isSelected: false, isFocused: false,
            isEnabled: true, isSecure: false, textLength: nil, toggleValue: nil, containerID: container,
            isContainer: false, inWebArea: viewport != nil, url: nil, viewport: viewport)
    }

    private func snapshot(_ nodes: [AXNode]) -> AXSnapshot {
        AXSnapshot(
            generation: 1, windowFrame: CGRect(x: 0, y: 0, width: 1200, height: 800), nodes: nodes, webURL: nil,
            dialogOpen: false, webContent: nil)
    }

    private func move(_ nodes: [AXNode], purpose: DemoFraming.Purpose = .highlight) -> DemoFraming.Move? {
        var progress = DemoFraming.Progress()
        return DemoFraming.nextMove(for: nodes, in: snapshot(nodes), purpose: purpose, progress: &progress)
    }

    @Test("Only a target the viewport cuts is scrolled, never one in full view or outside a page or list")
    func decidesWhatToScroll() {
        // Chromium clips a section running below the fold to end exactly at it.
        let section = node(0, rect(0.1, 0.78, 0.8, 0.22), label: "Key Features")
        #expect(move([section]) == .reveal(0))
        #expect(move([section], purpose: .action) == .reveal(0))
        #expect(move([node(0, rect(0.4, 0.5, 0.2, 0.05))]) == nil)
        #expect(move([node(0, rect(0.4, 0.96, 0.2, 0.035))]) == nil)
        // A native control outside any scroll area, even one the window cuts.
        #expect(move([node(0, rect(0, 0.97, 0.3, 0.05), viewport: nil)]) == nil)
        // A browser's toolbar next to page content.
        #expect(move([node(0, rect(0.1, 0.02, 0.1, 0.04), viewport: nil), node(1, section.rect)]) == nil)

        var progress = DemoFraming.Progress(revealed: true, revealMoved: true)
        let scene = snapshot([section])
        #expect(DemoFraming.nextMove(for: [section], in: scene, purpose: .highlight, progress: &progress) == nil)
        // The reveal did nothing to a frame that only touches the edge: every engine leaves a
        // target wholly in view where it is, so it stays put rather than getting a real scroll.
        for flush in [section, node(0, rect(0, 0.1, 1, 0.08), label: "Site nav")] {
            progress = DemoFraming.Progress(revealed: true)
            #expect(DemoFraming.nextMove(for: [flush], in: scene, purpose: .highlight, progress: &progress) == nil)
        }
        // A frame known to run past the edge (WebKit, AppKit) means the app ignored the request:
        // a highlight gets one exact scroll; an action never does.
        let past = node(0, rect(0.1, 0.78, 0.8, 0.35), label: "Key Features")
        progress = DemoFraming.Progress(revealed: true)
        guard
            case .scroll(let amount) = DemoFraming.nextMove(
                for: [past], in: snapshot([past]), purpose: .highlight, progress: &progress)
        else {
            Issue.record("Expected an exact scroll")
            return
        }
        #expect(abs(amount - (1.13 - (1 - 24 * point))) < 1e-9)
        progress = DemoFraming.Progress(revealed: true)
        #expect(DemoFraming.nextMove(for: [past], in: snapshot([past]), purpose: .action, progress: &progress) == nil)
    }

    @Test("Targets pushed past the opposite edge by centering another get one exact scroll back")
    func bringsGroupsBack() {
        // Centering the button left the heading as Chromium's strip above the view.
        let heading = node(0, NormRect(x: 0.2, y: 0.1, w: 0.6, h: point), label: "Start building", role: "AXHeading")
        let button = node(1, rect(0.4, 0.51, 0.2, 0.08), label: "Start free trial", role: "AXButton")
        var progress = DemoFraming.Progress(revealed: true, revealMoved: true, firstCutBottom: true)
        let scene = snapshot([heading, button])
        // Shown from the bottom with the margin, as the heading's place can't be measured.
        #expect(
            DemoFraming.nextMove(for: [heading, button], in: scene, purpose: .highlight, progress: &progress)
                == .scroll(0.59 - (1 - 24 * point)))
        #expect(
            DemoFraming.nextMove(for: [heading, button], in: scene, purpose: .highlight, progress: &progress) == nil)
        // Already cut there before scrolling, like a sticky header next to the target: left alone.
        progress = DemoFraming.Progress(revealed: true, revealMoved: true, firstCutTop: true, firstCutBottom: true)
        #expect(
            DemoFraming.nextMove(for: [heading, button], in: scene, purpose: .highlight, progress: &progress) == nil)
    }

    @Test("Targets in two panes are neither scrolled for nor clamped to one of them")
    func leavesTwoPanes() {
        let sidebar = NormRect(x: 0, y: 0.1, w: 0.25, h: 0.9)
        let detail = NormRect(x: 0.25, y: 0.1, w: 0.75, h: 0.9)
        let row = node(0, rect(0.02, 0.96, 0.2, 0.04), label: "Inbox", role: "AXRow", viewport: sidebar)
        let item = node(1, rect(0.3, 0.5, 0.6, 0.04), label: "Invoice", role: "AXRow", viewport: detail)
        #expect(DemoFraming.viewport(of: [row, item]) == nil)
        #expect(move([row, item]) == nil)
        #expect(
            DemoFraming.cueRect(for: [row, item], in: snapshot([row, item]), effect: .spotlight)
                == row.rect.union(item.rect))
    }

    @Test("A tall target shows its top: its heading comes in, and a top in the upper half will do")
    func tallTargets() {
        let heading = node(
            1, NormRect(x: 0.15, y: 0.1, w: 0.5, h: point), label: "Everything in one chat", container: 0)
        let covering = node(0, page, label: "Key Features")
        var progress = DemoFraming.Progress(revealed: true, revealMoved: true)
        #expect(
            DemoFraming.nextMove(
                for: [covering], in: snapshot([covering, heading]), purpose: .highlight, progress: &progress)
                == .reveal(1))
        #expect(progress.tall)
        // The heading came in with the top in the upper half: never a real scroll closer to the edge.
        let upper = node(0, NormRect(x: 0.1, y: 0.505, w: 0.8, h: 0.495), label: "Key Features")
        #expect(
            DemoFraming.nextMove(for: [upper], in: snapshot([upper, heading]), purpose: .highlight, progress: &progress)
                == nil)
        // Its top low in the view: scrolled into view once, in the background, and no more.
        progress = DemoFraming.Progress(tall: true)
        let low = node(0, NormRect(x: 0.1, y: 0.75, w: 0.8, h: 0.25), label: "Key Features")
        #expect(
            DemoFraming.nextMove(for: [low], in: snapshot([low]), purpose: .highlight, progress: &progress)
                == .reveal(0))
        #expect(DemoFraming.nextMove(for: [low], in: snapshot([low]), purpose: .highlight, progress: &progress) == nil)
        // Its top already near the top of the view: nothing more to do.
        progress = DemoFraming.Progress(tall: true)
        let highTop = node(0, NormRect(x: 0.1, y: 0.2, w: 0.8, h: 0.8), label: "Key Features")
        #expect(
            DemoFraming.nextMove(for: [highTop], in: snapshot([highTop]), purpose: .highlight, progress: &progress)
                == nil)
    }

    @Test("An exact scroll shows a cut target with a margin and never pushes its top out")
    func exactShift() {
        let margin = 24 * point
        let edge = 1.5 * point
        func shift(_ target: NormRect) -> Double {
            DemoFraming.shift(for: target, in: page, margin: margin, edge: edge)
        }
        #expect(shift(rect(0.1, 0.4, 0.8, 0.3)) == 0)
        // An unclipped frame past the bottom: just enough to clear the margin.
        #expect(abs(shift(rect(0.1, 0.85, 0.8, 0.25)) - (1.10 - (1 - margin))) < 1e-9)
        // A frame ending exactly at the bottom may be clipped: show it from its top.
        #expect(abs(shift(rect(0.1, 0.78, 0.8, 0.22)) - (0.78 - (0.1 + margin))) < 1e-9)
        // Taller than the view: its top stays at the margin.
        #expect(abs(shift(rect(0.1, 0.5, 0.8, 1.0)) - (0.5 - (0.1 + margin))) < 1e-9)
        // Cut at the top: the content moves down.
        #expect(abs(shift(rect(0.1, 0.0, 0.8, 0.2)) - (0.0 - (0.1 + margin))) < 1e-9)
    }

    @Test("A highlight stays inside the page, clear of its edge and the browser's toolbar")
    func cueStaysInside() throws {
        let scene = snapshot([])
        let cut = try #require(
            DemoFraming.cueRect(for: [node(0, rect(0.1, 0.78, 0.8, 0.22))], in: scene, effect: .spotlight))
        #expect(abs(cut.maxY - (1 - 10 * point)) < 1e-9)
        #expect(abs(cut.y - 0.78) < 1e-9)
        let under = try #require(
            DemoFraming.cueRect(for: [node(0, rect(0.1, 0.05, 0.8, 0.3))], in: scene, effect: .draw))
        #expect(abs(under.y - (0.1 + 16 * point)) < 1e-9)
        let native = node(0, rect(0, 0.97, 0.3, 0.05), viewport: nil)
        #expect(DemoFraming.cueRect(for: [native], in: scene, effect: .spotlight) == native.rect)
        // Below a sticky header's bottom edge.
        let covered = try #require(
            DemoFraming.cueRect(
                for: [node(0, rect(0.1, 0.1, 0.8, 0.5))], in: scene, effect: .spotlight, coveredTop: 0.18))
        #expect(abs(covered.y - (0.18 + 10 * point)) < 1e-9)
    }

    @Test("Scrolls are measured from edges the viewport didn't clip, and a sticky header doesn't hide the move")
    func measuresShift() throws {
        let before = snapshot([node(0, rect(0.1, 0.78, 0.8, 0.22), label: "Key Features")])
        let after = snapshot([node(0, rect(0.1, 0.375, 0.8, 0.35), label: "Key Features")])
        #expect(abs(try #require(DemoFraming.observedShift(from: before, to: after, pairs: [(0, 0)])) - 0.405) < 1e-9)

        func page(_ dy: Double) -> AXSnapshot {
            snapshot([
                node(0, rect(0.1, 0.12, 0.1, 0.03), label: "Home", role: "AXLink"),
                node(1, rect(0.3, 0.12, 0.1, 0.03), label: "Pricing", role: "AXLink"),
                node(2, rect(0.1, 0.6 - dy, 0.4, 0.03), label: "Log expenses by chat", role: "AXStaticText"),
                node(3, rect(0.1, 0.7 - dy, 0.4, 0.03), label: "Budgets that adapt", role: "AXStaticText"),
                // Chromium's strip for an element below the fold says nothing about where it is.
                node(4, NormRect(x: 0.1, y: 1 - point, w: 0.4, h: point), label: "Reports", role: "AXStaticText")
            ])
        }
        #expect(abs(try #require(DemoFraming.observedShift(from: page(0), to: page(0.2))) - 0.2) < 1e-9)
        #expect(try #require(DemoFraming.observedShift(from: page(0), to: page(0))) == 0)
        #expect(DemoFraming.observedShift(from: snapshot([]), to: snapshot([])) == nil)

        // The links stayed put while the page moved: a sticky header, whose bottom a highlight stays below.
        let target = rect(0.1, 0.3, 0.8, 0.3)
        let area = NormRect(x: 0, y: 0.1, w: 1, h: 0.9)
        #expect(
            DemoFraming.pinnedTop(from: page(0), to: page(0.2), moved: 0.2, over: target, in: area, excluding: [])
                == 0.15)
        #expect(
            DemoFraming.pinnedTop(from: page(0), to: page(0), moved: 0, over: target, in: area, excluding: [])
                == nil)
        // Not across the target, or the target itself: no header over it.
        #expect(
            DemoFraming.pinnedTop(
                from: page(0), to: page(0.2), moved: 0.2, over: rect(0.6, 0.3, 0.3, 0.3), in: area, excluding: [])
                == nil)
        #expect(
            DemoFraming.pinnedTop(
                from: page(0), to: page(0.2), moved: 0.2, over: target, in: area, excluding: [0, 1]) == nil)
    }
}

/// A landing page in Chromium whose “Key Features” section starts above the fold
/// and runs past it, like the page in the report.
@MainActor
private func landingApp(sectionHeight: Double = 0.35, engine: AppEngine = .chromium) -> FakeApp {
    let home = FakeScreen(
        url: "https://gasti.app/",
        elements: [
            FakeElement(role: "AXButton", label: "Back", rect: rect(0.02, 0.02, 0.04, 0.04), fixed: true),
            FakeElement(role: "AXHeading", label: "The more you use it", rect: rect(0.2, 0.2, 0.6, 0.06)),
            FakeElement(role: "AXLink", label: "Get Started", rect: rect(0.4, 0.4, 0.2, 0.05)),
            FakeElement(
                role: "AXGroup", label: "Key Features", rect: rect(0.1, 0.78, 0.8, sectionHeight), isContainer: true),
            FakeElement(
                role: "AXHeading", label: "Everything in one chat", rect: rect(0.15, 0.8, 0.5, 0.05),
                container: "Key Features"),
            FakeElement(
                role: "AXStaticText", label: "Log expenses by chat", rect: rect(0.15, 0.9, 0.4, 0.03),
                container: "Key Features"),
            FakeElement(
                role: "AXImage", label: "Budget chart", rect: rect(0.6, 0.86, 0.25, 0.1), container: "Key Features"),
            FakeElement(
                role: "AXLink", label: "$9 / month", rect: rect(0.15, 1.02, 0.2, 0.03), container: "Key Features"),
            FakeElement(role: "AXLink", label: "See all features", rect: rect(0.4, 1.62, 0.2, 0.05))
        ], viewport: page)
    let app = FakeApp(screens: ["home": home], start: "home")
    app.engine = engine
    return app
}

@Suite("Framing demo targets")
@MainActor
struct DemoFramingReplayTests {
    private let keyFeatures = DemoElementLocator(
        role: "AXGroup", label: "Key Features", labelIsStable: true, rect: rect(0.1, 0.78, 0.8, 0.22))
    private let pre = ScreenSignature(urlKey: "gasti.app/", selected: [], headings: [], dialogOpen: false)

    private func demo(_ steps: [DemoStep]) -> RealTimeDemo {
        RealTimeDemo(
            prompt: "Show the key features",
            app: DemoAppKey(bundleID: "com.example.app", appName: "Example", engine: .chromium, isBrowser: true),
            title: "Gasti", steps: steps, status: .recorded)
    }

    private func highlight(_ locator: DemoElementLocator, framing: Double? = nil) -> DemoStep {
        DemoStep(
            title: "Key features", script: "", holdSeconds: 0.4,
            action: .present(DemoBeat(effect: .spotlight, targets: [locator])), pre: pre, framing: framing)
    }

    private func replay(
        _ demo: RealTimeDemo, on app: FakeApp, mode: ReplayMode = .present, model: ScriptedModel = ScriptedModel([])
    ) -> DemoReplayEngine {
        var options = DemoReplayEngine.Options(mode: mode, holdOverride: 0.001, gateTimeout: .milliseconds(200))
        options.framing = .instant
        return DemoReplayEngine(
            demo: demo, source: app.demoSource, driver: app, model: model, key: { "key" }, options: options,
            hooks: .init(check: {}, onStep: { _, _ in }, onCommit: { _ in }))
    }

    private func scout(_ app: FakeApp, _ model: ScriptedModel) throws -> DemoScout {
        var limits = fastScoutLimits()
        limits.beatPreview = .milliseconds(1)
        return try DemoScout(
            demo: RealTimeDemo(
                prompt: "Show the key features",
                app: DemoAppKey(bundleID: "com.example.app", appName: "Example", engine: .chromium, isBrowser: true),
                title: "Demo", status: .draft(ScoutDraft())),
            source: app.demoSource, driver: app, model: model, key: "key", limits: limits, check: {},
            onUpdate: { _, _ in })
    }

    private func lastCue(_ app: FakeApp) -> NormRect? {
        app.cues.compactMap { $0?.rect }.last
    }

    /// Whether `cue` sits inside the page with the framing margin around it.
    private func isFramed(_ cue: NormRect?) -> Bool {
        guard let cue else { return false }
        let margin = DemoFraming.margin * point - 1e-9
        return cue.y >= page.y + margin && cue.maxY <= page.maxY - margin
    }

    @Test("A section cut by the fold is scrolled fully into view before its highlight")
    func framesCutSection() async throws {
        let app = landingApp()
        let end = try await replay(demo([highlight(keyFeatures)]), on: app).run(from: 0)
        #expect(end == .completed)
        // Chromium centers it in the background; no wheel scroll.
        #expect(app.log == ["scroll into view Key Features"])
        #expect(abs(app.screens["home"]!.scrollY - 0.405) < 1e-9)
        let cue = try #require(lastCue(app))
        #expect(isFramed(cue))
        #expect(abs(cue.h - 0.35) < 1e-9)
    }

    @Test("The highlight comes from a look taken once the scroll settled")
    func settlesBeforeHighlighting() async throws {
        let app = landingApp()
        app.scrollLag = 1
        #expect(try await replay(demo([highlight(keyFeatures)]), on: app).run(from: 0) == .completed)
        #expect(isFramed(lastCue(app)))
    }

    @Test("A section taller than the view shows its top: its heading comes in, all in the background")
    func framesTallSection() async throws {
        let app = landingApp(sectionHeight: 1.4)
        #expect(try await replay(demo([highlight(keyFeatures)]), on: app).run(from: 0) == .completed)
        // Chromium centers the section, then its heading; its top then sits in the upper half.
        #expect(app.log == ["scroll into view Key Features", "scroll into view Everything in one chat"])
        let cue = try #require(lastCue(app))
        #expect(abs(cue.y - 0.505) < 1e-9)
        #expect(cue.y < page.midY)
        #expect(abs(cue.maxY - (page.maxY - 10 * point)) < 1e-9)
    }

    @Test("A highlight starts below a sticky header that scrolling into view showed")
    func staysBelowStickyHeader() async throws {
        let app = landingApp(sectionHeight: 0.86)
        app.screens["home"]!.elements[3].rect.y = 0.56
        app.screens["home"]!.elements.append(
            FakeElement(
                role: "AXGroup", label: "Site nav", rect: rect(0, 0.1, 1, 0.08), isContainer: true, sticky: true))
        #expect(try await replay(demo([highlight(keyFeatures)]), on: app).run(from: 0) == .completed)
        // Centered, the section's top sits under the header.
        #expect(app.log == ["scroll into view Key Features"])
        let cue = try #require(lastCue(app))
        #expect(abs(cue.y - (0.18 + 10 * point)) < 1e-9)
    }

    @Test("A highlight that only touches the edge of the view never gets a real scroll")
    func leavesFlushTargets() async throws {
        let screen = FakeScreen(
            url: "https://gasti.app/",
            elements: [
                FakeElement(
                    role: "AXGroup", label: "Site nav", rect: rect(0, 0.1, 1, 0.08), isContainer: true, sticky: true),
                FakeElement(role: "AXGroup", label: "Hero", rect: rect(0, 0.1, 1, 0.5), isContainer: true),
                FakeElement(role: "AXGroup", label: "Footer", rect: rect(0, 2.6, 1, 0.3), isContainer: true),
                FakeElement(
                    role: "AXGroup", label: "Cookie notice", rect: rect(0, 0.92, 1, 0.08), isContainer: true,
                    sticky: true)
            ], viewport: page, maxScrollY: 1.9)
        // The hero at the top of the page, the sticky header and banner scrolled down, the footer at the end.
        for (label, scrollY) in [("Hero", 0.0), ("Site nav", 1.0), ("Cookie notice", 0.5), ("Footer", 1.9)] {
            let app = FakeApp(screens: ["home": screen], start: "home")
            app.screens["home"]!.scrollY = scrollY
            let element = try #require(screen.elements.first { $0.label == label })
            let locator = DemoElementLocator(role: "AXGroup", label: label, labelIsStable: true, rect: element.rect)
            #expect(try await replay(demo([highlight(locator)]), on: app).run(from: 0) == .completed)
            #expect(!app.log.contains { $0.hasPrefix("scroll by") }, "\(label)")
            #expect(app.screens["home"]!.scrollY == scrollY, "\(label)")
            #expect(app.broughtToFront == 0)
            #expect(lastCue(app) != nil, "\(label)")
        }
    }

    @Test("Highlighting a heading and a button cut at the fold shows both, not just the button")
    func framesSpreadGroup() async throws {
        let app = FakeApp(
            screens: [
                "home": FakeScreen(
                    url: "https://gasti.app/",
                    elements: [
                        FakeElement(role: "AXHeading", label: "Start building", rect: rect(0.2, 0.4, 0.6, 0.05)),
                        FakeElement(role: "AXButton", label: "Start free trial", rect: rect(0.4, 0.95, 0.2, 0.08))
                    ], viewport: page)
            ], start: "home")
        let heading = DemoElementLocator(
            role: "AXHeading", label: "Start building", labelIsStable: true, rect: rect(0.2, 0.4, 0.6, 0.05))
        let button = DemoElementLocator(
            role: "AXButton", label: "Start free trial", labelIsStable: true, rect: rect(0.4, 0.95, 0.2, 0.05))
        let step = DemoStep(
            title: "Start", script: "", holdSeconds: 0.4,
            action: .present(DemoBeat(effect: .spotlight, targets: [heading, button])), pre: pre)
        #expect(try await replay(demo([step]), on: app).run(from: 0) == .completed)
        // Centering the button pushed the heading out the top; one exact scroll brings both back.
        #expect(app.log == ["scroll into view Start free trial", "scroll by -304"])
        let cue = try #require(lastCue(app))
        let scrollY = app.screens["home"]!.scrollY
        #expect(abs(cue.y - (0.4 - scrollY)) < 1e-9)
        #expect(abs(cue.maxY - (1.03 - scrollY)) < 1e-9)
        #expect(isFramed(cue))
    }

    @Test("The last highlight is cleared before scrolling, so it never sits over moving content")
    func clearsCueBeforeScrolling() async throws {
        let app = landingApp()
        let heading = DemoElementLocator(
            role: "AXHeading", label: "The more you use it", labelIsStable: true, rect: rect(0.2, 0.2, 0.6, 0.06))
        var cueAtScroll: [DemoCue?] = []
        app.beforeInput = { input in
            if case .scrollToVisible = input { cueAtScroll.append(app.cues.last ?? nil) }
        }
        #expect(
            try await replay(demo([highlight(heading), highlight(keyFeatures)]), on: app).run(from: 0) == .completed)
        #expect(cueAtScroll.count == 1)
        #expect(cueAtScroll.first == .some(nil))
        #expect(app.cues.compactMap { $0 }.count == 2)
    }

    @Test("Presenting, a highlight scrolled into view stays up a moment even when its line was already said")
    func keepsFramedCueUp() async throws {
        func run(_ step: DemoStep) async throws -> Duration {
            let app = landingApp()
            var options = DemoReplayEngine.Options(mode: .present, gateTimeout: .milliseconds(200))
            options.framing = .instant
            options.framedCueMinimum = .milliseconds(300)
            let engine = DemoReplayEngine(
                demo: demo([step]), source: app.demoSource, driver: app, model: ScriptedModel([]), key: { "key" },
                options: options,
                hooks: .init(check: {}, onStep: { _, _ in }, onCommit: { _ in }, hold: { _, _ in }))
            let started = ContinuousClock.now
            #expect(try await engine.run(from: 0) == .completed)
            return ContinuousClock.now - started
        }
        #expect(try await run(highlight(keyFeatures)) >= .milliseconds(300))
        // Nothing to scroll: the voice decides alone.
        let heading = DemoElementLocator(
            role: "AXHeading", label: "The more you use it", labelIsStable: true, rect: rect(0.2, 0.2, 0.6, 0.06))
        #expect(try await run(highlight(heading)) < .milliseconds(300))
    }

    @Test("Targets already in full view never scroll, in a browser or a native app's list")
    func leavesVisibleTargets() async throws {
        for engine in [AppEngine.chromium, .native] {
            let app = landingApp(engine: engine)
            app.isBrowser = engine != .native
            let heading = DemoElementLocator(
                role: "AXHeading", label: "The more you use it", labelIsStable: true, rect: rect(0.2, 0.2, 0.6, 0.06))
            let link = DemoElementLocator(
                role: "AXLink", label: "Get Started", labelIsStable: true, rect: rect(0.4, 0.4, 0.2, 0.05))
            let steps = [
                DemoStep(
                    title: "Headline", script: "", holdSeconds: 0.4,
                    action: .present(DemoBeat(effect: .spotlight, targets: [heading])), pre: pre),
                DemoStep(title: "Start", script: "", holdSeconds: 0.4, action: .click(link), pre: pre)
            ]
            #expect(try await replay(demo(steps), on: app).run(from: 0) == .completed)
            #expect(app.log == ["click Get Started"])
            #expect(app.screens["home"]!.scrollY == 0)
            #expect(lastCue(app) == heading.rect.clampedToWindow)
        }
    }

    @Test("A native control outside any scroll area is highlighted where it is, without scrolling")
    func leavesNativeControls() async throws {
        let toolbar = DemoElementLocator(
            role: "AXGroup", label: "Formatting", labelIsStable: true, rect: rect(0, 0.97, 0.3, 0.05))
        let app = FakeApp(
            screens: [
                "editor": FakeScreen(
                    url: nil,
                    elements: [FakeElement(role: "AXGroup", label: "Formatting", rect: toolbar.rect, isContainer: true)]
                )
            ], start: "editor")
        app.engine = .native
        app.isBrowser = false
        var step = highlight(toolbar)
        step.pre = ScreenSignature(selected: [], headings: [], dialogOpen: false)
        #expect(try await replay(demo([step]), on: app).run(from: 0) == .completed)
        #expect(app.log.isEmpty)
        #expect(lastCue(app) == toolbar.rect.clampedToWindow)
    }

    @Test(
        "When the app ignores scrolling into view, a highlight past the edge gets an exact scroll and a click doesn't")
    func fallsBackToExactScroll() async throws {
        // WebKit's frames aren't clipped, so the section is known to run past the fold.
        let app = landingApp(engine: .webkit)
        app.ignoresScrollToVisible = true
        app.screens["home"]!.elements[8].rect = rect(0.4, 1.13, 0.2, 0.05)
        let more = DemoElementLocator(
            role: "AXLink", label: "See all features", labelIsStable: true, rect: rect(0.4, 0.97, 0.2, 0.05))
        let steps = [
            highlight(keyFeatures),
            DemoStep(title: "More", script: "", holdSeconds: 0.4, action: .click(more), pre: pre)
        ]
        #expect(try await replay(demo(steps), on: app).run(from: 0) == .completed)
        #expect(
            app.log == [
                "scroll into view Key Features", "scroll by 128", "scroll into view See all features",
                "click See all features"
            ])
        #expect(app.cues.compactMap { $0?.rect }.contains { isFramed($0) })
    }

    @Test("A target whose identity a scroll lost is found again where the scroll moved it")
    func refindsLostTargets() async throws {
        let app = landingApp()
        app.forgetsElementsWhenScrolled = true
        let engine = replay(demo([highlight(keyFeatures)]), on: app, mode: .verify)
        #expect(try await engine.run(from: 0) == .completed)
        #expect(engine.verifiedAllSteps)
        #expect(isFramed(lastCue(app)))
    }

    @Test("Scrolling the build did for a step left out of the demo still counts for the next one")
    func accountsForDroppedFraming() async throws {
        let chart = DemoElementLocator(
            role: "AXImage", label: "Budget chart", labelIsStable: false,
            container: ContainerKey(role: "AXGroup", subrole: nil, label: "key features"),
            rect: rect(0.6, 0.86 - 0.2, 0.25, 0.1))
        let dropped = DemoStep(
            title: "Pricing", script: "", holdSeconds: 0.4, action: .click(keyFeatures), pre: pre, framing: 0.2)
        var kept = highlight(chart, framing: 0)
        kept.title = "The chart"
        let records = [
            ScoutRecord(turn: 1, steps: [dropped], outcome: .noEffect, fact: ""),
            ScoutRecord(turn: 2, steps: [dropped], outcome: .rejected, fact: ""),
            ScoutRecord(turn: 3, steps: [kept], outcome: .changed, fact: "")
        ]
        let steps = ScoutCompaction.compact(records)
        #expect(steps.count == 2)
        #expect(steps.last?.priorFraming == 0.2)
        // A step on another page owes nothing.
        var elsewhere = kept
        elsewhere.pre.urlKey = "gasti.app/pricing"
        #expect(
            ScoutCompaction.compact([records[1], ScoutRecord(turn: 3, steps: [elsewhere], outcome: .changed, fact: "")])
                .first?.priorFraming == nil)

        // The chart was recorded on the page scrolled for the dropped step; replay finds it unscrolled.
        let app = landingApp()
        let replayModel = ScriptedModel([])
        let engine = replay(demo([steps[1]]), on: app, model: replayModel)
        #expect(try await engine.run(from: 0) == .completed)
        #expect(engine.skippedBeats.isEmpty)
        #expect(replayModel.relocateCount == 0)
        let cue = try #require(lastCue(app))
        #expect(abs(cue.y - 0.86) < 1e-9 && abs(cue.h - 0.1) < 1e-9)
    }

    @Test("Resuming a paused presentation keeps track of the page an earlier highlight scrolled")
    func keepsDriftAcrossResume() async throws {
        let app = landingApp()
        let price = DemoElementLocator(
            role: "AXLink", label: "", labelIsStable: false,
            container: ContainerKey(role: "AXGroup", subrole: nil, label: "key features"),
            rect: rect(0.15, 0.97, 0.2, 0.03))
        app.screens["home"]!.elements[7].rect = rect(0.15, 0.97, 0.2, 0.03)
        var recorded = demo([
            highlight(keyFeatures),
            DemoStep(title: "Price", script: "", holdSeconds: 0.4, action: .click(price), pre: pre, approved: true)
        ])
        let start = try await app.snapshot(app.demoSource, waitForContent: true)
        recorded.start = DemoStartPoint(
            signature: ScreenSignatures.make(start), url: URL(string: "https://gasti.app/"), returnAnchor: nil,
            toggles: [], description: "Gasti home", sizeClass: .regular)
        let defaults = UserDefaults(suiteName: "demo-framing-tests-\(UUID().uuidString)")!
        defaults.set(true, forKey: DemoSession.consentKey)
        var library = DemoLibrary(defaults: defaults)
        library.save(recorded)
        let model = ScriptedModel([])
        let session = DemoSession(
            driver: app, defaults: defaults, model: model, keyStore: FramingKeyStore(), observesUserInput: false,
            scoutLimits: fastScoutLimits(), opensWindows: false)
        session.replayTuning = (0.001, .milliseconds(300))
        session.pausesAfterEachStep = true
        #expect(session.phase == .ready)

        session.play()
        try await waitUntil { if case .paused = session.phase { true } else { false } }
        #expect(app.log == ["scroll into view Key Features"])
        // A resume is a new run, which must still know the page sits higher than recorded.
        session.play()
        try await waitUntil { session.phase == .finished }
        #expect(app.log == ["scroll into view Key Features", "click $9 / month"])
        #expect(model.relocateCount == 0)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<1_000 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting")
    }

    @Test("A demo built before framing still finds a target by position after its highlight scrolled the page")
    func compensatesOlderDemos() async throws {
        let app = landingApp()
        let price = DemoElementLocator(
            role: "AXLink", label: "", labelIsStable: false,
            container: ContainerKey(role: "AXGroup", subrole: nil, label: "key features"),
            rect: rect(0.15, 0.97, 0.2, 0.03))
        let steps = [
            highlight(keyFeatures),
            DemoStep(
                title: "Price", script: "", holdSeconds: 0.4, action: .click(price), pre: pre, approved: true)
        ]
        // The price was recorded cut at the fold, before highlights scrolled.
        app.screens["home"]!.elements[7].rect = rect(0.15, 0.97, 0.2, 0.03)
        let model = ScriptedModel([])
        #expect(try await replay(demo(steps), on: app, model: model).run(from: 0) == .completed)
        #expect(app.log == ["scroll into view Key Features", "click $9 / month"])
        #expect(model.relocateCount == 0)
    }

    @Test("Building frames a cut section before showing it and records it so replay ends up the same")
    func buildAndReplayAgree() async throws {
        let built = landingApp()
        let model = ScriptedModel([
            reply(.present([ScoutBeat(effect: .spotlight, elementIDs: [3], title: "Key features", script: "")])),
            reply(.finish(title: "Gasti", startDescription: "Gasti home", startLabel: "", closingScript: ""))
        ])
        let scout = try scout(built, model)
        #expect(try await scout.run() == .finished)
        #expect(built.log == ["scroll into view Key Features"])
        let builtCue = try #require(lastCue(built))
        #expect(isFramed(builtCue))
        #expect(model.facts[1].last?.contains("scrolled into view") == true)

        var recorded = scout.demo
        recorded.steps = ScoutCompaction.compact(recorded.draft?.records ?? [])
        recorded.status = .recorded
        let step = try #require(recorded.steps.first)
        #expect(abs((step.framing ?? 0) - 0.405) < 1e-9)
        guard case .present(let beat) = step.action else {
            Issue.record("Expected a highlight")
            return
        }
        // Recorded as replay finds it: before the scroll.
        #expect(abs(beat.targets[0].rect.y - 0.78) < 1e-9)

        let replayed = landingApp()
        let replayModel = ScriptedModel([])
        #expect(try await replay(recorded, on: replayed, model: replayModel).run(from: 0) == .completed)
        #expect(replayed.screens["home"]!.scrollY == built.screens["home"]!.scrollY)
        #expect(lastCue(replayed) == builtCue)
        #expect(replayModel.relocateCount == 0)
    }

    @Test("A later highlight in the same turn is recorded where the earlier one's scroll left it")
    func followsLaterBeats() async throws {
        let built = landingApp()
        let model = ScriptedModel([
            reply(
                .present([
                    ScoutBeat(effect: .spotlight, elementIDs: [3], title: "Key features", script: ""),
                    ScoutBeat(effect: .draw, elementIDs: [6], title: "The chart", script: "")
                ])),
            reply(.finish(title: "Gasti", startDescription: "Gasti home", startLabel: "", closingScript: ""))
        ])
        let scout = try scout(built, model)
        #expect(try await scout.run() == .finished)
        let steps = ScoutCompaction.compact(scout.demo.draft?.records ?? [])
        #expect(steps.count == 2)
        guard steps.count == 2, case .present(let chart) = steps[1].action else {
            Issue.record("Expected two highlights")
            return
        }
        // An image is found by position, so it must be where the first highlight's scroll left it.
        #expect(DemoLocatorMatcher.isPositional(chart.targets[0]))
        #expect(abs(chart.targets[0].rect.y - (0.86 - 0.405)) < 1e-9)
        #expect(steps[1].framing == 0)

        var recorded = scout.demo
        recorded.steps = steps
        recorded.status = .recorded
        let replayed = landingApp()
        let replayModel = ScriptedModel([])
        let engine = replay(recorded, on: replayed, model: replayModel)
        #expect(try await engine.run(from: 0) == .completed)
        #expect(engine.skippedBeats.isEmpty)
        #expect(replayModel.relocateCount == 0)
        #expect(replayed.cues.compactMap { $0 }.map(\.effect) == [.spotlight, .draw])
    }

    @Test("Building scrolls a cut button into view before clicking it, and the scroll isn't the click's effect")
    func framesClicksWhileBuilding() async throws {
        let app = FakeApp(
            screens: [
                "home": FakeScreen(
                    url: "https://gasti.app/",
                    elements: [
                        FakeElement(role: "AXLink", label: "Pricing", rect: rect(0.1, 0.1, 0.1, 0.03)),
                        FakeElement(role: "AXButton", label: "Join the waitlist", rect: rect(0.4, 0.95, 0.2, 0.08))
                    ], viewport: page)
            ], start: "home")
        // WebKit's frames aren't clipped, so the link leaving the view changes what shows.
        app.engine = .webkit
        let model = ScriptedModel([
            reply(.click(elementID: 1, title: "Join", script: "")),
            reply(.finish(title: "Join", startDescription: "Gasti home", startLabel: "", closingScript: ""))
        ])
        let scout = try scout(app, model)
        #expect(try await scout.run() == .finished)
        // The click changed nothing, so it's retried with a real click, not counted as working.
        #expect(app.log == ["scroll into view Join the waitlist", "click Join the waitlist", "click Join the waitlist"])
        #expect(model.facts[1].last?.contains("no visible change") == true)
        let step = try #require(scout.demo.draft?.records.first?.steps.first)
        #expect(abs((step.framing ?? 0) - 0.03) < 1e-9)
    }

    @Test("Building looks for a clicked icon where scrolling it into view moved it, to retry with a real click")
    func retriesFramedClicks() async throws {
        let app = FakeApp(
            screens: [
                "home": FakeScreen(
                    url: "https://gasti.app/",
                    elements: [
                        FakeElement(role: "AXLink", label: "Pricing", rect: rect(0.1, 0.1, 0.1, 0.03)),
                        FakeElement(
                            role: "AXButton", label: "", rect: rect(0.45, 0.94, 0.05, 0.1), pointerOnly: true)
                    ], viewport: page)
            ], start: "home")
        app.engine = .webkit
        let model = ScriptedModel([
            reply(.click(elementID: 1, title: "Open the menu", script: "")),
            reply(.finish(title: "Menu", startDescription: "Gasti home", startLabel: "", closingScript: ""))
        ])
        let scout = try scout(app, model)
        // An unlabelled control needs the presenter's approval first.
        guard case .stopped(.needsApproval(let pending)) = try await scout.run() else {
            Issue.record("Expected an approval")
            return
        }
        #expect(try await scout.run(approved: pending) == .finished)
        // Scrolled up by 32 points, past where the icon was found by position.
        #expect(app.log == ["scroll into view ", "press  (ignored)", "click "])
    }
}

private struct FramingKeyStore: DemoKeyStore {
    var key: String? { "test-key" }
    var hasKey: Bool { true }
    func save(_ value: String) -> Bool { true }
}
