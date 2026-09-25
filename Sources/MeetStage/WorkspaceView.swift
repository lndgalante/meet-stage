import SwiftUI

struct WorkspaceView: View {
    @ObservedObject var manager: CaptureManager
    @ObservedObject private var windowState = BetterMeetsWindowState.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @FocusState private var stageIsFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if !windowState.stageOnly {
                VStack(spacing: 12) {
                    StageActionsView(manager: manager)
                        .workspacePanel()
                    ControlView(manager: manager)
                        .frame(maxHeight: .infinity)
                        .workspacePanel()
                }
                .frame(width: WorkspaceMetrics.sidebarWidth)
                .transition(.opacity)
            }

            VStack(spacing: 12) {
                stage
                if !windowState.stageOnly {
                    StageStatusBar(manager: manager)
                        .workspacePanel()
                }
            }
        }
        .padding(windowState.stageOnly ? 0 : 12)
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: WorkspaceMetrics.minimumSize.width, minHeight: WorkspaceMetrics.minimumSize.height)
        .background(WindowConfigurator())
        .background(StageActionsInstaller(manager: manager))
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    windowState.toggleStageOnly()
                } label: {
                    Label(
                        windowState.stageOnly ? "Show Controls" : "Stage Only",
                        systemImage: windowState.stageOnly ? "sidebar.left" : "rectangle"
                    )
                }
                .help(windowState.stageOnly ? "Show tools and windows (⌃⌘S)" : "Hide controls for sharing (⌃⌘S)")
            }
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.on.rectangle")
                        .foregroundStyle(.secondary)
                    Text("BetterMeets")
                        .font(.headline)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    manager.toggleCapturePause()
                } label: {
                    Label(
                        manager.state == .paused ? "Resume" : "Pause",
                        systemImage: manager.state == .paused ? "play.fill" : "pause.fill"
                    )
                }
                .disabled(!manager.canToggleCapturePause)
                .help(manager.state == .paused ? "Resume sharing (⇧⌘P)" : "Pause sharing (⇧⌘P)")
            }
        }
        .toolbar(removing: .title)
        .ignoresSafeArea(.container, edges: windowState.stageOnly ? .top : [])
        .toolbar(windowState.stageOnly ? .hidden : .visible, for: .windowToolbar)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: windowState.stageOnly)
        .task {
            manager.startWindowMonitoring()
            manager.refreshWindows()
        }
        .onChange(of: windowState.stageOnly) { _, stageOnly in
            if stageOnly { stageIsFocused = true }
        }
    }

    private var stage: some View {
        GeometryReader { geometry in
            let size = WorkspaceMetrics.stageSize(
                fitting: geometry.size,
                aspectRatio: manager.displayedStageAspectRatio
            )
            StageView(manager: manager)
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: windowState.stageOnly ? 0 : 12))
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
            Button(manager.state == .paused ? "Resume Sharing" : "Pause Sharing") {
                manager.toggleCapturePause()
            }
            .disabled(!manager.canToggleCapturePause)
            Button("Open Source App") { manager.focusSelectedSourceIfPossible() }
                .disabled(!manager.isLive)
        }
    }
}

enum WorkspaceMetrics {
    static let sidebarWidth: CGFloat = 176
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
