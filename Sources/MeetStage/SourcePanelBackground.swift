import SwiftUI

struct SourcePanelBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: ControlWindowSizing.panelCornerRadius, style: .continuous)
            .fill(
                reduceTransparency
                    ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
                    : AnyShapeStyle(.regularMaterial)
            )
            .overlay {
                RoundedRectangle(cornerRadius: ControlWindowSizing.panelCornerRadius, style: .continuous)
                    .fill(colorScheme == .dark ? .black.opacity(0.55) : .white.opacity(0.20))
            }
            .overlay {
                RoundedRectangle(cornerRadius: ControlWindowSizing.panelCornerRadius, style: .continuous)
                    .strokeBorder(.primary.opacity(contrast == .increased ? 0.5 : 0.18), lineWidth: 1)
            }
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
        .padding(.horizontal, 12)
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
