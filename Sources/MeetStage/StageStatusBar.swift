import SwiftUI

struct StageStatusBar: View {
    @ObservedObject var manager: CaptureManager

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(statusColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(manager.sourceGuidance.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .help("\(manager.sourceGuidance.title). \(detail)")
            .frame(maxWidth: .infinity, alignment: .leading)

            if manager.canStopCapture {
                Button(
                    manager.state == .paused ? "Resume Stage" : "Pause Stage",
                    systemImage: manager.state == .paused ? "play.fill" : "pause.fill",
                    action: manager.toggleCapturePause
                )
                .disabled(!manager.canToggleCapturePause)
                .help(manager.state == .paused ? "Resume stage (⇧⌘P)" : "Hide the source and pause the stage (⇧⌘P)")
                Button("Clear Stage", systemImage: "stop.fill", action: manager.stopCapture)
                    .help("Remove the source without stopping a share in your meeting app (⌘.)")
            }
        }
        .controlSize(.regular)
        .padding(.horizontal, 4)
        .frame(height: 40)
    }

    private var detail: String {
        switch manager.state {
        case .capturing:
            manager.selectedSource.flatMap { $0.hasDistinctTitle ? $0.title : nil }
                ?? "Switch windows using the sidebar"
        case .paused: "Source hidden until you resume"
        default: manager.sourceGuidance.hint
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
