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
    @State private var isShowingSettings = false
    @Environment(\.legibilityWeight) private var legibilityWeight

    var body: some View {
        VStack(spacing: controlSpacing) {
            if layout == .sidebar {
                Text("Tools")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 4)
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
                action: manager.toggleAutoPresentation,
                settingsAction: { showSettings(.stage) }
            )

            ControlBarButton(
                systemImage: "magnifyingglass",
                title: "Spotlight",
                help: spotlightControlHelp,
                isOn: manager.spotlightEnabled,
                action: manager.toggleSpotlight,
                settingsAction: { showSettings(.spotlight) }
            )

            ControlBarButton(
                systemImage: "pencil.and.outline",
                title: "Annotate",
                help: annotationControlHelp,
                isOn: manager.annotationsEnabled,
                action: manager.toggleAnnotations,
                settingsAction: { showSettings(.annotations) }
            )
        }
    }

    private var lowerControls: some View {
        VStack(spacing: controlSpacing) {
            ControlBarButton(
                systemImage: "cursorarrow.rays",
                title: "Click Highlights",
                help: "Show click ripples on the selected window and Demo Stage",
                isOn: manager.highlightsMouseClicks,
                glyphOffset: ControlMetrics.clickHighlightGlyphOffset,
                action: manager.toggleMouseClickHighlighting,
                settingsAction: { showSettings(.clicks) }
            )

            ControlBarButton(
                systemImage: "command.square",
                title: "Keystrokes",
                help: manager.needsKeystrokeAccessibilityPermission
                    ? "Allow Accessibility access, then turn on keystroke highlighting"
                    : "Highlight keystrokes on the Demo Stage",
                isOn: manager.highlightsKeystrokes,
                glyphOffset: ControlMetrics.keystrokeHighlightGlyphOffset,
                showsPermissionWarning: manager.needsKeystrokeAccessibilityPermission,
                action: manager.toggleKeystrokeHighlighting,
                settingsAction: { showSettings(.keystrokes) }
            )

            ControlBarButton(
                systemImage: "gearshape",
                title: "Settings",
                help: "Open Settings",
                isPresented: isShowingSettings,
                action: { isShowingSettings.toggle() }
            )
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
                    "Polish the Demo Stage with activity zooms, a 2× system pointer, and a styled frame"
            )
    }

}
