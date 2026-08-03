import SwiftUI

struct StageView: View {
    @ObservedObject var manager: CaptureManager

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            StageVideoRepresentable(renderer: manager.renderer)

            if !manager.isCapturing {
                VStack(spacing: 14) {
                    Image(systemName: "rectangle.on.rectangle.slash")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("Nothing is on stage")
                        .font(.title2.weight(.medium))
                    Text("Choose a window in the Meet Stage controller.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .background(WindowConfigurator(kind: .stage))
    }
}

private struct StageVideoRepresentable: NSViewRepresentable {
    let renderer: SampleBufferRenderer

    func makeNSView(context: Context) -> StageVideoView {
        let view = StageVideoView()
        renderer.attach(view)
        return view
    }

    func updateNSView(_ nsView: StageVideoView, context: Context) {
        renderer.attach(nsView)
    }

    static func dismantleNSView(_ nsView: StageVideoView, coordinator: Void) {
        nsView.clear()
    }
}
