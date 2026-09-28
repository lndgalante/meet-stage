import SwiftUI

struct WorkspaceView: View {
    @ObservedObject var manager: CaptureManager
    @ObservedObject private var windowState = BetterMeetsWindowState.shared
    @Environment(\.colorSchemeContrast) private var contrast
    @FocusState private var stageIsFocused: Bool
    @AppStorage("BetterMeets.hasUsedStageOnly") private var hasUsedStageOnly = false

    var body: some View {
        Group {
            if windowState.stageOnly {
                stage
            } else {
                HSplitView {
                    sidebar
                        .frame(minWidth: 200, idealWidth: WorkspaceMetrics.sidebarWidth, maxWidth: 320)
                        .background(SidebarWidthRestorer())
                    VStack(spacing: 12) {
                        if manager.isLive && !hasUsedStageOnly {
                            HStack(spacing: 12) {
                                Text("Choose Stage Only before sharing BetterMeets in your meeting.")
                                    .font(.callout)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                Button("Stage Only") { windowState.stageOnly = true }
                            }
                            .padding(12)
                            .workspacePanel()
                        }
                        stage
                        StageStatusBar(manager: manager).workspacePanel()
                    }
                    .padding(.leading, 12)
                    .frame(minWidth: 440)
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
                    HStack(spacing: 6) {
                        Image(systemName: "rectangle")
                        Text("Stage Only")
                    }
                }
                .help(windowState.stageOnly ? "Show tools and windows (⌃⌘S)" : "Hide controls before sharing BetterMeets. Restoring controls shows them in that window share (⌃⌘S)")
            }
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
                hasUsedStageOnly = true
            }
        }
    }

    private var sidebar: some View {
        GeometryReader { geometry in
            VStack(spacing: 12) {
                WorkspaceTools(manager: manager)
                    .workspacePanel()
                ControlView(manager: manager, compact: geometry.size.height < 680)
                    .frame(maxHeight: .infinity)
                    .workspacePanel()
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

private struct WorkspaceTools: View {
    @ObservedObject var manager: CaptureManager
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Tools").font(.callout.weight(.medium))
                if enabledCount > 0 {
                    Text("\(enabledCount) on").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button("Settings", systemImage: "gearshape") {
                    UtilityWindows.showSettings(manager: manager)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Settings (⌘,)")
            }
            .padding(12)
            StageActionsView(manager: manager)
            if enabledCount > 0 && !manager.isLive {
                Text("Ready for the next source")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
    }

    private var enabledCount: Int {
        [manager.autoPresentationEnabled, manager.spotlightEnabled, manager.annotationsEnabled,
         manager.highlightsMouseClicks, manager.highlightsKeystrokes].filter { $0 }.count
    }
}

enum WorkspaceMetrics {
    static let sidebarWidth: CGFloat = 224
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
