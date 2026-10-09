import SwiftUI

/// The card above the stage: what's on stage on the leading edge, then the
/// presentation effects and the stage's own Pause and Clear on the trailing edge.
struct StageHeader: View {
    @ObservedObject var manager: CaptureManager

    var body: some View {
        HStack(spacing: 12) {
            StageSourceTitle(manager: manager)
                .layoutPriority(1)
            Spacer(minLength: 0)
            // Pause and Clear drop their labels before the title runs out of room.
            ViewThatFits(in: .horizontal) {
                controls(compact: false)
                controls(compact: true)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: WorkspaceMetrics.headerHeight)
        .background { WindowDragArea() }
        .workspacePanel()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Stage controls")
    }

    private func controls(compact: Bool) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                effect(
                    "Auto Polish", systemImage: "wand.and.sparkles", isOn: manager.autoPresentationEnabled,
                    help: "Zoom into activity, enlarge the pointer and frame the stage (⌥⌘P)"
                ) { manager.toggleAutoPresentation(focusSource: false) }
                effect(
                    "Spotlight", systemImage: "magnifyingglass", isOn: manager.spotlightEnabled,
                    help: "Dim everything outside the pointer (⌥⌘F)"
                ) { manager.toggleSpotlight(focusSource: false) }
                effect(
                    "Annotations", systemImage: "pencil.and.outline", isOn: manager.annotationsEnabled,
                    help: "Draw temporary ink over the app (⌥⌘A)"
                ) { manager.toggleAnnotations(focusSource: false) }
                effect(
                    "Click Highlights", systemImage: "cursorarrow.rays", isOn: manager.highlightsMouseClicks,
                    help: "Show click ripples (⌥⌘C)", action: manager.toggleMouseClickHighlighting)
                effect(
                    "Keystrokes", systemImage: "command.square", isOn: manager.highlightsKeystrokes,
                    help: manager.needsKeystrokeAccessibilityPermission
                        ? "Allow Accessibility access, then show keystrokes (⌥⌘K)" : "Show keystrokes on the stage (⌥⌘K)",
                    action: manager.toggleKeystrokeHighlighting)
            }
            HStack(spacing: 4) {
                Button(action: manager.toggleCapturePause) {
                    stageLabel(
                        manager.state == .paused ? "Resume Stage" : "Pause Stage",
                        systemImage: manager.state == .paused ? "play.fill" : "pause.fill", compact: compact)
                }
                .disabled(!manager.canToggleCapturePause)
                .help(
                    manager.state == .paused
                        ? "Show the source again (⇧⌘P)" : "Hide the source and pause the stage (⇧⌘P)")
                Button(action: manager.stopCapture) {
                    stageLabel("Clear Stage", systemImage: "stop.fill", compact: compact)
                }
                .disabled(!manager.canStopCapture)
                .help("Remove the source without stopping a share in your meeting app (⌘.)")
            }
            .buttonStyle(.accessoryBarAction)
        }
        .font(.callout)
        .fixedSize()
    }

    @ViewBuilder private func stageLabel(_ title: String, systemImage: String, compact: Bool) -> some View {
        let label = Label(title, systemImage: systemImage)
        if compact {
            label.labelStyle(.iconOnly)
        } else {
            label.labelStyle(.titleAndIcon)
        }
    }

    private func effect(
        _ title: String, systemImage: String, isOn: Bool, help: String, action: @escaping () -> Void
    ) -> some View {
        Toggle(isOn: Binding(get: { isOn }, set: { _ in action() })) {
            Label(title, systemImage: systemImage)
        }
        .toggleStyle(.button)
        .buttonStyle(.accessoryBar)
        .labelStyle(.iconOnly)
        .modifier(ActiveTint(isOn: isOn))
        .help(help)
        .accessibilityLabel(title)
    }
}

/// The app on stage: its icon and name, its state, and the window's title.
private struct StageSourceTitle: View {
    @ObservedObject var manager: CaptureManager

    var body: some View {
        HStack(spacing: 8) {
            icon.frame(width: 24, height: 24)
            WidthCap(maxWidth: 320) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(name).font(.headline).lineLimit(1)
                        stateBadge
                    }
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        // Like a window title, it moves the window; the drag area also shows the full title.
        .overlay { WindowDragArea(help: helpText) }
    }

    @ViewBuilder private var icon: some View {
        if let image = manager.selectedSource?.applicationIcon {
            Image(nsImage: image)
                .resizable()
        } else {
            Image(systemName: "rectangle.on.rectangle")
                .foregroundStyle(.secondary)
        }
    }

    private var name: String {
        switch manager.state {
        case .capturing, .paused: manager.selectedSource?.applicationName ?? manager.sourceGuidance.title
        default: manager.sourceGuidance.title
        }
    }

    private var detail: String? {
        switch manager.state {
        case .capturing, .paused:
            manager.selectedSource.flatMap { $0.hasDistinctTitle ? $0.title : nil }
        default:
            manager.sourceGuidance.hint
        }
    }

    @ViewBuilder private var stateBadge: some View {
        switch manager.sourceGuidance.status {
        case .live: badge("On stage", symbol: "circle.fill", tint: .accentColor)
        case .paused: badge("Paused", symbol: "pause.fill", tint: .orange)
        case .warning: badge("Needs attention", symbol: "exclamationmark.triangle.fill", tint: .orange)
        case .busy: ProgressView().controlSize(.mini).accessibilityLabel("Working")
        case .ready: EmptyView()
        }
    }

    private func badge(_ text: String, symbol: String, tint: Color) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol).font(.system(size: 6, weight: .bold))
        }
        .labelStyle(.titleAndIcon)
        .font(.caption.weight(.medium))
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .background(tint.opacity(0.14), in: Capsule())
        // A long app name truncates; the state never does.
        .fixedSize()
    }

    private var helpText: String {
        [name, detail].compactMap { $0 }.joined(separator: " — ")
    }
}

/// The accent marks a tool that's on, as in the floating widget; off keeps the bar's own style.
private struct ActiveTint: ViewModifier {
    let isOn: Bool

    func body(content: Content) -> some View {
        if isOn {
            content.foregroundStyle(Color.accentColor)
        } else {
            content
        }
    }
}

/// Caps its content's width without growing to the cap, as `frame(maxWidth:)`
/// does, so a short title leaves Pause and Clear room for their labels.
private struct WidthCap: Layout {
    let maxWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(capped(proposal)) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // The proposal, not the measured bounds, which can round a hair short of the text and truncate it.
        subviews.first?.place(at: bounds.origin, proposal: capped(proposal))
    }

    private func capped(_ proposal: ProposedViewSize) -> ProposedViewSize {
        ProposedViewSize(width: min(proposal.width ?? .infinity, maxWidth), height: proposal.height)
    }
}
