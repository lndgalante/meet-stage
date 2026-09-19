import SwiftUI

struct SourcePanelBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ControlWindowSizing.panelCornerRadius, style: .continuous)
    }

    var body: some View {
        Group {
            if reduceTransparency {
                shape.fill(Color(nsColor: .windowBackgroundColor))
            } else {
                shape.fill(.clear)
                    .glassEffect(.clear, in: shape)
            }
        }
        .overlay {
            if contrast == .increased || reduceTransparency {
                shape.strokeBorder(.primary.opacity(contrast == .increased ? 0.5 : 0.18), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }
}

struct SourceStatusFooter: View {
    let guidance: SourceSelectionGuidance

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 12)
                .accessibilityHidden(true)

            Text(guidance.title)
                .font(.system(size: 11, weight: .medium))
                .layoutPriority(1)

            Spacer(minLength: 8)

            Text(guidance.hint)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .padding(.horizontal, ControlWindowSizing.sourceRailInset)
        .frame(height: ControlWindowSizing.guidanceHeight)
        .contentShape(Rectangle())
        .help(guidance.message)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(guidance.message)
    }

    private var symbol: String {
        switch guidance.status {
        case .ready: "macwindow"
        case .busy: "ellipsis"
        case .live: "circle.fill"
        case .paused: "pause.fill"
        case .warning: "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch guidance.status {
        case .ready, .busy: .secondary
        case .live: ControlPalette.accent
        case .paused, .warning: ControlPalette.warning
        }
    }
}
