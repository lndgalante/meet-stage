import SwiftUI

/// The workspace toolbar: what's on stage on the leading edge, then the
/// presentation effects and the stage's own Pause and Clear on the trailing edge.
struct StageToolbar: ToolbarContent {
    @ObservedObject var manager: CaptureManager

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            StageSourceTitle(manager: manager)
        }
        // A title, not a control, so it sits outside the glass.
        .sharedBackgroundVisibility(.hidden)
        ToolbarSpacer(.flexible)
        ToolbarItemGroup {
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
        ToolbarSpacer(.fixed)
        ToolbarItemGroup {
            Button(action: manager.toggleCapturePause) {
                stageLabel(
                    manager.state == .paused ? "Resume Stage" : "Pause Stage",
                    systemImage: manager.state == .paused ? "play.fill" : "pause.fill")
            }
            .disabled(!manager.canToggleCapturePause)
            .help(
                manager.state == .paused ? "Show the source again (⇧⌘P)" : "Hide the source and pause the stage (⇧⌘P)")
            Button(action: manager.stopCapture) {
                stageLabel("Clear Stage", systemImage: "stop.fill")
            }
            .disabled(!manager.canStopCapture)
            .help("Remove the source without stopping a share in your meeting app (⌘.)")
        }
    }

    /// Text and icon with the same breathing room the icon-only effects get.
    private func stageLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 6)
    }

    private func effect(
        _ title: String, systemImage: String, isOn: Bool, help: String, action: @escaping () -> Void
    ) -> some View {
        Toggle(isOn: Binding(get: { isOn }, set: { _ in action() })) {
            Label(title, systemImage: systemImage)
        }
        .toggleStyle(.button)
        .labelStyle(.iconOnly)
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
            .frame(maxWidth: 320, alignment: .leading)
        }
        .help(helpText)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(helpText)
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
        case .busy: ProgressView().controlSize(.mini)
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
    }

    private var helpText: String {
        [name, detail].compactMap { $0 }.joined(separator: " — ")
    }
}
