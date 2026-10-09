import SwiftUI

/// The floating widget beside the source window: the demo and the stage first,
/// then every presentation effect in order of how often presenters reach for it.
struct StageActionsView: View {
    @ObservedObject var manager: CaptureManager
    @ObservedObject var demo: DemoSession
    @Environment(\.legibilityWeight) private var legibilityWeight

    init(manager: CaptureManager) {
        self.manager = manager
        demo = manager.demo
    }

    var body: some View {
        VStack(spacing: StageActionsMetrics.spacing) {
            if showsDemo {
                FloatingDemoButton(demo: demo)
            }
            ControlBarButton(
                systemImage: manager.state == .paused ? "play.fill" : "pause.fill",
                title: manager.state == .paused ? "Resume Stage" : "Pause Stage",
                help: manager.state == .paused ? "Resume the selected source" : "Hide the source and pause the stage",
                isEnabled: manager.canToggleCapturePause,
                action: manager.toggleCapturePause
            )
            Divider().padding(.horizontal, 12)
            ControlBarButton(
                systemImage: "wand.and.sparkles",
                title: "Auto Polish",
                help: manager.autoPresentationEnabled
                    ? "Auto-zoom clicks, mirror the pointer at 2× and frame the stage"
                    : "Polish the stage with activity zooms, a 2× pointer and a styled frame",
                isOn: manager.autoPresentationEnabled,
                action: { manager.toggleAutoPresentation() }
            )
            ControlBarButton(
                systemImage: "magnifyingglass",
                title: "Spotlight",
                help: spotlightControlHelp,
                isOn: manager.spotlightEnabled,
                action: { manager.toggleSpotlight() }
            )
            ControlBarButton(
                systemImage: "pencil.and.outline",
                title: "Annotations",
                help: annotationControlHelp,
                isOn: manager.annotationsEnabled,
                action: { manager.toggleAnnotations() }
            )
            ControlBarButton(
                systemImage: "cursorarrow.rays",
                title: "Click Highlights",
                help: "Show click ripples on the source window and stage",
                isOn: manager.highlightsMouseClicks,
                glyphOffset: ControlMetrics.clickHighlightGlyphOffset,
                action: manager.toggleMouseClickHighlighting
            )
            ControlBarButton(
                systemImage: "command.square",
                title: "Keystrokes",
                help: manager.needsKeystrokeAccessibilityPermission
                    ? "Allow Accessibility access, then turn on keystroke highlighting"
                    : "Highlight keystrokes on the stage",
                isOn: manager.highlightsKeystrokes,
                glyphOffset: ControlMetrics.keystrokeHighlightGlyphOffset,
                showsPermissionWarning: manager.needsKeystrokeAccessibilityPermission,
                action: manager.toggleKeystrokeHighlighting
            )
            Divider().padding(.horizontal, 12)
            moreMenu
        }
        .padding(.vertical, StageActionsMetrics.inset)
        .frame(width: StageActionsMetrics.panelWidth)
        .background {
            PresenterPanelBackground(cornerRadius: StageActionsMetrics.cornerRadius, drawsShadow: false)
        }
        .fontWeight(legibilityWeight == .bold ? .bold : nil)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Stage actions")
    }

    /// The demo button appears once this app has a demo.
    private var showsDemo: Bool { demo.demo != nil && demo.phase != .composing }

    private var moreMenu: some View {
        Menu {
            Button("Clear Stage", action: manager.stopCapture)
                .disabled(!manager.canStopCapture)
            Button("Show BetterMeets") {
                BetterMeetsWindowState.shared.stageOnly = false
                BetterMeetsWindowActions.showStage()
            }
            Button("Settings…") { UtilityWindows.showSettings(manager: manager) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: ControlMetrics.controlBarIconSize, weight: .medium))
                .frame(width: StageActionsMetrics.actionSize, height: StageActionsMetrics.actionSize)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(height: ControlMetrics.controlBarButtonHeight)
        .help("Clear Stage, Show BetterMeets and Settings")
        .accessibilityLabel("More")
    }

    private var annotationControlHelp: String {
        if manager.isAnnotating {
            return String(localized: "Draw temporary ink over the selected app window")
        }
        if manager.annotationsEnabled {
            return manager.state == .paused
                ? String(localized: "Annotations will resume when sharing resumes")
                : String(localized: "Annotations will start when a window is live")
        }
        return manager.isLive
            ? String(localized: "Draw temporary ink over the selected app window")
            : String(localized: "Enable annotations for the next shared window")
    }

    private var spotlightControlHelp: String {
        if manager.spotlightEnabled {
            return manager.isLive
                ? String(localized: "Move the pointer to focus part of the selected window")
                : String(localized: "The spotlight will appear when a window is live")
        }
        return manager.isLive
            ? String(localized: "Dim and softly blur everything outside the pointer spotlight")
            : String(localized: "Enable the spotlight for the next shared window")
    }
}

private struct FloatingDemoButton: View {
    @ObservedObject var demo: DemoSession

    var body: some View {
        let isActive = demo.phase.isActuating
        let action = PanelActionID.floatingPrimary(in: demo.phase)
        ControlBarButton(
            systemImage: isActive ? "pause.rectangle.fill" : "play.rectangle",
            title: action.menuTitle,
            help: action.help(context),
            isOn: isActive,
            isEnabled: isActive || canContinue,
            action: { action.perform(on: demo) }
        )
    }

    private var context: PanelActionID.Context {
        let phase = demo.phase
        let count = demo.demo?.steps.count ?? 0
        return .init(
            app: demo.selectedSource?.name ?? "this app", start: demo.demo?.startLabel ?? "the starting screen",
            step: min((phase.currentStep ?? phase.nextStep) + 1, max(count, 1)))
    }

    private var canContinue: Bool {
        guard demo.isLiveSourceSelected else { return false }
        switch demo.phase {
        case .ready, .finished: return demo.canPlay
        case .paused, .offTrack: return true
        case .needsStart(.webContentUnavailable, _): return false
        case .needsStart(.noAutomaticReturn, _): return demo.canReturnAutomatically
        case .needsStart: return true
        case .scoutPaused(let stop): return stop.canKeepBuilding
        default: return false
        }
    }
}
