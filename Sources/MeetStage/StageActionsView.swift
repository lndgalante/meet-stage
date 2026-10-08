import SwiftUI

enum StageActionLayout {
    case sidebar, floating
}

extension EnvironmentValues {
    @Entry var stageActionLayout = StageActionLayout.sidebar
}

struct StageActionsView: View {
    @ObservedObject var manager: CaptureManager
    var layout: StageActionLayout = .sidebar
    @Environment(\.legibilityWeight) private var legibilityWeight

    var body: some View {
        VStack(spacing: controlSpacing) {
            if layout == .floating {
                floatingCaptureControls
                Divider().padding(.horizontal, 12)
            }
            upperControls
            lowerControls
        }
        .padding(.vertical, StageActionsMetrics.inset)
        .padding(.horizontal, layout == .sidebar ? 10 : 0)
        .frame(width: layout == .floating ? StageActionsMetrics.panelWidth : nil)
        .background {
            if layout == .floating {
                PresenterPanelBackground(cornerRadius: StageActionsMetrics.cornerRadius, drawsShadow: false)
            }
        }
        .environment(\.stageActionLayout, layout)
        .fontWeight(legibilityWeight == .bold ? .bold : nil)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Stage actions")
    }

    private var upperControls: some View {
        VStack(spacing: controlSpacing) {
            ControlBarButton(
                systemImage: "wand.and.sparkles",
                title: "Auto Polish",
                help: autoPresentationControlHelp,
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
        }
    }

    private var lowerControls: some View {
        VStack(spacing: controlSpacing) {
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

            if layout == .floating {
                ControlBarButton(
                    systemImage: "gearshape",
                    title: "Settings",
                    help: "Open Settings",
                    action: { UtilityWindows.showSettings(manager: manager) }
                )
            }
        }
    }

    private var floatingCaptureControls: some View {
        VStack(spacing: StageActionsMetrics.spacing) {
            FloatingDemoButton(demo: manager.demo)
            ControlBarButton(
                systemImage: manager.state == .paused ? "play.fill" : "pause.fill",
                title: manager.state == .paused ? "Resume Stage" : "Pause Stage",
                help: manager.state == .paused ? "Resume the selected source" : "Hide the source and pause the stage",
                isEnabled: manager.canToggleCapturePause,
                action: manager.toggleCapturePause
            )
            ControlBarButton(
                systemImage: "stop.fill", title: "Clear Stage",
                help: "Remove the source from the stage",
                isEnabled: manager.canStopCapture, action: manager.stopCapture
            )
            ControlBarButton(
                systemImage: "sidebar.left", title: "Show Controls",
                help: "Show BetterMeets controls. They will be visible if this window is shared.",
                action: {
                    BetterMeetsWindowState.shared.stageOnly = false
                    BetterMeetsWindowActions.showStage()
                }
            )
        }
    }

    private var controlSpacing: CGFloat {
        layout == .floating ? StageActionsMetrics.spacing : 4
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

    private var autoPresentationControlHelp: String {
        manager.autoPresentationEnabled
            ? String(
                localized:
                    "Auto-zoom clicks, mirror the system pointer at 2×, and apply the selected frame"
            )
            : String(
                localized:
                    "Polish the stage with activity zooms, a 2× system pointer, and a styled frame"
            )
    }

}

private struct FloatingDemoButton: View {
    @ObservedObject var demo: DemoSession

    var body: some View {
        let isActive = demo.phase.isActuating
        ControlBarButton(
            systemImage: isActive ? "pause.rectangle.fill" : "play.rectangle",
            title: title,
            help: isActive ? "Pause and keep the current view" : "Play or continue the real-time demo",
            isOn: isActive,
            isEnabled: isActive || canContinue,
            action: {
                if isActive {
                    demo.pause()
                } else if case .needsStart = demo.phase {
                    demo.returnToStart()
                } else {
                    demo.play()
                }
            }
        )
    }

    private var title: String {
        switch demo.phase {
        case .scouting: "Stop Building"
        case .running(.verify, _, _): "Pause Check"
        case .running, .returning: "Pause Demo"
        case .paused, .offTrack: "Continue"
        case .scoutPaused: "Keep Building"
        case .needsStart: "Return to Start"
        default: "Play Demo"
        }
    }

    private var canContinue: Bool {
        guard demo.isLiveSourceSelected else { return false }
        switch demo.phase {
        case .ready, .finished: return demo.canPlay
        case .paused, .offTrack: return true
        case .needsStart(let mismatch, _): return mismatch != .noAutomaticReturn && mismatch != .webContentUnavailable
        case .scoutPaused(let stop): return stop.canKeepBuilding
        default: return false
        }
    }
}
