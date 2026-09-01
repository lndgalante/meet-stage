import SwiftUI

struct StageView: View {
    @ObservedObject var manager: CaptureManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            LiveStageSurface(
                manager: manager,
                reducesMotion: reduceMotion
            )

            if !manager.isLive {
                ZStack {
                    IdleStageChrome()

                    VStack(spacing: 14) {
                        if manager.state == .switching {
                            ProgressView()
                                .controlSize(.large)
                        } else {
                            Image(
                                systemName: manager.state == .paused
                                    ? "pause.circle"
                                    : "rectangle.on.rectangle.slash"
                            )
                            .font(.system(size: 48, weight: .light))
                            .foregroundStyle(.secondary)
                        }
                        Text(stageTitle)
                            .font(.title2.weight(.medium))
                        Text(stageGuidance)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .allowsHitTesting(false)
            }

            if manager.isLive,
                let keystroke = manager.keystrokePresentation
            {
                KeystrokeBadge(
                    label: keystroke.label,
                    size: keystroke.size,
                    appearance: keystroke.appearance
                )
                .id(keystroke.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 28)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .opacity.combined(with: .scale(scale: 0.92, anchor: .bottom))
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .ignoresSafeArea()
        .animation(
            reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 1),
            value: manager.keystrokePresentation?.id
        )
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.18),
            value: manager.spotlightEnabled
        )
        .onExitCommand {
            manager.finishAnnotations()
        }
        .background(
            WindowConfigurator(
                kind: .stage(aspectRatio: manager.displayedStageAspectRatio)
            )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Demo Stage"))
        .accessibilityValue(stageAccessibilityValue)
        .accessibilityHint(
            String(localized: "This is the window to share in your meeting app")
        )
        .accessibilityAction(named: String(localized: "Show Controller")) {
            BetterMeetsWindowActions.showController()
        }
        .accessibilityAction(named: String(localized: "Minimize Demo Stage")) {
            BetterMeetsWindowActions.minimizeStage()
        }
        .accessibilityAction(named: String(localized: "Toggle Demo Stage Full Screen")) {
            BetterMeetsWindowActions.toggleStageFullScreen()
        }
    }

    private var stageGuidance: String {
        let guidance: String

        switch manager.state {
        case .switching:
            guidance = String(localized: "Waiting for the first video frame")
        case .paused:
            guidance = String(localized: "Select this window again in BetterMeets to resume")
        case .permissionRequired:
            guidance = String(localized: "Allow screen recording in BetterMeets")
        case let .failed(message):
            guidance = message
        default:
            guidance = String(
                localized:
                    "Choose a window in BetterMeets, then share this\nDemo Stage window in Google Meet or Zoom"
            )
        }

        return guidance.hasSuffix(".") ? String(guidance.dropLast()) : guidance
    }

    private var stageAccessibilityValue: String {
        if manager.isLive, let source = manager.activeCaptureSource {
            return String(
                localized: "Live. Sharing \(source.applicationName), \(source.title)"
            )
        }
        return "\(stageTitle). \(stageGuidance)"
    }

    private var stageTitle: String {
        switch manager.state {
        case .switching:
            return String(localized: "Preparing the stage")
        case .paused:
            return String(localized: "Sharing is paused")
        default:
            return String(localized: "Nothing is on stage")
        }
    }
}

private struct LiveStageSurface: View {
    @ObservedObject var manager: CaptureManager
    let reducesMotion: Bool

    var body: some View {
        GeometryReader { stageGeometry in
            let frameIsStyled =
                manager.autoPresentationEnabled
                && manager.stageFrameStyle != .none
            let showsStageLogo = StageLogoVisibilityPolicy.shouldShow(
                isLive: manager.isLive,
                isAutoPresentationEnabled: manager.autoPresentationEnabled,
                hasLogo: manager.stageLogo != nil
            )
            let frameLayoutIsEnabled = frameIsStyled || showsStageLogo
            let effectivePadding =
                showsStageLogo
                ? max(manager.stageFramePadding, StageLogoAppearance.minimumStagePadding)
                : manager.stageFramePadding
            let layout = StageFrameLayout.resolve(
                viewportSize: stageGeometry.size,
                sourceAspectRatio: manager.stageAspectRatio,
                paddingFraction: effectivePadding,
                cornerRadius: frameIsStyled ? manager.stageFrameCornerRadius : 0,
                isEnabled: frameLayoutIsEnabled
            )

            ZStack {
                StageFrameBackdrop(
                    style: frameIsStyled ? manager.stageFrameStyle : .none,
                    blur: frameIsStyled ? manager.stageFrameBlur : 0
                )

                ZoomableStageContent(
                    manager: manager,
                    autoPresentation: manager.autoPresentation,
                    demoMode: manager.demoMode,
                    reducesMotion: reducesMotion
                )
                .frame(
                    width: layout.contentFrame.width,
                    height: layout.contentFrame.height
                )
                .clipped()
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: layout.cornerRadius,
                        style: .continuous
                    )
                )
                .overlay {
                    if frameIsStyled {
                        RoundedRectangle(
                            cornerRadius: layout.cornerRadius,
                            style: .continuous
                        )
                        .strokeBorder(.white.opacity(0.16), lineWidth: 1)
                    }
                }
                .shadow(
                    color: .black.opacity(
                        frameIsStyled ? 0.48 * manager.stageFrameShadow : 0
                    ),
                    radius: frameIsStyled ? 28 * manager.stageFrameShadow : 0,
                    y: frameIsStyled ? 12 * manager.stageFrameShadow : 0
                )
                .shadow(
                    color: .black.opacity(
                        frameIsStyled ? 0.22 * manager.stageFrameShadow : 0
                    ),
                    radius: frameIsStyled ? 5 * manager.stageFrameShadow : 0,
                    y: frameIsStyled ? 2 * manager.stageFrameShadow : 0
                )
                .position(
                    x: layout.contentFrame.midX,
                    y: layout.contentFrame.midY
                )

                if showsStageLogo, let logo = manager.stageLogo {
                    StageLogoOverlay(
                        image: logo,
                        contentFrame: layout.contentFrame
                    )
                }
            }
        }
        .clipped()
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Keeps high-frequency camera state below the styled-stage composition. A
/// cursor or zoom update can move the captured content without rebuilding the
/// backdrop, logo, clipping surface, or layered shadows around it.
private struct ZoomableStageContent: View {
    @ObservedObject var manager: CaptureManager
    @ObservedObject var autoPresentation: AutoPresentationSession
    @ObservedObject var demoMode: DemoModeSession
    let reducesMotion: Bool

    var body: some View {
        GeometryReader { contentGeometry in
            let allowsZoom = manager.autoPresentationEnabled || manager.demoModeEnabled
            let transform = AutoZoomTransform.resolve(
                focus: allowsZoom ? autoPresentation.zoomFocus : nil,
                requestedScale: autoPresentation.zoomScaleOverride
                    ?? manager.autoZoomSize.autoZoomScale,
                viewportSize: contentGeometry.size,
                reducesMotion: reducesMotion
            )

            ZStack {
                StageVideoRepresentable(
                    renderer: manager.renderer,
                    reducesMotion: reducesMotion
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if manager.isSpotlightVisible {
                    SpotlightSurface(session: manager.spotlight)
                        .transition(.opacity)
                }

                if manager.isLive {
                    AnnotationInkLayer(
                        session: manager.annotations,
                        acceptsInput: false
                    )
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }

                ForEach(manager.clickPresentations) { presentation in
                    ClickRippleGlyph(
                        presentation: presentation,
                        reducesMotion: reducesMotion
                    )
                    .position(
                        x: presentation.location.x * contentGeometry.size.width,
                        y: presentation.location.y * contentGeometry.size.height
                    )
                }

                if manager.isLive {
                    DemoHighlightSurface(
                        highlights: demoMode.highlights,
                        reducesMotion: reducesMotion
                    )
                }

                if manager.isLive, manager.autoPresentationEnabled {
                    EnlargedSystemCursorLayer(session: autoPresentation.cursor)
                }
            }
            .frame(
                width: contentGeometry.size.width,
                height: contentGeometry.size.height
            )
            .scaleEffect(transform.scale, anchor: .topLeading)
            .offset(transform.offset)
            .animation(
                reducesMotion
                    ? nil
                    : .spring(response: 0.26, dampingFraction: 1),
                value: transform
            )
        }
    }
}

private struct IdleStageChrome: View {
    private static let shaderLibrary: ShaderLibrary? = {
        guard
            let url = Bundle.main.url(
                forResource: "IdleStageChrome",
                withExtension: "metallib"
            )
        else { return nil }

        return ShaderLibrary(url: url)
    }()

    var body: some View {
        Group {
            if let shaderLibrary = Self.shaderLibrary {
                Color.black
                    .colorEffect(
                        shaderLibrary.idleStageChrome(
                            .boundingRect,
                            .float(20),
                            .float(34),
                            .float(1),
                            .float(1),
                            .float(0.56),
                            .float(0.2),
                            .float(1),
                            .float2(0.5, 0),
                            .color(.black),
                            .color(.white),
                            .color(Color(red: 214 / 255, green: 226 / 255, blue: 242 / 255)),
                            .color(Color(red: 196 / 255, green: 212 / 255, blue: 235 / 255)),
                            .color(Color(red: 120 / 255, green: 136 / 255, blue: 160 / 255)),
                            .color(.black)
                        )
                    )
            } else {
                Color.black
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct KeystrokeBadge: View {
    let label: String
    let size: PresentationSize
    let appearance: KeystrokeAppearance

    @Environment(\.legibilityWeight) private var legibilityWeight

    var body: some View {
        Text(label)
            .font(
                .system(
                    size: metrics.fontSize,
                    weight: legibilityWeight == .bold ? .bold : .semibold,
                    design: .rounded
                )
            )
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.vertical, metrics.verticalPadding)
            .background(
                backgroundColor,
                in: RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.32), radius: 8, y: 3)
    }

    private var metrics: KeystrokeBadgeMetrics {
        KeystrokeBadgeMetrics(size: size)
    }

    private var foregroundColor: Color {
        appearance == .dark ? .white : .black.opacity(0.82)
    }

    private var backgroundColor: Color {
        appearance == .dark ? .black.opacity(0.78) : .white.opacity(0.92)
    }

    private var borderColor: Color {
        appearance == .dark ? .white.opacity(0.22) : .black.opacity(0.16)
    }
}

private struct KeystrokeBadgeMetrics {
    let fontSize: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let cornerRadius: CGFloat

    init(size: PresentationSize) {
        switch size {
        case .small:
            fontSize = 14
            horizontalPadding = 12
            verticalPadding = 7
            cornerRadius = 8
        case .medium:
            fontSize = 18
            horizontalPadding = 16
            verticalPadding = 9
            cornerRadius = 10
        case .large:
            fontSize = 24
            horizontalPadding = 21
            verticalPadding = 11
            cornerRadius = 13
        }
    }
}

private struct StageVideoRepresentable: NSViewRepresentable {
    let renderer: SampleBufferRenderer
    let reducesMotion: Bool

    final class Coordinator {
        var renderer: SampleBufferRenderer

        init(renderer: SampleBufferRenderer) {
            self.renderer = renderer
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(renderer: renderer)
    }

    func makeNSView(context: Context) -> StageVideoView {
        let view = StageVideoView()
        view.reducesMotion = reducesMotion
        renderer.attach(view)
        return view
    }

    func updateNSView(_ nsView: StageVideoView, context: Context) {
        if context.coordinator.renderer !== renderer {
            context.coordinator.renderer.detach(nsView)
            context.coordinator.renderer = renderer
            renderer.attach(nsView)
        }
        nsView.reducesMotion = reducesMotion
    }

    static func dismantleNSView(_ nsView: StageVideoView, coordinator: Coordinator) {
        coordinator.renderer.detach(nsView)
        nsView.clearForDismantle()
    }
}
