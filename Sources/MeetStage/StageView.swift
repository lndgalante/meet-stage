import SwiftUI

struct StageView: View {
    @ObservedObject var manager: CaptureManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            StageVideoRepresentable(
                renderer: manager.renderer,
                reducesMotion: reduceMotion
            )
                .ignoresSafeArea()

            if !manager.isLive {
                VStack(spacing: 14) {
                    if manager.state == .switching {
                        ProgressView()
                            .controlSize(.large)
                    } else {
                        Image(systemName: "rectangle.on.rectangle.slash")
                            .font(.system(size: 48, weight: .light))
                            .foregroundStyle(.secondary)
                    }
                    Text(manager.state == .switching ? "Preparing the stage" : "Nothing is on stage")
                        .font(.title2.weight(.medium))
                    Text(stageGuidance)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .allowsHitTesting(false)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(stageAccessibilityLabel)
            }
        }
        .background(WindowConfigurator(kind: .stage(aspectRatio: manager.stageAspectRatio)))
    }

    private var stageGuidance: String {
        switch manager.state {
        case .switching:
            return "Waiting for the first video frame."
        case .permissionRequired:
            return "Allow screen recording in BetterDemos."
        case .failed:
            return "Capture stopped. Choose a window to try again."
        default:
            return "Choose a window in BetterDemos."
        }
    }

    private var stageAccessibilityLabel: String {
        let title = manager.state == .switching ? "Preparing the stage" : "Nothing is on stage"
        return "\(title). \(stageGuidance)"
    }
}

private struct StageVideoRepresentable: NSViewRepresentable {
    let renderer: SampleBufferRenderer
    let reducesMotion: Bool

    func makeNSView(context: Context) -> StageVideoView {
        let view = StageVideoView()
        view.reducesMotion = reducesMotion
        renderer.attach(view)
        return view
    }

    func updateNSView(_ nsView: StageVideoView, context: Context) {
        nsView.reducesMotion = reducesMotion
        renderer.attach(nsView)
    }

    static func dismantleNSView(_ nsView: StageVideoView, coordinator: Void) {
        nsView.clear()
    }
}
