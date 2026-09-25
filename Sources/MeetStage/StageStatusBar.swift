import SwiftUI

struct StageStatusBar: View {
    @ObservedObject var manager: CaptureManager

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(statusColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(manager.sourceGuidance.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if manager.isLive {
                Button("Open App", systemImage: "arrow.up.forward.app") {
                    manager.focusSelectedSourceIfPossible()
                }
                .help("Bring the source app forward to interact with it (⇧⌘O)")
            }
            Button("Stop", systemImage: "stop.fill") { manager.stopCapture() }
                .disabled(!manager.canStopCapture)
                .help("Clear the stage (⌘.)")
        }
        .controlSize(.small)
        .padding(.horizontal, 14)
        .frame(height: 52)
    }

    private var detail: String {
        switch manager.state {
        case .capturing:
            manager.selectedSource?.title ?? "Share this BetterMeets window in your meeting"
        case .paused:
            "Your audience sees a paused stage"
        default:
            manager.sourceGuidance.hint
        }
    }

    private var symbol: String {
        switch manager.sourceGuidance.status {
        case .ready: "rectangle.on.rectangle"
        case .busy: "ellipsis"
        case .live: "circle.fill"
        case .paused: "pause.fill"
        case .warning: "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch manager.sourceGuidance.status {
        case .live: .accentColor
        case .paused, .warning: .orange
        case .ready, .busy: .secondary
        }
    }
}
