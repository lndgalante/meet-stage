import SwiftUI

struct StageActionsView: View {
    @ObservedObject var manager: CaptureManager
    @State private var isShowingSettings = false
    @Environment(\.legibilityWeight) private var legibilityWeight

    var body: some View {
        VStack(spacing: StageActionsMetrics.spacing) {
            upperControls
            demoHero
                .padding(.vertical, 4)
            lowerControls
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

    private var demoHero: some View {
        DemoHeroButton(
            isListening: manager.demoModeEnabled,
            showsPermissionWarning: manager.needsMicrophonePermission
                || manager.demoModeNeedsClickAccessibility
                || manager.demoModeUnavailableReason != nil,
            help: demoModeControlHelp,
            action: manager.toggleDemoMode,
            settingsAction: { showSettings(.voice) }
        )
    }

    private var upperControls: some View {
        VStack(spacing: StageActionsMetrics.spacing) {
            ControlBarButton(
                systemImage: "wand.and.sparkles",
                title: "Auto polish",
                help: autoPresentationControlHelp,
                isOn: manager.autoPresentationEnabled,
                action: manager.toggleAutoPresentation,
                settingsAction: { showSettings(.stage) }
            )
            .frame(width: ControlMetrics.controlBarActionSize)

            ControlBarButton(
                systemImage: "magnifyingglass",
                title: "Focus spotlight",
                help: spotlightControlHelp,
                isOn: manager.spotlightEnabled,
                action: manager.toggleSpotlight,
                settingsAction: { showSettings(.spotlight) }
            )
            .frame(width: ControlMetrics.controlBarActionSize)

            ControlBarButton(
                systemImage: "pencil.and.outline",
                title: "Annotate",
                help: annotationControlHelp,
                isOn: manager.annotationsEnabled,
                action: manager.toggleAnnotations,
                settingsAction: { showSettings(.annotations) }
            )
            .frame(width: ControlMetrics.controlBarActionSize)
        }
    }

    private var lowerControls: some View {
        VStack(spacing: StageActionsMetrics.spacing) {
            ControlBarButton(
                systemImage: "cursorarrow.rays",
                title: "Highlight clicks",
                help: "Show click ripples on the selected window and Demo Stage",
                isOn: manager.highlightsMouseClicks,
                glyphOffset: ControlMetrics.clickHighlightGlyphOffset,
                action: manager.toggleMouseClickHighlighting,
                settingsAction: { showSettings(.clicks) }
            )
            .frame(width: ControlMetrics.controlBarActionSize)

            ControlBarButton(
                systemImage: "command.square",
                title: "Highlight keystrokes",
                help: manager.needsKeystrokeAccessibilityPermission
                    ? "Allow Accessibility access, then turn on keystroke highlighting"
                    : "Highlight keystrokes on the Demo Stage",
                isOn: manager.highlightsKeystrokes,
                glyphOffset: ControlMetrics.keystrokeHighlightGlyphOffset,
                showsPermissionWarning: manager.needsKeystrokeAccessibilityPermission,
                action: manager.toggleKeystrokeHighlighting,
                settingsAction: { showSettings(.keystrokes) }
            )
            .frame(width: ControlMetrics.controlBarActionSize)

            ControlBarButton(
                systemImage: "gearshape",
                title: "Settings",
                help: "Open Settings",
                isPresented: isShowingSettings,
                action: { isShowingSettings.toggle() }
            )
            .frame(width: ControlMetrics.controlBarActionSize)
            .popover(isPresented: $isShowingSettings, arrowEdge: .trailing) {
                BetterMeetsSettingsView(manager: manager)
                    .fixedSize()
            }
        }
    }

    private func showSettings(_ tab: SettingsTab) {
        UserDefaults.standard.set(tab.rawValue, forKey: SettingsTab.storageKey)
        isShowingSettings = true
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
                    "Polish the Demo Stage with activity zooms, a 2× system pointer, and a styled frame"
            )
    }

    private var demoModeControlHelp: String {
        if manager.needsMicrophonePermission {
            return String(localized: "Allow microphone access, then turn on Demo Mode")
        }
        if let reason = manager.demoModeUnavailableReason {
            return reason
        }
        if manager.demoModeEnabled {
            if manager.demoMode.isListening {
                return manager.demoModeNeedsClickAccessibility
                    ? String(
                        localized:
                            "Listening — allow Accessibility to open controls, not just highlight them"
                    )
                    : String(
                        localized:
                            "Listening — name a control to highlight it, or say “click” to open it"
                    )
            }
            return String(localized: "Demo Mode starts listening when a window is live")
        }
        return String(localized: "Highlight and open controls by voice as you narrate your demo")
    }

}
