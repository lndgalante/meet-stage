import AppKit
import Foundation
import SwiftUI

struct AnnotationStroke: Equatable, Identifiable, Sendable {
    let id: UUID
    var points: [NormalizedWindowPoint]
    var opacity: Double
    var fadeDuration: TimeInterval
}

enum AnnotationTiming {
    static let defaultLifetimeSeconds = 4
    static let supportedLifetimeSeconds = [2, 4, 6, 10]
    static let standardFadeDuration: TimeInterval = 0.55
    static let reducedMotionFadeDuration: TimeInterval = 0.18

    static func normalizedLifetimeSeconds(_ value: Int) -> Int {
        supportedLifetimeSeconds.min { abs($0 - value) < abs($1 - value) }
            ?? defaultLifetimeSeconds
    }
}

enum AnnotationGeometry {
    static func normalizedPoint(
        for location: CGPoint,
        in size: CGSize
    ) -> NormalizedWindowPoint? {
        guard size.width > 0, size.height > 0 else { return nil }

        return NormalizedWindowPoint(
            x: min(max(location.x / size.width, 0), 1),
            y: min(max(location.y / size.height, 0), 1)
        )
    }

    static func appKitOverlayFrame(
        sourceFrame: CGRect,
        primaryScreenFrame: CGRect
    ) -> CGRect {
        CGRect(
            x: sourceFrame.minX,
            y: primaryScreenFrame.maxY - sourceFrame.maxY,
            width: sourceFrame.width,
            height: sourceFrame.height
        )
    }

    static func shouldAppend(
        _ point: NormalizedWindowPoint,
        after previousPoint: NormalizedWindowPoint
    ) -> Bool {
        let deltaX = point.x - previousPoint.x
        let deltaY = point.y - previousPoint.y
        return deltaX * deltaX + deltaY * deltaY >= 0.000_001
    }
}

@MainActor
final class AnnotationSession: ObservableObject {
    @Published private(set) var strokes: [AnnotationStroke] = []
    @Published private(set) var lifetimeSeconds: Int

    private var fadeTasks: [UUID: Task<Void, Never>] = [:]
    private let sleep: @Sendable (Duration) async throws -> Void

    init(
        lifetimeSeconds: Int = AnnotationTiming.defaultLifetimeSeconds,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        }
    ) {
        self.lifetimeSeconds = AnnotationTiming.normalizedLifetimeSeconds(lifetimeSeconds)
        self.sleep = sleep
    }

    deinit {
        fadeTasks.values.forEach { $0.cancel() }
    }

    var isEmpty: Bool {
        strokes.isEmpty
    }

    @discardableResult
    func beginStroke(at point: NormalizedWindowPoint) -> UUID {
        let stroke = AnnotationStroke(
            id: UUID(),
            points: [point],
            opacity: 1,
            fadeDuration: AnnotationTiming.standardFadeDuration
        )
        strokes.append(stroke)
        return stroke.id
    }

    func append(_ point: NormalizedWindowPoint, to id: UUID) {
        guard let index = strokes.firstIndex(where: { $0.id == id }),
            let previousPoint = strokes[index].points.last,
            AnnotationGeometry.shouldAppend(point, after: previousPoint)
        else { return }

        strokes[index].points.append(point)
    }

    func endStroke(
        _ id: UUID,
        reducesMotion: Bool
    ) {
        guard strokes.contains(where: { $0.id == id }) else { return }

        let strokeLifetimeSeconds = lifetimeSeconds
        let sleep = sleep
        fadeTasks[id]?.cancel()
        fadeTasks[id] = Task { [weak self] in
            do {
                try await sleep(.seconds(strokeLifetimeSeconds))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }

            let fadeDuration =
                reducesMotion
                ? AnnotationTiming.reducedMotionFadeDuration
                : AnnotationTiming.standardFadeDuration
            self?.beginFade(for: id, duration: fadeDuration)

            do {
                try await sleep(.seconds(fadeDuration))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.removeStroke(id)
        }
    }

    func clear() {
        fadeTasks.values.forEach { $0.cancel() }
        fadeTasks.removeAll()
        strokes.removeAll()
    }

    func setLifetimeSeconds(_ value: Int) {
        lifetimeSeconds = AnnotationTiming.normalizedLifetimeSeconds(value)
    }

    private func beginFade(for id: UUID, duration: TimeInterval) {
        guard let index = strokes.firstIndex(where: { $0.id == id }) else { return }
        strokes[index].fadeDuration = duration
        strokes[index].opacity = 0
    }

    private func removeStroke(_ id: UUID) {
        fadeTasks[id]?.cancel()
        fadeTasks[id] = nil
        strokes.removeAll { $0.id == id }
    }
}

struct AnnotationInkLayer: View {
    @ObservedObject var session: AnnotationSession
    let acceptsInput: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activeStrokeID: UUID?
    @State private var isUsingCrosshairCursor = false

    private let inkColor = Color(red: 1, green: 0.36, blue: 0.14)

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(session.strokes) { stroke in
                    let shape = AnnotationStrokeShape(points: stroke.points)
                    let lineWidth = min(max(min(geometry.size.width, geometry.size.height) * 0.009, 3.5), 8)

                    ZStack {
                        shape
                            .stroke(
                                Color.black.opacity(0.46),
                                style: StrokeStyle(
                                    lineWidth: lineWidth + 3,
                                    lineCap: .round,
                                    lineJoin: .round
                                )
                            )

                        shape
                            .stroke(
                                inkColor,
                                style: StrokeStyle(
                                    lineWidth: lineWidth,
                                    lineCap: .round,
                                    lineJoin: .round
                                )
                            )
                            .shadow(color: Color.black.opacity(0.24), radius: 1.5, y: 1)
                    }
                    .opacity(stroke.opacity)
                    .animation(
                        .easeOut(duration: stroke.fadeDuration),
                        value: stroke.opacity
                    )
                }

                if acceptsInput {
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(drawingGesture(in: geometry.size))
                        .onHover(perform: updateCursor)
                        .accessibilityLabel("Annotation canvas")
                        .accessibilityHint("Drag the pointer to draw temporary ink")
                }
            }
        }
        .clipped()
        .onDisappear {
            finishActiveStroke()
            restoreCursorIfNeeded()
        }
    }

    private func drawingGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard
                    let point = AnnotationGeometry.normalizedPoint(
                        for: value.location,
                        in: size
                    )
                else { return }

                if let activeStrokeID {
                    session.append(point, to: activeStrokeID)
                } else {
                    activeStrokeID = session.beginStroke(at: point)
                }
            }
            .onEnded { _ in
                finishActiveStroke()
            }
    }

    private func finishActiveStroke() {
        guard let activeStrokeID else { return }
        session.endStroke(
            activeStrokeID,
            reducesMotion: reduceMotion
        )
        self.activeStrokeID = nil
    }

    private func updateCursor(_ isHovering: Bool) {
        if isHovering, !isUsingCrosshairCursor {
            NSCursor.crosshair.push()
            isUsingCrosshairCursor = true
        } else if !isHovering {
            restoreCursorIfNeeded()
        }
    }

    private func restoreCursorIfNeeded() {
        guard isUsingCrosshairCursor else { return }
        NSCursor.pop()
        isUsingCrosshairCursor = false
    }
}

private struct AnnotationStrokeShape: Shape {
    let points: [NormalizedWindowPoint]

    func path(in rect: CGRect) -> Path {
        guard let firstPoint = points.first else { return Path() }

        let resolvedPoints = points.map {
            CGPoint(
                x: rect.minX + $0.x * rect.width,
                y: rect.minY + $0.y * rect.height
            )
        }
        var path = Path()

        if resolvedPoints.count == 1 {
            path.move(to: resolvedPoints[0])
            path.addLine(to: CGPoint(x: resolvedPoints[0].x + 0.01, y: resolvedPoints[0].y))
            return path
        }

        path.move(
            to: CGPoint(
                x: (firstPoint.x * rect.width) + rect.minX,
                y: (firstPoint.y * rect.height) + rect.minY
            ))
        for index in 1..<resolvedPoints.count {
            let previous = resolvedPoints[index - 1]
            let current = resolvedPoints[index]
            let midpoint = CGPoint(
                x: (previous.x + current.x) / 2,
                y: (previous.y + current.y) / 2
            )
            path.addQuadCurve(to: midpoint, control: previous)
        }
        if let lastPoint = resolvedPoints.last {
            path.addLine(to: lastPoint)
        }
        return path
    }
}

@MainActor
final class SourceAnnotationPresenter {
    private var panel: AnnotationPanel?
    private var frameTrackingTask: Task<Void, Never>?
    private var sourceWindowID: CGWindowID?
    private var fallbackSourceFrame = CGRect.zero

    deinit {
        frameTrackingTask?.cancel()
    }

    func show(
        session: AnnotationSession,
        sourceWindowID: CGWindowID,
        fallbackSourceFrame: CGRect,
        onFinish: @escaping @MainActor () -> Void
    ) {
        dismiss()

        self.sourceWindowID = sourceWindowID
        self.fallbackSourceFrame = fallbackSourceFrame

        let panel = AnnotationPanel(
            contentRect: overlayFrame(),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        AnnotationWindowPolicy.configure(panel)
        panel.onCancel = onFinish
        panel.contentView = NSHostingView(
            rootView: SourceAnnotationSurface(
                session: session,
                onFinish: onFinish
            )
        )
        self.panel = panel
        panel.orderFrontRegardless()
        panel.makeKey()

        frameTrackingTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(100))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                self?.updatePanelFrame()
            }
        }
    }

    func dismiss() {
        frameTrackingTask?.cancel()
        frameTrackingTask = nil
        sourceWindowID = nil
        panel?.close()
        panel = nil
    }

    private func updatePanelFrame() {
        guard let panel else { return }
        let frame = overlayFrame()
        guard frame != panel.frame else { return }
        panel.setFrame(frame, display: true)
    }

    private func overlayFrame() -> CGRect {
        let sourceFrame =
            sourceWindowID.map {
                WindowFrameResolver.currentFrame(for: $0, fallback: fallbackSourceFrame)
            } ?? fallbackSourceFrame
        let primaryScreenFrame =
            NSScreen.screens.first?.frame
            ?? CGRect(x: 0, y: 0, width: sourceFrame.width, height: sourceFrame.maxY)
        return AnnotationGeometry.appKitOverlayFrame(
            sourceFrame: sourceFrame,
            primaryScreenFrame: primaryScreenFrame
        )
    }
}

enum AnnotationWindowPolicy {
    // The selected source windows are normal-level, while BetterDemos' compact
    // controller is floating. This slot keeps ink above the source without
    // making the controller unreachable when the two overlap.
    static let sourceOverlayLevel = NSWindow.Level(
        rawValue: NSWindow.Level.normal.rawValue + 1
    )

    @MainActor
    static func configure(_ panel: AnnotationPanel) {
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = sourceOverlayLevel
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .transient
        ]
    }
}

final class AnnotationPanel: NSPanel {
    var onCancel: (@MainActor () -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }
}

struct SourceAnnotationSurface: View {
    @ObservedObject var session: AnnotationSession
    let onFinish: @MainActor () -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                AnnotationInkLayer(
                    session: session,
                    acceptsInput: true
                )

                if geometry.size.width >= 320, geometry.size.height >= 160 {
                    annotationModeIndicator
                        .padding(.top, 12)
                }
            }
        }
        .background(Color.clear)
    }

    private var annotationModeIndicator: some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil.tip")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(red: 0.21, green: 0.84, blue: 1))

            Text("Drawing")
                .font(.caption.weight(.semibold))

            Text("Esc")
                .font(.system(.caption2, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4, style: .continuous))

            Button("Done", action: onFinish)
                .buttonStyle(.borderless)
                .font(.caption.weight(.semibold))
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.28), radius: 8, y: 3)
        .accessibilityElement(children: .contain)
    }
}
