import SwiftUI

struct StageStatusBar: View {
    @ObservedObject var manager: CaptureManager

    var body: some View {
        GeometryReader { geometry in
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

                if manager.isLive {
                    Button {
                        manager.focusSelectedSourceIfPossible()
                    } label: {
                        if geometry.size.width > 700 {
                            Label("Open Source App", systemImage: "arrow.up.forward.app")
                        } else {
                            Image(systemName: "arrow.up.forward.app")
                        }
                    }
                    .accessibilityLabel("Open Source App")
                    .help("Open the source app to interact with it (⇧⌘O)")
                }
                if manager.canStopCapture {
                    Button(
                        manager.state == .paused ? "Resume" : "Pause",
                        systemImage: manager.state == .paused ? "play.fill" : "pause.fill",
                        action: manager.toggleCapturePause
                    )
                    .disabled(!manager.canToggleCapturePause)
                    .help(manager.state == .paused ? "Resume stage (⇧⌘P)" : "Hide the source and pause the stage (⇧⌘P)")
                    Button("Clear Stage", systemImage: "stop.fill", action: manager.stopCapture)
                        .help("Remove the source without stopping a share in your meeting app (⌘.)")
                } else {
                    Button("How to Present", systemImage: "questionmark.circle") {
                        UtilityWindows.showGuide()
                    }
                }
            }
            .controlSize(.regular)
            .padding(.horizontal, 14)
            .frame(maxHeight: .infinity)
        }
        .frame(height: 60)
    }

    private var detail: String {
        switch manager.state {
        case .capturing:
            manager.selectedSource.flatMap { $0.hasDistinctTitle ? $0.title : nil }
                ?? "Use Open Source App to interact"
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
