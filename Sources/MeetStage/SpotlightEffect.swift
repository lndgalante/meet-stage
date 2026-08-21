import AppKit
import SwiftUI

enum SpotlightVisibilityPolicy {
    static func shouldShow(
        isEnabled: Bool,
        captureState: CaptureState,
        hasActiveCapture: Bool,
        hasSelectedWindow: Bool
    ) -> Bool {
        isEnabled
            && captureState == .capturing
            && hasActiveCapture
            && hasSelectedWindow
    }
}

enum SpotlightAppearance {
    static let defaultOutsideOpacity = 0.24
    static let outsideBlurOpacity = 0.64
    static let outsideOpacityRange = 0.0...0.65

    static func normalizedOutsideOpacity(_ value: Double) -> Double {
        min(max(value, outsideOpacityRange.lowerBound), outsideOpacityRange.upperBound)
    }

}

enum SpotlightGeometry {
    static let maximumWindowCoverage: CGFloat = 0.82

    static func normalizedLocation(
        for globalLocation: CGPoint,
        in sourceFrame: CGRect
    ) -> NormalizedWindowPoint? {
        guard sourceFrame.width > 0,
            sourceFrame.height > 0,
            globalLocation.x >= sourceFrame.minX,
            globalLocation.x <= sourceFrame.maxX,
            globalLocation.y >= sourceFrame.minY,
            globalLocation.y <= sourceFrame.maxY
        else { return nil }

        return NormalizedWindowPoint(
            x: (globalLocation.x - sourceFrame.minX) / sourceFrame.width,
            y: (globalLocation.y - sourceFrame.minY) / sourceFrame.height
        )
    }

    static func apertureDiameter(
        in viewportSize: CGSize,
        size: PresentationSize = .medium
    ) -> CGFloat {
        let shortestEdge = min(viewportSize.width, viewportSize.height)
        guard shortestEdge > 0 else { return 0 }
        let metrics = SpotlightSizeMetrics(size: size)

        return min(
            max(shortestEdge * metrics.proportionalDiameter, metrics.minimumDiameter),
            shortestEdge * maximumWindowCoverage,
            metrics.maximumDiameter
        )
    }

    static func apertureRect(
        at location: NormalizedWindowPoint,
        in viewportSize: CGSize,
        size: PresentationSize = .medium
    ) -> CGRect {
        let diameter = apertureDiameter(in: viewportSize, size: size)
        guard diameter > 0 else { return .zero }

        let center = CGPoint(
            x: min(max(location.x, 0), 1) * viewportSize.width,
            y: min(max(location.y, 0), 1) * viewportSize.height
        )
        let radius = diameter / 2
        return CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: diameter,
            height: diameter
        )
    }
}

private struct SpotlightSizeMetrics {
    let minimumDiameter: CGFloat
    let maximumDiameter: CGFloat
    let proportionalDiameter: CGFloat

    init(size: PresentationSize) {
        switch size {
        case .small:
            minimumDiameter = 112
            maximumDiameter = 280
            proportionalDiameter = 0.32
        case .medium:
            minimumDiameter = 144
            maximumDiameter = 360
            proportionalDiameter = 0.42
        case .large:
            minimumDiameter = 176
            maximumDiameter = 480
            proportionalDiameter = 0.56
        }
    }
}

@MainActor
final class SpotlightSession: ObservableObject {
    @Published private(set) var location = NormalizedWindowPoint(x: 0.5, y: 0.5)
    @Published private(set) var size: PresentationSize
    @Published private(set) var outsideOpacity: Double

    init(
        size: PresentationSize = .medium,
        outsideOpacity: Double = SpotlightAppearance.defaultOutsideOpacity
    ) {
        self.size = size
        self.outsideOpacity = SpotlightAppearance.normalizedOutsideOpacity(outsideOpacity)
    }

    func move(to location: NormalizedWindowPoint) {
        self.location = NormalizedWindowPoint(
            x: min(max(location.x, 0), 1),
            y: min(max(location.y, 0), 1)
        )
    }

    func setSize(_ value: PresentationSize) {
        size = value
    }

    func setOutsideOpacity(_ value: Double) {
        outsideOpacity = SpotlightAppearance.normalizedOutsideOpacity(value)
    }

}

struct SpotlightSurface: View {
    @ObservedObject var session: SpotlightSession

    var body: some View {
        GeometryReader { geometry in
            let aperture = SpotlightGeometry.apertureRect(
                at: session.location,
                in: geometry.size,
                size: session.size
            )

            SpotlightEffectLayer(
                aperture: aperture,
                outsideOpacity: session.outsideOpacity
            )
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct SpotlightEffectLayer: View {
    let aperture: CGRect
    let outsideOpacity: Double

    var body: some View {
        let outside = SpotlightOutsideShape(aperture: aperture)

        ZStack {
            outside
                .fill(.ultraThinMaterial, style: FillStyle(eoFill: true))
                .opacity(SpotlightAppearance.outsideBlurOpacity)

            outside
                .fill(
                    Color.black.opacity(
                        SpotlightAppearance.normalizedOutsideOpacity(outsideOpacity)
                    ),
                    style: FillStyle(eoFill: true)
                )

            Circle()
                .strokeBorder(Color.white.opacity(0.26), lineWidth: 1)
                .frame(width: aperture.width, height: aperture.height)
                .position(x: aperture.midX, y: aperture.midY)
                .shadow(color: Color.black.opacity(0.32), radius: 3, y: 1)
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct SpotlightOutsideShape: Shape {
    let aperture: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addEllipse(in: aperture)
        return path
    }
}

@MainActor
final class GlobalPointerMonitor {
    typealias Handler = @MainActor (CGPoint) -> Void

    private let handler: Handler
    private let resources = PointerMonitorResources()

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    var observesLocalApplicationEvents: Bool {
        resources.localMonitor != nil
    }

    func start() {
        guard resources.globalMonitor == nil,
            resources.localMonitor == nil
        else { return }

        let eventMask: NSEvent.EventTypeMask = [
            .mouseMoved,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged
        ]
        resources.globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: eventMask
        ) { [weak self] event in
            self?.dispatch(event)
        }
        resources.localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: eventMask
        ) { [weak self] event in
            self?.dispatch(event)
            return event
        }
    }

    func stop() {
        if let globalMonitor = resources.globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            resources.globalMonitor = nil
        }
        if let localMonitor = resources.localMonitor {
            NSEvent.removeMonitor(localMonitor)
            resources.localMonitor = nil
        }
    }

    private nonisolated func dispatch(_ event: NSEvent) {
        guard let location = event.cgEvent?.location else { return }
        Task { @MainActor [weak self] in
            self?.handler(location)
        }
    }
}

private final class PointerMonitorResources: @unchecked Sendable {
    var globalMonitor: Any?
    var localMonitor: Any?

    deinit {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }
}

@MainActor
final class SourceSpotlightPresenter {
    private var panel: SpotlightPanel?
    private var frameTrackingTask: Task<Void, Never>?
    private var sourceWindowID: CGWindowID?
    private var fallbackSourceFrame = CGRect.zero

    deinit {
        frameTrackingTask?.cancel()
    }

    func show(
        session: SpotlightSession,
        sourceWindowID: CGWindowID,
        fallbackSourceFrame: CGRect
    ) {
        if panel != nil, self.sourceWindowID == sourceWindowID {
            return
        }
        dismiss()

        self.sourceWindowID = sourceWindowID
        self.fallbackSourceFrame = fallbackSourceFrame

        let panel = SpotlightPanel(
            contentRect: overlayFrame(),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        SpotlightWindowPolicy.configure(panel)
        panel.contentView = NSHostingView(
            rootView: SpotlightSurface(session: session)
        )
        self.panel = panel
        panel.orderFrontRegardless()

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

enum SpotlightWindowPolicy {
    static let sourceOverlayLevel = NSWindow.Level(
        rawValue: NSWindow.Level.normal.rawValue + 1
    )

    @MainActor
    static func configure(_ panel: SpotlightPanel) {
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.ignoresMouseEvents = true
        panel.level = sourceOverlayLevel
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .transient
        ]
    }
}

final class SpotlightPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
