import AppKit
import Testing
@testable import MeetStage

@Suite("Presenter action placement")
struct StageActionsTests {
    private let screen = CGRect(x: 0, y: 40, width: 1440, height: 860)

    @Test("A resized source leaves the controls outside and vertically centered")
    func outsideSource() throws {
        let source = CGRect(x: 100, y: 100, width: 1000, height: 700)
        let frame = try #require(StageActionsPlacement.panelFrame(sourceFrame: source, visibleScreen: screen))
        #expect(frame.minX == source.maxX + StageActionsMetrics.edgeGap)
        #expect(frame.midY == source.midY)
        #expect(!frame.intersects(source))
    }

    @Test("A maximized source keeps the controls inside its right edge")
    func insideSource() throws {
        let frame = try #require(StageActionsPlacement.panelFrame(sourceFrame: screen, visibleScreen: screen))
        #expect(screen.contains(frame))
        #expect(frame.maxX == screen.maxX - StageActionsMetrics.edgeGap)
        #expect(frame.midY == screen.midY)
    }

    @Test("The left gutter is used when only that side has space")
    func leftGutter() throws {
        let source = CGRect(x: 200, y: 100, width: 1240, height: 700)
        let frame = try #require(StageActionsPlacement.panelFrame(sourceFrame: source, visibleScreen: screen))
        #expect(frame.maxX == source.minX - StageActionsMetrics.edgeGap)
        #expect(frame.midY == source.midY)
    }

    @Test("An exact-width gutter fits without covering the source")
    func gutterBoundary() throws {
        let width = screen.width - StageActionsMetrics.edgeGap - StageActionsMetrics.panelWidth
        let source = CGRect(x: 0, y: 100, width: width, height: 700)
        let outside = try #require(StageActionsPlacement.panelFrame(sourceFrame: source, visibleScreen: screen))
        #expect(outside.maxX == screen.maxX)
        let wider = CGRect(x: 0, y: 100, width: width + 1, height: 700)
        let inside = try #require(StageActionsPlacement.panelFrame(sourceFrame: wider, visibleScreen: screen))
        #expect(wider.contains(inside))
    }

    @Test("Offscreen windows cannot strand the menu, including on a left-hand display")
    func multipleDisplays() throws {
        let screen = CGRect(x: -1440, y: -200, width: 1440, height: 900)
        let source = CGRect(x: -1500, y: 550, width: 1000, height: 400)
        let frame = try #require(StageActionsPlacement.panelFrame(sourceFrame: source, visibleScreen: screen))
        #expect(screen.contains(frame))
        #expect(frame.maxY == screen.maxY)
        #expect(StageActionsPlacement.panelFrame(sourceFrame: .zero, visibleScreen: screen) == nil)
        #expect(StageActionsPlacement.panelFrame(sourceFrame: source, visibleScreen: .zero) == nil)
    }

    @Test("Actions occupy their own nonactivating window above annotation input")
    @MainActor
    func separateWindow() {
        let panel = StageActionsPanel(
            contentRect: CGRect(origin: .zero, size: StageActionsMetrics.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        defer { panel.close() }
        #expect(panel.parent == nil)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.becomesKeyOnlyIfNeeded)
        #expect(panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(panel.level.rawValue > AnnotationWindowPolicy.sourceOverlayLevel.rawValue)
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
    }
}

@Suite("Source picker guidance")
struct SourceSelectionGuidanceTests {
    @Test("The footer explains the current state and the next action separately")
    func selectionStates() {
        let empty = guidance(.idle)
        #expect(empty.title == "No app windows open")
        #expect(empty.hint == "Open an app to get started")
        let suggested = guidance(.idle, suggested: "Chrome", shortcut: "⌥1")
        #expect(suggested.title == "Choose a window")
        #expect(suggested.hint == "Try Chrome · ⌥1")
        #expect(guidance(.idle, suggested: "Chrome").hint == "Click a preview to start")
        let live = guidance(.capturing, selected: "Chrome")
        #expect(live.title == "Chrome on stage")
        #expect(live.hint == "Click again to pause")
        #expect(live.status == .live)
        let paused = guidance(.paused, selected: "Chrome")
        #expect(paused.title == "Chrome paused")
        #expect(paused.hint == "Click again to resume")
        #expect(paused.status == .paused)
        let pending = guidance(.switching, selected: "Chrome", pending: "Warp")
        #expect(pending.title == "Preparing Warp…")
        #expect(pending.status == .busy)
        #expect(guidance(.permissionRequired).hint == "Already allowed? Restart")
        #expect(guidance(.loading).status == .busy)
        let failed = guidance(.failed("Capture failed"))
        #expect(failed.title == "Window unavailable")
        #expect(failed.hint == "Choose an app to try again")
        #expect(failed.status == .warning)
    }

    private func guidance(
        _ state: CaptureState,
        selected: String? = nil,
        pending: String? = nil,
        suggested: String? = nil,
        shortcut: String? = nil
    ) -> SourceSelectionGuidance {
        SourceSelectionGuidance(
            state: state,
            selectedApplication: selected,
            pendingApplication: pending,
            suggestedApplication: suggested,
            shortcut: shortcut
        )
    }
}
