import AppKit
import Testing
@testable import MeetStage

@Suite("Magnetic Dock attachment")
struct DockSnapTests {
    private let screen = CGRect(x: 0, y: 0, width: 2048, height: 1152)
    private let visible = CGRect(x: 0, y: 98, width: 2048, height: 1026)
    private let dock = CGRect(x: 398, y: 5, width: 1252, height: 93)

    @Test("Both ends of the Dock have a fixed gap and share its vertical center")
    func attachmentTargets() throws {
        let targets = targets()
        let right = try #require(targets.first { $0.side == .right })
        let left = try #require(targets.first { $0.side == .left })
        #expect(right.frame.minX - dock.maxX == DockSnap.gap)
        #expect(dock.minX - left.frame.maxX == DockSnap.gap)
        for target in targets {
            #expect(abs(target.frame.midY - dock.midY) <= 0.5)
            #expect(screen.contains(target.frame))
            #expect(!target.frame.intersects(dock))
        }
    }

    @Test("Only a drop near the Dock is eligible to snap")
    func dropDistance() throws {
        let targets = targets()
        let right = try #require(targets.first)
        let near = CGPoint(x: right.frame.minX + 20, y: right.frame.minY + 5)
        #expect(DockSnap.target(for: near, among: targets) == right)
        let farther = CGPoint(x: right.frame.minX + 35, y: right.frame.minY)
        #expect(DockSnap.target(for: farther, among: targets) == nil)
    }

    @Test("A distant or vertically misaligned drag remains free")
    func noUnexpectedSnap() throws {
        let targets = targets()
        let right = try #require(targets.first)
        #expect(DockSnap.target(for: CGPoint(x: 800, y: 300), among: targets) == nil)
        let above = CGPoint(x: right.frame.minX, y: right.frame.minY + 70)
        #expect(DockSnap.target(for: above, among: targets) == nil)
    }

    @Test("Hidden, side, or full-width Docks never create unreachable snap targets")
    func unavailableTargets() {
        for dock in [
            CGRect(x: 398, y: -92, width: 1252, height: 93),
            CGRect(x: 0, y: 200, width: 93, height: 752),
            CGRect(x: 100, y: 5, width: 1848, height: 93)
        ] {
            #expect(
                DockSnap.targets(size: ControlWindowSizing.size, dock: dock, screen: screen, visibleScreen: visible)
                    .isEmpty)
        }
    }

    @Test("Dock attachment works on a display with negative coordinates")
    func secondaryDisplay() {
        let actual = DockSnap.targets(
            size: ControlWindowSizing.size,
            dock: dock.offsetBy(dx: -2048, dy: -300),
            screen: screen.offsetBy(dx: -2048, dy: -300),
            visibleScreen: visible.offsetBy(dx: -2048, dy: -300)
        )
        #expect(
            actual == targets().map { DockSnapTarget(side: $0.side, frame: $0.frame.offsetBy(dx: -2048, dy: -300)) })
    }

    @Test("Option bypasses snapping and clears a saved attachment")
    @MainActor
    func bypassAndPersistence() throws {
        let suite = "DockSnapTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let window = ControlWindow()
        defer { window.close() }
        let targets = targets()
        var reads = 0
        let attachment = ControlDockAttachment(window: window, defaults: defaults) { _ in
            reads += 1
            return targets
        }
        #expect(attachment.attach())
        #expect(defaults.string(forKey: ControlDockAttachment.preferenceKey) == "right")
        attachment.beginDragging()
        let readsAtPickup = reads
        let proposed = window.frame.origin
        #expect(attachment.dragOrigin(for: proposed, bypassSnap: true) == proposed)
        #expect(attachment.dragOrigin(for: proposed, bypassSnap: true) == proposed)
        #expect(reads == readsAtPickup)
        attachment.endDragging()
        #expect(defaults.string(forKey: ControlDockAttachment.preferenceKey) == nil)
    }

    @Test("Restored attachments follow the Dock's current position")
    @MainActor
    func restoredAttachment() throws {
        let suite = "DockSnapTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("left", forKey: ControlDockAttachment.preferenceKey)
        let window = ControlWindow()
        defer { window.close() }
        let targets = targets()
        let attachment = ControlDockAttachment(window: window, defaults: defaults) { _ in targets }
        attachment.restore()
        #expect(window.frame == targets.first { $0.side == .left }?.frame)
    }

    private func targets() -> [DockSnapTarget] {
        DockSnap.targets(size: ControlWindowSizing.size, dock: dock, screen: screen, visibleScreen: visible)
    }
}
