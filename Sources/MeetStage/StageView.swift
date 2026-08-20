import SwiftUI

struct StageView: View {
    @ObservedObject var manager: CaptureManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            StageVideoRepresentable(
                renderer: manager.renderer,
                reducesMotion: reduceMotion
            )
            .ignoresSafeArea()

            if manager.isLive, !manager.clickPresentations.isEmpty {
                GeometryReader { geometry in
                    ForEach(manager.clickPresentations) { presentation in
                        ClickRippleGlyph(reducesMotion: reduceMotion)
                            .position(
                                x: presentation.location.x * geometry.size.width,
                                y: presentation.location.y * geometry.size.height
                            )
                    }
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }

            if !manager.isLive {
                ZStack {
                    Color.black
                        .ignoresSafeArea()

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
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                }
                .allowsHitTesting(false)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(stageAccessibilityLabel)
            }

            if manager.isLive,
                let keystroke = manager.keystrokePresentation
            {
                KeystrokeBadge(label: keystroke.label)
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
        .animation(
            reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 1),
            value: manager.keystrokePresentation?.id
        )
        .background(WindowConfigurator(kind: .stage(aspectRatio: manager.stageAspectRatio)))
    }

    private var stageGuidance: String {
        switch manager.state {
        case .switching:
            return "Waiting for the first video frame."
        case .paused:
            return "Select this window again in BetterDemos to resume."
        case .permissionRequired:
            return "Allow screen recording in BetterDemos."
        case .failed:
            return "Capture stopped. Choose a window to try again."
        default:
            return "Choose a window in BetterDemos."
        }
    }

    private var stageAccessibilityLabel: String {
        "\(stageTitle). \(stageGuidance)"
    }

    private var stageTitle: String {
        switch manager.state {
        case .switching:
            return "Preparing the stage"
        case .paused:
            return "Sharing is paused"
        default:
            return "Nothing is on stage"
        }
    }
}

private struct KeystrokeBadge: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                Color.black.opacity(0.78),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.32), radius: 8, y: 3)
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
        }
        nsView.reducesMotion = reducesMotion
        renderer.attach(nsView)
    }

    static func dismantleNSView(_ nsView: StageVideoView, coordinator: Coordinator) {
        coordinator.renderer.detach(nsView)
        nsView.clearForDismantle()
    }
}
