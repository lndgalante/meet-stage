import SwiftUI

struct WorkspaceView: View {
    @ObservedObject var manager: CaptureManager
    @ObservedObject private var windowState = BetterMeetsWindowState.shared
    @Environment(\.colorSchemeContrast) private var contrast
    @FocusState private var stageIsFocused: Bool

    var body: some View {
        Group {
            if windowState.stageOnly {
                stage
            } else {
                HStack(spacing: WorkspaceMetrics.gutter) {
                    VStack(spacing: 0) {
                        // The window's close, minimize and zoom buttons sit here, level with the header.
                        WindowDragArea()
                            .frame(height: WorkspaceMetrics.headerHeight)
                        ControlView(manager: manager)
                    }
                    .frame(width: WorkspaceMetrics.sidebarWidth)
                    .workspacePanel()
                    VStack(spacing: WorkspaceMetrics.gutter) {
                        StageHeader(manager: manager)
                        stage
                            .overlay { DemoDrivingGlow(demo: manager.demo, cornerRadius: 16) }
                        DemoPanelSlot(manager: manager, demo: manager.demo)
                    }
                    .frame(minWidth: 440)
                }
                .padding(WorkspaceMetrics.gutter)
                // The gutters around the cards move the window too, as a title bar would.
                .background { WindowDragArea() }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: WorkspaceMetrics.minimumSize.width, minHeight: WorkspaceMetrics.minimumSize.height)
        .background(WindowConfigurator(hidesWindowButtons: windowState.stageOnly))
        .background(StageActionsInstaller(manager: manager))
        .ignoresSafeArea(.container, edges: .top)
        .task {
            manager.startWindowMonitoring()
            manager.refreshWindows()
        }
        .onChange(of: windowState.stageOnly) { _, stageOnly in
            if stageOnly {
                stageIsFocused = true
            }
        }
    }

    private var stage: some View {
        Group {
            if !manager.isLive && !windowState.stageOnly {
                StageSetupView(manager: manager)
            } else {
                GeometryReader { geometry in
                    let size = WorkspaceMetrics.stageSize(
                        fitting: geometry.size,
                        aspectRatio: manager.displayedStageAspectRatio
                    )
                    StageView(manager: manager)
                        .frame(width: size.width, height: size.height)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .focusable()
                        .focusEffectDisabled()
                        .focused($stageIsFocused)
                        .onKeyPress(.escape) {
                            guard windowState.stageOnly else { return .ignored }
                            windowState.stageOnly = false
                            return .handled
                        }
                }
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: windowState.stageOnly ? 0 : 16))
        .overlay {
            if !windowState.stageOnly {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.primary.opacity(contrast == .increased ? 0.5 : 0.10), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .contextMenu {
            Button(windowState.stageOnly ? "Show Controls" : "Stage Only") {
                windowState.toggleStageOnly()
            }
            Button(manager.state == .paused ? "Resume Stage" : "Pause Stage") {
                manager.toggleCapturePause()
            }
            .disabled(!manager.canToggleCapturePause)
            Button("Open Source App") { manager.focusSelectedSourceIfPossible() }
                .disabled(!manager.isLive)
        }
    }
}

/// The demo panel, once a window is chosen. Until then the stage's setup
/// guidance has the whole column.
private struct DemoPanelSlot: View {
    let manager: CaptureManager
    @ObservedObject var demo: DemoSession

    var body: some View {
        if demo.selectedSource != nil {
            DemoBarView(manager: manager, demo: demo)
        }
    }
}

enum WorkspaceMetrics {
    /// Around and between the rail, the header, the stage and the demo panel.
    static let gutter: CGFloat = 12
    static let sidebarWidth: CGFloat = 88
    static let headerHeight: CGFloat = 56
    /// The window's buttons sit in the rail, level with the header.
    static let windowButtonsCenter = CGPoint(x: gutter + sidebarWidth / 2, y: gutter + headerHeight / 2)
    static let minimumSize = CGSize(width: 800, height: 560)
    static let defaultSize = CGSize(width: 1180, height: 780)

    static func stageSize(fitting viewport: CGSize, aspectRatio: CGFloat) -> CGSize {
        guard viewport.width > 0, viewport.height > 0 else { return .zero }
        let ratio = aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 16 / 10
        let width = min(viewport.width, viewport.height * ratio)
        return CGSize(width: width, height: width / ratio)
    }
}

private struct WorkspacePanel: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .background(
                reduceTransparency
                    ? AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
                    : AnyShapeStyle(.regularMaterial),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.primary.opacity(contrast == .increased ? 0.5 : 0.08), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    func workspacePanel() -> some View { modifier(WorkspacePanel()) }
}
