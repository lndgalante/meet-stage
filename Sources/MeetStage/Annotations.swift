import AppKit
import Foundation
import SwiftUI

struct AnnotationStroke: Equatable, Identifiable, Sendable {
    let id: UUID
    var points: [NormalizedWindowPoint]
    let color: PresentationColor
    var opacity: Double
    var fadeDuration: TimeInterval
    var geometry: AnnotationStrokeGeometry = .freehand
}

enum AnnotationStrokeGeometry: Equatable, Sendable {
    case freehand
    case circle(center: NormalizedWindowPoint, diameter: CGFloat)
    case rectangle(NormalizedAnnotationBounds)
}

struct NormalizedAnnotationBounds: Equatable, Sendable {
    let minX: CGFloat
    let minY: CGFloat
    let width: CGFloat
    let height: CGFloat

    func resolved(in rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX + minX * rect.width,
            y: rect.minY + minY * rect.height,
            width: width * rect.width,
            height: height * rect.height
        )
    }
}

enum AnnotationTiming {
    static let defaultLifetimeSeconds = 4
    static let supportedLifetimeSeconds = [2, 4, 6, 10]
    static let standardFadeDuration: TimeInterval = 0.55
    static let reducedMotionFadeDuration: TimeInterval = 0.18

    static func normalizedLifetimeSeconds(_ value: Int) -> Int {
        // UserDefaults is an untrusted persistence boundary. Clamp before
        // subtracting so Int.min/Int.max cannot overflow the distance check.
        guard let minimum = supportedLifetimeSeconds.first,
            let maximum = supportedLifetimeSeconds.last
        else { return defaultLifetimeSeconds }
        if value <= minimum { return minimum }
        if value >= maximum { return maximum }

        return
            supportedLifetimeSeconds.min {
                abs($0 - value) < abs($1 - value)
            }
            ?? defaultLifetimeSeconds
    }
}

enum AnnotationGeometry {
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
    @Published private(set) var inkColor: PresentationColor

    private var fadeTasks: [UUID: Task<Void, Never>] = [:]
    private let sleep: @Sendable (Duration) async throws -> Void

    init(
        lifetimeSeconds: Int = AnnotationTiming.defaultLifetimeSeconds,
        inkColor: PresentationColor = .orange,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        }
    ) {
        self.lifetimeSeconds = AnnotationTiming.normalizedLifetimeSeconds(lifetimeSeconds)
        self.inkColor = inkColor
        self.sleep = sleep
    }

    deinit {
        fadeTasks.values.forEach { $0.cancel() }
    }

    var isEmpty: Bool {
        strokes.isEmpty
    }

    func snapshot() -> [AnnotationStroke] {
        strokes
    }

    func registerUndo(
        restoring snapshot: [AnnotationStroke],
        with undoManager: UndoManager?,
        actionName: String,
        reducesMotion: Bool
    ) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { session in
            session.restoreForUndo(
                snapshot,
                with: undoManager,
                actionName: actionName,
                reducesMotion: reducesMotion
            )
        }
        undoManager.setActionName(actionName)
    }

    @discardableResult
    func beginStroke(at point: NormalizedWindowPoint) -> UUID {
        let stroke = AnnotationStroke(
            id: UUID(),
            points: [point],
            color: inkColor,
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
        canvasSize: CGSize? = nil,
        reducesMotion: Bool
    ) {
        guard let index = strokes.firstIndex(where: { $0.id == id }) else { return }

        if let canvasSize,
            let recognizedGeometry = AnnotationShapeRecognizer.recognize(
                points: strokes[index].points,
                in: canvasSize
            )
        {
            strokes[index].geometry = recognizedGeometry
        }

        scheduleFade(for: id, reducesMotion: reducesMotion)
    }

    /// Adds a ready-made shape (used by Demo Mode's voice "circle this" command),
    /// which fades on the same timer as a drawn stroke.
    @discardableResult
    func addShape(_ geometry: AnnotationStrokeGeometry, reducesMotion: Bool) -> UUID {
        let stroke = AnnotationStroke(
            id: UUID(),
            points: [],
            color: inkColor,
            opacity: 1,
            fadeDuration: AnnotationTiming.standardFadeDuration,
            geometry: geometry
        )
        strokes.append(stroke)
        scheduleFade(for: stroke.id, reducesMotion: reducesMotion)
        return stroke.id
    }

    private func scheduleFade(for id: UUID, reducesMotion: Bool) {
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

    private func restoreForUndo(
        _ snapshot: [AnnotationStroke],
        with undoManager: UndoManager,
        actionName: String,
        reducesMotion: Bool
    ) {
        let inverse = strokes
        registerUndo(
            restoring: inverse,
            with: undoManager,
            actionName: actionName,
            reducesMotion: reducesMotion
        )

        fadeTasks.values.forEach { $0.cancel() }
        fadeTasks.removeAll()
        strokes = snapshot.map { stroke in
            var restored = stroke
            restored.opacity = 1
            restored.fadeDuration = AnnotationTiming.standardFadeDuration
            return restored
        }
        strokes.forEach { scheduleFade(for: $0.id, reducesMotion: reducesMotion) }
    }

    func setLifetimeSeconds(_ value: Int) {
        lifetimeSeconds = AnnotationTiming.normalizedLifetimeSeconds(value)
    }

    func setInkColor(_ value: PresentationColor) {
        inkColor = value
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

/// Converts pointer updates into annotation-domain operations without relying
/// on window-server event delivery. Keeping this small state machine outside
/// the SwiftUI view makes drag behavior deterministic and directly testable.
@MainActor
struct AnnotationInputController {
    private(set) var activeStrokeID: UUID?
    private var activeCanvasSize: CGSize?
    private var undoSnapshot: [AnnotationStroke]?

    mutating func update(
        location: CGPoint,
        canvasSize: CGSize,
        session: AnnotationSession
    ) {
        guard
            let point = WindowCoordinateGeometry.normalizedPoint(
                clamping: location,
                in: canvasSize
            )
        else { return }

        if let activeStrokeID {
            session.append(point, to: activeStrokeID)
        } else {
            undoSnapshot = session.snapshot()
            activeStrokeID = session.beginStroke(at: point)
        }
        activeCanvasSize = canvasSize
    }

    mutating func finish(
        session: AnnotationSession,
        reducesMotion: Bool,
        undoManager: UndoManager? = nil
    ) {
        guard let activeStrokeID else { return }
        session.endStroke(
            activeStrokeID,
            canvasSize: activeCanvasSize,
            reducesMotion: reducesMotion
        )
        if let undoSnapshot {
            session.registerUndo(
                restoring: undoSnapshot,
                with: undoManager,
                actionName: "Draw Annotation",
                reducesMotion: reducesMotion
            )
        }
        self.activeStrokeID = nil
        activeCanvasSize = nil
        undoSnapshot = nil
    }
}

struct AnnotationInkLayer: View {
    @ObservedObject var session: AnnotationSession
    let acceptsInput: Bool
    var undoManager: UndoManager? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var inputController = AnnotationInputController()
    @State private var isUsingCrosshairCursor = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(session.strokes) { stroke in
                    let shape = AnnotationStrokePath(stroke: stroke)
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
                                stroke.color.color,
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
                        .accessibilityHint(
                            "Drag the pointer to draw temporary ink. Rough circles and rectangles snap into clean shapes."
                        )
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
                inputController.update(
                    location: value.location,
                    canvasSize: size,
                    session: session
                )
            }
            .onEnded { _ in
                finishActiveStroke()
            }
    }

    private func finishActiveStroke() {
        inputController.finish(
            session: session,
            reducesMotion: reduceMotion,
            undoManager: undoManager
        )
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

private struct AnnotationStrokePath: Shape {
    let stroke: AnnotationStroke

    func path(in rect: CGRect) -> Path {
        switch stroke.geometry {
        case .freehand:
            freehandPath(in: rect)
        case .circle(let center, let diameter):
            circlePath(center: center, diameter: diameter, in: rect)
        case .rectangle(let bounds):
            Path(bounds.resolved(in: rect))
        }
    }

    private func freehandPath(in rect: CGRect) -> Path {
        let points = stroke.points
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

    private func circlePath(
        center: NormalizedWindowPoint,
        diameter: CGFloat,
        in rect: CGRect
    ) -> Path {
        let resolvedDiameter = diameter * min(rect.width, rect.height)
        let resolvedCenter = CGPoint(
            x: rect.minX + center.x * rect.width,
            y: rect.minY + center.y * rect.height
        )
        return Path(
            ellipseIn: CGRect(
                x: resolvedCenter.x - resolvedDiameter / 2,
                y: resolvedCenter.y - resolvedDiameter / 2,
                width: resolvedDiameter,
                height: resolvedDiameter
            )
        )
    }
}
