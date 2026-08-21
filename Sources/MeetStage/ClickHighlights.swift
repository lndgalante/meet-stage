import AppKit
import Foundation
import SwiftUI

struct ClickPresentation: Equatable, Identifiable, Sendable {
    static let duration = Duration.milliseconds(560)

    let id = UUID()
    let location: NormalizedWindowPoint
    let color: PresentationColor
    let size: PresentationSize
}

/// Captures the same mouse event in Quartz and AppKit coordinates so a ripple
/// can be aligned on both the Demo Stage and a source-window overlay.
struct GlobalClickLocation: Equatable, Sendable {
    let quartzX: CGFloat
    let quartzY: CGFloat
    let appKitX: CGFloat
    let appKitY: CGFloat

    var quartzPoint: CGPoint {
        CGPoint(x: quartzX, y: quartzY)
    }

    var appKitPoint: CGPoint {
        CGPoint(x: appKitX, y: appKitY)
    }
}

enum ClickPresentationGeometry {
    static func appKitOverlayFrame(
        sourceFrame: CGRect,
        globalClickLocation: CGPoint,
        appKitClickLocation: CGPoint
    ) -> CGRect {
        let localX = globalClickLocation.x - sourceFrame.minX
        let localYFromTop = globalClickLocation.y - sourceFrame.minY

        return CGRect(
            x: appKitClickLocation.x - localX,
            y: appKitClickLocation.y - (sourceFrame.height - localYFromTop),
            width: sourceFrame.width,
            height: sourceFrame.height
        )
    }
}

@MainActor
final class SourceClickRipplePresenter {
    private var panels: [UUID: NSPanel] = [:]
    private var dismissTasks: [UUID: Task<Void, Never>] = [:]

    func show(
        _ presentation: ClickPresentation,
        sourceFrame: CGRect,
        clickLocation: GlobalClickLocation
    ) {
        let panel = ClickThroughPanel(
            contentRect: ClickPresentationGeometry.appKitOverlayFrame(
                sourceFrame: sourceFrame,
                globalClickLocation: clickLocation.quartzPoint,
                appKitClickLocation: clickLocation.appKitPoint
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .transient
        ]
        panel.contentView = NSHostingView(
            rootView: SourceClickRippleSurface(
                presentation: presentation,
                reducesMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            )
        )

        panels[presentation.id] = panel
        panel.orderFrontRegardless()

        dismissTasks[presentation.id]?.cancel()
        dismissTasks[presentation.id] = Task { [weak self] in
            do {
                try await Task.sleep(for: ClickPresentation.duration)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.dismiss(presentation.id)
        }
    }

    func dismissAll() {
        dismissTasks.values.forEach { $0.cancel() }
        dismissTasks.removeAll()
        panels.values.forEach { $0.close() }
        panels.removeAll()
    }

    private func dismiss(_ id: UUID) {
        dismissTasks[id]?.cancel()
        dismissTasks[id] = nil
        panels.removeValue(forKey: id)?.close()
    }
}

private final class ClickThroughPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct SourceClickRippleSurface: View {
    let presentation: ClickPresentation
    let reducesMotion: Bool

    var body: some View {
        GeometryReader { geometry in
            ClickRippleGlyph(
                presentation: presentation,
                reducesMotion: reducesMotion
            )
            .position(
                x: presentation.location.x * geometry.size.width,
                y: presentation.location.y * geometry.size.height
            )
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct ClickRippleGlyph: View {
    let presentation: ClickPresentation
    let reducesMotion: Bool

    @State private var isReceding = false

    var body: some View {
        let metrics = ClickRippleMetrics(size: presentation.size)
        let color = presentation.color.color

        ZStack {
            Circle()
                .stroke(color, lineWidth: isReceding ? 1.5 : 3)
                .frame(
                    width: reducesMotion
                        ? metrics.reducedMotionDiameter
                        : (isReceding ? metrics.expandedDiameter : metrics.initialDiameter),
                    height: reducesMotion
                        ? metrics.reducedMotionDiameter
                        : (isReceding ? metrics.expandedDiameter : metrics.initialDiameter)
                )
                .opacity(isReceding ? 0 : 0.95)

            Circle()
                .fill(color)
                .frame(width: metrics.dotDiameter, height: metrics.dotDiameter)
                .scaleEffect(isReceding ? 0.75 : 1)
                .opacity(isReceding ? 0 : 1)
        }
        .frame(width: metrics.canvasDiameter, height: metrics.canvasDiameter)
        .shadow(color: .black.opacity(0.34), radius: 2, y: 1)
        .task {
            await Task.yield()
            withAnimation(.easeOut(duration: reducesMotion ? 0.22 : 0.46)) {
                isReceding = true
            }
        }
    }
}

struct ClickRippleMetrics: Equatable, Sendable {
    let initialDiameter: CGFloat
    let reducedMotionDiameter: CGFloat
    let expandedDiameter: CGFloat
    let dotDiameter: CGFloat
    let canvasDiameter: CGFloat

    init(size: PresentationSize) {
        switch size {
        case .small:
            initialDiameter = 10
            reducedMotionDiameter = 19
            expandedDiameter = 42
            dotDiameter = 7
            canvasDiameter = 46
        case .medium:
            initialDiameter = 12
            reducedMotionDiameter = 24
            expandedDiameter = 54
            dotDiameter = 8
            canvasDiameter = 58
        case .large:
            initialDiameter = 14
            reducedMotionDiameter = 30
            expandedDiameter = 68
            dotDiameter = 10
            canvasDiameter = 72
        }
    }
}
