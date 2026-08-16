import SwiftUI

private enum ControlMetrics {
    static let outerPadding: CGFloat = 7
    static let cornerRadius: CGFloat = 16
    static let controlBarCornerRadius: CGFloat = 12
    static let contentHeight: CGFloat = 58
    static let captureControlWidth: CGFloat = 42
    static let captureGlyphHorizontalOffset: CGFloat = -4
    static let sourceTileWidth: CGFloat = 52
    static let sourceTileHeight: CGFloat = 52
    static let sourceTileSpacing: CGFloat = 4
    static let sourceTileHorizontalInset: CGFloat = 4
    static let sourceTileVerticalInset: CGFloat = 2
    static let sourceViewportHeight: CGFloat = 56
    static let sourceTileRadius: CGFloat = 10
    static let controlBarButtonHeight: CGFloat = 30
    static let clickHighlightGlyphOffset = CGSize(width: -0.5, height: -0.5)
    static let keystrokeHighlightGlyphOffset = CGSize(width: 0.25, height: -0.5)
}

struct ControlView: View {
    @ObservedObject var manager: CaptureManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            controlBar
                .offset(
                    y: ControlWindowSizing.captureSurfaceSize.height
                        - ControlWindowSizing.controlBarOverlap
                )

            captureSurface
                .zIndex(1)
        }
        .frame(
            width: ControlWindowSizing.size.width,
            height: ControlWindowSizing.size.height,
            alignment: .top
        )
        .background(WindowConfigurator(kind: .control))
        .task {
            openWindow(id: "stage")
            manager.startWindowMonitoring()
            manager.refreshWindows()
        }
    }

    private var captureSurface: some View {
        Group {
            if manager.needsScreenRecordingPermission {
                permissionStrip
            } else if manager.windows.isEmpty {
                emptyStrip
            } else {
                sourcePanel
            }
        }
        .padding(ControlMetrics.outerPadding)
        .frame(
            width: ControlWindowSizing.captureSurfaceSize.width,
            height: ControlWindowSizing.captureSurfaceSize.height
        )
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: ControlMetrics.cornerRadius, style: .continuous)
        )
        .overlay {
            ZStack {
                CaptureSeparatorShape()
                    .fill(Color.white.opacity(0.12))

                RoundedRectangle(cornerRadius: ControlMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.20), lineWidth: 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: ControlMetrics.cornerRadius, style: .continuous))
    }

    private var controlBar: some View {
        HStack(spacing: 0) {
            ControlBarButton(
                systemImage: "gearshape",
                title: "Settings",
                help: "Settings (coming soon)",
                action: {}
            )

            controlBarDivider

            ControlBarButton(
                systemImage: "pencil.and.outline",
                title: "Annotate",
                help: "Annotate (coming soon)",
                action: {}
            )

            controlBarDivider

            ControlBarButton(
                systemImage: "cursorarrow.rays",
                title: "Highlight clicks",
                help: "Show click ripples on the selected window and Demo Stage",
                isOn: manager.highlightsMouseClicks,
                glyphOffset: ControlMetrics.clickHighlightGlyphOffset,
                action: manager.toggleMouseClickHighlighting
            )

            controlBarDivider

            ControlBarButton(
                systemImage: "command.square",
                title: "Highlight keystrokes",
                help: manager.needsKeystrokeAccessibilityPermission
                    ? "Allow Accessibility access, then turn on keystroke highlighting"
                    : "Highlight keystrokes on the Demo Stage",
                isOn: manager.highlightsKeystrokes,
                glyphOffset: ControlMetrics.keystrokeHighlightGlyphOffset,
                showsPermissionWarning: manager.needsKeystrokeAccessibilityPermission,
                action: manager.toggleKeystrokeHighlighting
            )
        }
        .padding(.top, ControlWindowSizing.controlBarOverlap)
        .frame(
            width: ControlWindowSizing.controlBarWidth,
            height: ControlWindowSizing.controlBarHeight
        )
        .background(
            .regularMaterial,
            in: UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: ControlMetrics.controlBarCornerRadius,
                bottomTrailingRadius: ControlMetrics.controlBarCornerRadius,
                topTrailingRadius: 0,
                style: .continuous
            )
        )
        .overlay {
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: ControlMetrics.controlBarCornerRadius,
                bottomTrailingRadius: ControlMetrics.controlBarCornerRadius,
                topTrailingRadius: 0,
                style: .continuous
            )
            .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        }
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: ControlMetrics.controlBarCornerRadius,
                bottomTrailingRadius: ControlMetrics.controlBarCornerRadius,
                topTrailingRadius: 0,
                style: .continuous
            )
        )
    }

    private var controlBarDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.10))
            .frame(width: 1, height: ControlMetrics.controlBarButtonHeight)
    }

    private var sourcePanel: some View {
        HStack(spacing: 0) {
            captureStatusButton
                .offset(x: ControlMetrics.captureGlyphHorizontalOffset)
                .frame(
                    width: ControlMetrics.captureControlWidth,
                    height: ControlMetrics.contentHeight
                )

            sourceScroller
        }
        .frame(width: ControlWindowSizing.contentWidth, height: ControlMetrics.contentHeight)
    }

    private var sourceScroller: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: ControlMetrics.sourceTileSpacing) {
                    ForEach(ShortcutSlot.all, id: \.self) { slot in
                        if let source = manager.window(forShortcutSlot: slot) {
                            windowButton(for: source, shortcut: slot)
                                .id(source.id)
                        } else {
                            EmptyShortcutSlot(
                                slot: slot,
                                pinnedWindowDescription: manager.shortcutOwnerDescription(for: slot)
                            )
                            .id("empty-shortcut-\(slot)")
                        }
                    }

                    ForEach(manager.unassignedDisplayedWindows) { source in
                        windowButton(for: source, shortcut: nil)
                            .id(source.id)
                    }
                }
                .padding(.horizontal, ControlMetrics.sourceTileHorizontalInset)
                .padding(.vertical, ControlMetrics.sourceTileVerticalInset)
            }
            .frame(width: ControlWindowSizing.sourceAreaWidth, height: ControlMetrics.sourceViewportHeight)
            .accessibilityLabel("Available windows")
            .accessibilityHint("Scroll horizontally to browse windows")
            .onAppear {
                scrollToFocusedSource(using: proxy)
            }
            .onChange(of: manager.pendingWindowID) { _, _ in
                scrollToFocusedSource(using: proxy)
            }
            .onChange(of: manager.selectedWindowID) { _, _ in
                scrollToFocusedSource(using: proxy)
            }
            .onChange(of: manager.displayedWindows.map(\.id)) { _, _ in
                scrollToFocusedSource(using: proxy)
            }
            .onChange(of: manager.shortcutWindowIDs) { _, _ in
                scrollToFocusedSource(using: proxy)
            }
        }
    }

    private func windowButton(for source: WindowSource, shortcut: Int?) -> some View {
        CompactWindowButton(
            source: source,
            shortcut: shortcut,
            isShortcutAvailable: shortcut.map {
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

    private func scrollToFocusedSource(using proxy: ScrollViewProxy) {
        guard let focusedID = manager.pendingWindowID ?? manager.selectedWindowID else { return }
        if reduceMotion {
            proxy.scrollTo(focusedID, anchor: .center)
        } else {
            withAnimation(.spring(response: 0.28, dampingFraction: 1)) {
                proxy.scrollTo(focusedID, anchor: .center)
            }
        }
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
        manager.errorMessage ?? "Open an app window. It will appear automatically."
    }

}

private struct EmptyShortcutSlot: View {
    let slot: Int
    let pinnedWindowDescription: String?

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: ControlMetrics.sourceTileRadius, style: .continuous)
                .fill(Color.black.opacity(0.16))

            RoundedRectangle(cornerRadius: ControlMetrics.sourceTileRadius, style: .continuous)
                .strokeBorder(
                    Color.white.opacity(0.13),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                )

            Text("⌥\(slot)")
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.06), in: Capsule())
                .padding(4)
        }
        .frame(width: ControlMetrics.sourceTileWidth, height: ControlMetrics.sourceTileHeight)
        .help(helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Option \(slot), empty shortcut slot")
        .accessibilityHint(accessibilityHint)
    }

    private var helpText: String {
        if let pinnedWindowDescription {
            return "Option+\(slot): \(pinnedWindowDescription) is unavailable"
        }
        return "Option+\(slot): Empty shortcut slot"
    }

    private var accessibilityHint: String {
        if pinnedWindowDescription != nil {
            return "The pinned window is currently unavailable"
        }
        return "A window can be pinned here from its context menu"
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: ControlMetrics.sourceTileRadius, style: .continuous)
                    .fill(Color.black)

                if let thumbnail = source.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(
                            width: ControlMetrics.sourceTileWidth,
                            height: ControlMetrics.sourceTileHeight
                        )
                        .clipped()
                } else if let icon = source.applicationIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .padding(10)
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
                                .transition(.opacity.combined(with: .scale(scale: 0.75)))
                        } else if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .blue)
                                .font(.system(size: 14))
                                .transition(.opacity.combined(with: .scale(scale: 0.75)))
                        }
                    }
                    Spacer()
                    HStack {
                        Spacer()
                        if let icon = source.applicationIcon {
                            Image(nsImage: icon)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 14, height: 14)
                                .padding(2)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }
                    }
                }
                .padding(4)
            }
            .frame(width: ControlMetrics.sourceTileWidth, height: ControlMetrics.sourceTileHeight)
            .clipShape(
                RoundedRectangle(cornerRadius: ControlMetrics.sourceTileRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: ControlMetrics.sourceTileRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            }
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.14),
                value: visualState
            )
        }
        .buttonStyle(CompactIconButtonStyle())
        .contextMenu {
            Menu("Pin Global Shortcut") {
                ForEach(ShortcutSlot.all, id: \.self) { slot in
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
                    try? await Task.sleep(for: .milliseconds(450))
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
        isPending || isSelected ? 2 : 1
    }

    private var visualState: Int {
        isPending ? 2 : isSelected ? 1 : 0
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

private struct ControlBarButton: View {
    let systemImage: String
    let title: String
    let help: String
    var isOn: Bool?
    var glyphOffset = CGSize.zero
    var isEnabled = true
    var showsPermissionWarning = false
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Rectangle()
                .fill(buttonBackground)

            Button(action: action) {
                ZStack {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .medium))
                        .symbolRenderingMode(.monochrome)
                        .offset(x: glyphOffset.width, y: glyphOffset.height)

                    if showsPermissionWarning {
                        HStack {
                            Spacer()

                            Image(systemName: "exclamationmark")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(.orange)
                                .frame(width: 8, height: 8)
                        }
                        .padding(.trailing, 4)
                    }
                }
                .foregroundStyle(
                    isOn == true || (isHovering && isEnabled) ? Color.primary : Color.secondary
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(CompactIconButtonStyle())
            .disabled(!isEnabled)
            .help(help)
            .accessibilityLabel(title)
            .accessibilityValue(accessibilityValue)
            .accessibilityHint(help)
            .accessibilityAddTraits(isOn == true ? .isSelected : [])
        }
        .frame(maxWidth: .infinity)
        .frame(height: ControlMetrics.controlBarButtonHeight)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.12),
            value: isHovering
        )
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.12),
            value: isOn
        )
    }

    private var buttonBackground: Color {
        guard isEnabled else { return .clear }
        if isOn == true {
            return Color.primary.opacity(isHovering ? 0.14 : 0.10)
        }
        return isHovering ? Color.primary.opacity(0.07) : .clear
    }

    private var accessibilityValue: String {
        guard let isOn else { return "Coming soon" }
        if showsPermissionWarning { return "Permission required" }
        return isOn ? "On" : "Off"
    }
}

private struct CaptureSeparatorShape: Shape {
    func path(in rect: CGRect) -> Path {
        let thickness: CGFloat = 1
        let borderInset: CGFloat = 1
        let captureBoundary = ControlMetrics.outerPadding + ControlMetrics.captureControlWidth

        var path = Path()
        path.addRect(
            CGRect(
                x: captureBoundary - thickness / 2,
                y: borderInset,
                width: thickness,
                height: rect.height - borderInset * 2
            )
        )
        return path
    }
}

private struct CompactIconButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.1),
                value: configuration.isPressed
            )
    }
}

private struct CaptureStatusControl: View {
    let state: CaptureState
    let statusDescription: String
    let isCapturing: Bool
    let isLive: Bool
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
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
        .frame(width: 24, height: ControlMetrics.contentHeight)
        .contentShape(Rectangle())
    }

    private var tooltipText: String {
        isCapturing
            ? "\(statusDescription) · Click to stop capture (⌘.)"
            : "Capture status: \(statusDescription)"
    }
}
