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
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        ControlView(manager: manager)
                            .frame(width: WorkspaceMetrics.sidebarWidth)
                            .workspacePanel()
                        stage
                            .frame(minWidth: 440)
                    }
                    .padding(12)
                    Divider()
                    StageStatusBar(manager: manager)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: WorkspaceMetrics.minimumSize.width, minHeight: WorkspaceMetrics.minimumSize.height)
        .background(WindowConfigurator())
        .background(StageActionsInstaller(manager: manager))
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.on.rectangle")
                        .foregroundStyle(.secondary)
                    Text("BetterMeets")
                        .font(.headline)
                }
            }
        }
        .toolbar(removing: .title)
        .ignoresSafeArea(.container, edges: windowState.stageOnly ? .top : [])
        .toolbar(windowState.stageOnly ? .hidden : .visible, for: .windowToolbar)
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

enum WorkspaceMetrics {
    static let sidebarWidth: CGFloat = 88
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
