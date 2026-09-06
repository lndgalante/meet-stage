import AppKit
import SwiftUI

/// Owns an independent window, never a child of the source or shared Stage.
/// Window-only capture therefore contains the Stage's content without controls.
struct StageActionsInstaller: NSViewRepresentable {
    @ObservedObject var manager: CaptureManager

    func makeCoordinator() -> StageActionsPresenter {
        StageActionsPresenter()
    }

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let source = manager.windows.first { $0.id == manager.selectedWindowID }
        context.coordinator.update(
            source: source,
            manager: manager
        )
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: StageActionsPresenter) {
        coordinator.dismiss()
    }
}

@MainActor
final class StageActionsPresenter {
    private var panel: StageActionsPanel?
    private var sourceID: CGWindowID?
    private var trackingTask: Task<Void, Never>?

    deinit {
        trackingTask?.cancel()
    }

    func update(
        source: WindowSource?,
        manager: CaptureManager
    ) {
        guard let source else {
            dismiss()
            return
        }
        guard sourceID != source.id else { return }
        dismiss()
        sourceID = source.id

        let panel = StageActionsPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = NSHostingView(
            rootView: StageActionsView(manager: manager)
        )
        self.panel = panel
        trackingTask = Task { [weak panel] in
            while !Task.isCancelled {
                guard let panel else { return }
                Self.position(panel, sourceID: source.id, sourcePID: source.processIdentifier)
                do {
                    try await Task.sleep(for: .milliseconds(100))
                } catch {
                    return
                }
            }
        }
    }

    func dismiss() {
        trackingTask?.cancel()
        trackingTask = nil
        sourceID = nil
        panel?.close()
        panel = nil
    }

    private static func position(_ panel: StageActionsPanel, sourceID: CGWindowID, sourcePID: pid_t) {
        guard let snapshot = WindowFrameResolver.currentSnapshot(for: sourceID),
            snapshot.ownerPID == sourcePID,
            snapshot.isOnScreen,
            let primaryScreen = NSScreen.screens.first,
            let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
            frontmostPID == sourcePID || frontmostPID == ProcessInfo.processInfo.processIdentifier
        else {
            panel.orderOut(nil)
            return
        }

        let sourceFrame = SourceOverlayGeometry.appKitFrame(
            forQuartzFrame: snapshot.frame,
            primaryScreenFrame: primaryScreen.frame
        )
        let screen = NSScreen.screens.max { first, second in
            intersectionArea(sourceFrame, first.frame) < intersectionArea(sourceFrame, second.frame)
        }
        guard let screen,
            let frame = StageActionsPlacement.panelFrame(
                sourceFrame: sourceFrame,
                visibleScreen: screen.visibleFrame
            )
        else {
            panel.orderOut(nil)
            return
        }

        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    private static func intersectionArea(_ first: CGRect, _ second: CGRect) -> CGFloat {
        let intersection = first.intersection(second)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }
}

final class StageActionsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        title = "Stage Actions"
        identifier = BetterMeetsWindowID.stageActions
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
    }
}
