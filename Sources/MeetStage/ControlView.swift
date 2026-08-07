import SwiftUI

enum ControlWindowSizing {
    static let size = NSSize(width: 340, height: 80)
    static let maximumVisibleSources = 3
    static let sourceAreaWidth: CGFloat = 186
}

struct ControlView: View {
    @ObservedObject var manager: CaptureManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if manager.needsScreenRecordingPermission {
                permissionStrip
            } else if manager.windows.isEmpty {
                emptyStrip
            } else {
                sourceStrip
            }
        }
        .padding(8)
        .frame(width: ControlWindowSizing.size.width, height: ControlWindowSizing.size.height)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .background(WindowConfigurator(kind: .control))
        .task {
            openWindow(id: "stage")
            manager.refreshWindows()
        }
    }

    private var sourceStrip: some View {
        HStack(spacing: 7) {
            captureStatusButton

            HStack(spacing: 6) {
                ForEach(visibleSources) { source in
                    CompactWindowButton(
                        source: source,
                        shortcut: manager.shortcut(for: source),
                        isShortcutAvailable: manager.shortcut(for: source).map {
                            !manager.unavailableShortcutSlots.contains($0)
                        } ?? true,
                        isSelected: source.id == manager.selectedWindowID,
                        isPending: source.id == manager.pendingWindowID,
                        shortcutOwner: manager.shortcutOwnerDescription(for:),
                        action: { manager.select(source) },
                        pin: { manager.pin(source, to: $0) },
                        unpin: { manager.unpin(source) }
                    )
                }
            }
            .frame(width: ControlWindowSizing.sourceAreaWidth, alignment: .leading)

            overflowMenu

            Divider()
                .frame(height: 38)

            actionButtons
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var visibleSources: [WindowSource] {
        let sources = manager.displayedWindows
        var visible = Array(sources.prefix(ControlWindowSizing.maximumVisibleSources))
        let focusedID = manager.pendingWindowID ?? manager.selectedWindowID

        guard
            let focusedID,
            let focusedSource = sources.first(where: { $0.id == focusedID }),
            !visible.contains(where: { $0.id == focusedID })
        else {
            return visible
        }

        if visible.count == ControlWindowSizing.maximumVisibleSources {
            visible[visible.count - 1] = focusedSource
        } else {
            visible.append(focusedSource)
        }
        return visible
    }

    private var captureStatusButton: some View {
        CaptureStatusControl(
            state: manager.state,
            statusDescription: manager.statusDescription,
            isCapturing: manager.isCapturing,
            isLive: manager.isLive,
            action: manager.stopCapture
        )
    }

    private var actionButtons: some View {
        HStack(spacing: 2) {
            CompactActionButton(
                systemImage: "arrow.clockwise",
                help: manager.isRefreshing ? "Refreshing available windows…" : "Refresh available windows (⌘R)",
                isDisabled: manager.isRefreshing,
                action: manager.refreshWindows
            )

            CompactActionButton(
                systemImage: "rectangle.on.rectangle",
                help: "Show Demo Stage"
            ) {
                openWindow(id: "stage")
            }

        }
    }

    private var overflowMenu: some View {
        Menu {
            ForEach(manager.displayedWindows) { source in
                Button {
                    manager.select(source)
                } label: {
                    Label {
                        Text(overflowMenuTitle(for: source))
                    } icon: {
                        ApplicationMenuIcon(image: source.applicationIcon)
                    }
                }
            }

            if !manager.pinnedShortcuts.isEmpty {
                Divider()
                Menu("Manage Pinned Shortcuts") {
                    ForEach(manager.pinnedShortcuts, id: \.slot) { pin in
                        Button("Clear ⌥\(pin.slot) — \(pin.window.description)") {
                            manager.clearShortcut(pin.slot)
                        }
                    }
                }
            }

            if let notice = manager.controllerNotice {
                Divider()
                Button {} label: {
                    Label(notice, systemImage: "exclamationmark.triangle.fill")
                }
                .disabled(true)
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 24, height: 40)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("All windows and pinned shortcuts")
        .accessibilityLabel("All windows and pinned shortcuts")
    }

    private func overflowMenuTitle(for source: WindowSource) -> String {
        let windowDescription = "\(source.applicationName) — \(source.title)"
        var prefixes: [String] = []

        if let shortcut = manager.shortcut(for: source) {
            prefixes.append("⌥\(shortcut)")
        }
        if source.id == manager.pendingWindowID {
            prefixes.append("Switching")
        } else if source.id == manager.selectedWindowID, manager.isLive {
            prefixes.append("Live")
        }

        guard !prefixes.isEmpty else { return windowDescription }
        return "\(prefixes.joined(separator: " · "))  \(windowDescription)"
    }

    private var permissionStrip: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "lock.screen")
                    .font(.title3)
                    .foregroundStyle(.red)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Allow screen recording")
                        .font(.callout.weight(.semibold))
                    Text("Open Settings, then restart.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 4)

            PermissionActionButton(
                title: "Settings",
                help: "Open Screen Recording Settings",
                action: manager.openScreenRecordingSettings
            )
            PermissionActionButton(
                title: "Restart",
                help: "Restart BetterDemos",
                action: manager.restartApplication
            )
        }
    }

    private var emptyStrip: some View {
        HStack(spacing: 10) {
            if manager.state == .loading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: manager.errorMessage == nil ? "macwindow.badge.plus" : "exclamationmark.triangle")
                    .font(.title2)
                    .foregroundStyle(manager.errorMessage == nil ? Color.secondary : Color.red)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(emptyTitle)
                    .font(.callout.weight(.semibold))
                Text(emptyDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(emptyDetail)
            }

            Spacer()

            CompactActionButton(
                systemImage: "arrow.clockwise",
                help: manager.isRefreshing ? "Refreshing windows…" : "Refresh windows",
                isDisabled: manager.isRefreshing,
                action: manager.refreshWindows
            )
            CompactActionButton(
                systemImage: "rectangle.on.rectangle",
                help: "Show Demo Stage"
            ) {
                openWindow(id: "stage")
            }
        }
    }

    private var emptyTitle: String {
        switch manager.state {
        case .loading:
            return "Finding windows…"
        case .failed:
            return "Capture needs attention"
        default:
            return "No windows available"
        }
    }

    private var emptyDetail: String {
        manager.errorMessage ?? "Open an app window, then refresh."
    }

}

private struct ApplicationMenuIcon: View {
    let image: NSImage?

    @ViewBuilder
    var body: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: 16, height: 16)
        } else {
            Image(systemName: "macwindow")
                .frame(width: 16, height: 16)
        }
    }
}

private struct CompactWindowButton: View {
    let source: WindowSource
    let shortcut: Int?
    let isShortcutAvailable: Bool
    let isSelected: Bool
    let isPending: Bool
    let shortcutOwner: (Int) -> String?
    let action: () -> Void
    let pin: (Int) -> Void
    let unpin: () -> Void

    @State private var showPreview = false
    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.black)

                if let thumbnail = source.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                } else if let icon = source.applicationIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .padding(12)
                } else {
                    Image(systemName: "macwindow")
                        .foregroundStyle(.secondary)
                }

                VStack {
                    HStack {
                        if let shortcut {
                            Text("⌥\(shortcut)")
                                .font(.system(.caption2, design: .rounded, weight: .bold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .foregroundStyle(.white)
                                .background(
                                    isShortcutAvailable ? Color.black.opacity(0.78) : Color.red.opacity(0.9),
                                    in: Capsule()
                                )
                        }
                        Spacer()
                        if isPending {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(.orange)
                        } else if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .blue)
                                .font(.system(size: 14))
                        }
                    }
                    Spacer()
                    HStack {
                        Spacer()
                        if let icon = source.applicationIcon {
                            Image(nsImage: icon)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 15, height: 15)
                                .padding(2)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }
                    }
                }
                .padding(4)
            }
            .frame(width: 58, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(borderColor, lineWidth: borderWidth)
            }
            .shadow(
                color: isSelected ? Color.blue.opacity(0.35) : .clear,
                radius: 4,
                y: 2
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Menu("Pin Global Shortcut") {
                ForEach(1...9, id: \.self) { slot in
                    Button {
                        pin(slot)
                    } label: {
                        shortcutMenuLabel(for: slot)
                    }
                }
            }

            if let shortcut {
                Divider()
                Button("Unpin ⌥\(shortcut)", role: .destructive, action: unpin)
            }
        }
        .onHover { isHovering in
            hoverTask?.cancel()

            if isHovering {
                hoverTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    guard !Task.isCancelled else { return }
                    showPreview = true
                }
            } else {
                showPreview = false
            }
        }
        .popover(isPresented: $showPreview, arrowEdge: .bottom) {
            WindowHoverPreview(
                source: source,
                shortcut: shortcut,
                isShortcutAvailable: isShortcutAvailable
            )
        }
        .onDisappear {
            hoverTask?.cancel()
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isPending ? "Switching" : isSelected ? "Live" : "Not live")
        .accessibilityHint("Selects this window. Open the context menu to pin a global shortcut.")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var borderColor: Color {
        if isPending { return .orange }
        if isSelected { return .blue }
        return .white.opacity(0.14)
    }

    private var borderWidth: CGFloat {
        isPending ? 2 : isSelected ? 3 : 1
    }

    private var accessibilityLabel: String {
        let name = "Share \(source.applicationName), \(source.title)"
        guard let shortcut else { return name }
        return "\(name), shortcut Option \(shortcut)"
    }

    @ViewBuilder
    private func shortcutMenuLabel(for slot: Int) -> some View {
        if shortcut == slot {
            Label("Option+\(slot) — Current", systemImage: "checkmark")
        } else if let owner = shortcutOwner(slot) {
            Text("Option+\(slot) — Replace \(owner)")
        } else {
            Text("Option+\(slot)")
        }
    }
}

private struct WindowHoverPreview: View {
    let source: WindowSource
    let shortcut: Int?
    let isShortcutAvailable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack {
                Color.black

                if let thumbnail = source.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                } else if let icon = source.applicationIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                }
            }
            .frame(width: 288, height: 162)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            HStack(spacing: 8) {
                if let icon = source.applicationIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(source.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text(source.applicationName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if let shortcut {
                    Text(isShortcutAvailable ? "⌥\(shortcut)" : "⌥\(shortcut) unavailable")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(isShortcutAvailable ? Color.primary : Color.red)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                } else {
                    Text("Right-click to pin")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .frame(width: 308)
    }
}

private struct PermissionActionButton: View {
    let title: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(help)
            .accessibilityLabel(help)
    }
}

private struct CompactActionButton: View {
    let systemImage: String
    let help: String
    var tint: Color = .primary
    var isDisabled = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 40)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isHovering ? Color.primary.opacity(0.09) : .clear)
                        .frame(height: 28)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(CompactIconButtonStyle())
        .disabled(isDisabled)
        .onHover { isHovering = $0 && !isDisabled }
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct CompactIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

private struct CaptureStatusControl: View {
    let state: CaptureState
    let statusDescription: String
    let isCapturing: Bool
    let isLive: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Group {
            if isCapturing {
                Button(action: action) {
                    statusGlyph
                        .contentShape(Rectangle())
                }
                .buttonStyle(CompactIconButtonStyle())
                .accessibilityLabel("Stop capture")
                .accessibilityValue(statusDescription)
                .accessibilityHint("Stops the current window capture")
            } else {
                statusGlyph
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Capture status")
                    .accessibilityValue(statusDescription)
            }
        }
        .onHover { isHovering = $0 && isCapturing }
        .help(tooltipText)
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    @ViewBuilder
    private var statusGlyph: some View {
        ZStack {
            if isCapturing && isHovering {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(.red)
                    .frame(width: 10, height: 10)
            } else {
                switch state {
                case .capturing:
                    Image(systemName: "record.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.green)
                        .shadow(color: Color.green.opacity(isLive ? 0.55 : 0), radius: 4, y: 2)
                case .loading, .switching:
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.orange)
                case .permissionRequired, .failed:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.red)
                case .idle:
                    Image(systemName: "circle")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 24, height: 40)
        .contentShape(Rectangle())
    }

    private var tooltipText: String {
        isCapturing
            ? "\(statusDescription) · Click to stop capture (⌘.)"
            : "Capture status: \(statusDescription)"
    }
}

struct WindowConfigurator: NSViewRepresentable {
    enum Kind {
        case control
        case stage(aspectRatio: CGFloat)
    }

    let kind: Kind

    final class Coordinator {
        var lastStageAspectRatio: CGFloat?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(view.window, coordinator: context.coordinator)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(nsView.window, coordinator: context.coordinator)
        }
    }

    private func configure(_ window: NSWindow?, coordinator: Coordinator) {
        guard let window else { return }

        switch kind {
        case .control:
            let compactSize = ControlWindowSizing.size
            window.level = .floating
            window.collectionBehavior.formUnion([.canJoinAllSpaces, .fullScreenAuxiliary])
            window.styleMask = [.borderless]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.isMovableByWindowBackground = true
            window.setContentSize(compactSize)
            window.minSize = compactSize
            window.maxSize = compactSize

        case let .stage(aspectRatio):
            let safeAspectRatio = max(0.75, min(aspectRatio, 3))
            let stageStyle: NSWindow.StyleMask = [.borderless, .resizable]
            if window.styleMask != stageStyle {
                window.styleMask = stageStyle
            }
            window.isOpaque = true
            window.backgroundColor = .black
            window.hasShadow = false
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.toolbar = nil
            [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].forEach {
                window.standardWindowButton($0)?.isHidden = true
            }
            window.isMovableByWindowBackground = true
            window.contentAspectRatio = NSSize(width: safeAspectRatio, height: 1)
            window.collectionBehavior.formUnion([.canJoinAllSpaces, .fullScreenAuxiliary])

            guard coordinator.lastStageAspectRatio.map({ abs($0 - safeAspectRatio) > 0.001 }) ?? true else {
                return
            }

            let previousCenter = NSPoint(x: window.frame.midX, y: window.frame.midY)
            let screen = window.screen ?? NSScreen.main
            let contentSize = StageWindowSizing.defaultWindowContentSize(
                aspectRatio: safeAspectRatio,
                on: screen
            )
            window.setContentSize(contentSize)

            if let visibleFrame = screen?.visibleFrame {
                let desiredOrigin = NSPoint(
                    x: previousCenter.x - window.frame.width / 2,
                    y: previousCenter.y - window.frame.height / 2
                )
                window.setFrameOrigin(NSPoint(
                    x: min(max(desiredOrigin.x, visibleFrame.minX), visibleFrame.maxX - window.frame.width),
                    y: min(max(desiredOrigin.y, visibleFrame.minY), visibleFrame.maxY - window.frame.height)
                ))
            }
            coordinator.lastStageAspectRatio = safeAspectRatio
        }
    }
}
