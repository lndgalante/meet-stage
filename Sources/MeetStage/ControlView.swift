import SwiftUI

enum ControlMetrics {
    static let outerPadding: CGFloat = 5
    static let cornerRadius: CGFloat = 14
    static let controlBarCornerRadius: CGFloat = 12
    static let contentHeight: CGFloat = 44
    static let sourceTileSpacing: CGFloat = 4
    static let sourceTileHorizontalInset: CGFloat = 1
    static let visibleSourceTileCount: CGFloat = 4
    static let sourceTileWidth: CGFloat =
        (ControlWindowSizing.sourceAreaWidth
            - sourceTileHorizontalInset * 2
            - sourceTileSpacing * (visibleSourceTileCount - 1))
        / visibleSourceTileCount
    static let sourceTileHeight: CGFloat = 44
    static let sourceTileVerticalInset: CGFloat = 0
    static let sourceViewportHeight: CGFloat = 44
    static let sourceTileRadius: CGFloat = 9
    static let sourceBadgeIconSize: CGFloat = 12
    static let sourceApplicationIconSize: CGFloat = 16
    static let sourceApplicationIconHorizontalOffset: CGFloat = 1
    static let sourceApplicationIconVerticalOffset: CGFloat = 1
    static let sourceScrollFadeWidth: CGFloat = 14
    static let sourceScrollShadowWidth: CGFloat = 18
    static let sourceScrollCoordinateSpace = "source-scroll"
    static let dragHandleWidth: CGFloat = 40
    static let dragHandleHeight: CGFloat = 3
    static let controlBarButtonHeight: CGFloat = 30
    static let controlBarIconSize: CGFloat = 12
    static let clickHighlightGlyphOffset = CGSize(width: -0.5, height: -0.5)
    static let keystrokeHighlightGlyphOffset = CGSize(width: 0.25, height: -0.5)
}

struct ControlView: View {
    @ObservedObject var manager: CaptureManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sourceScrollBounds = CGRect.zero
    @State private var isSettingsPresented = false

    var body: some View {
        ZStack(alignment: .top) {
            controlBar
                .offset(
                    y: ControlWindowSizing.captureSurfaceSize.height
                        - ControlWindowSizing.controlBarOverlap
                )

            bottomDragHandle
                .offset(y: ControlWindowSizing.joinedSurfaceHeight)
                .zIndex(0.5)

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
            if !manager.needsScreenRecordingPermission {
                SourceScrollEdgeShadow(
                    leadingStrength: leadingSourceFadeStrength,
                    trailingStrength: trailingSourceFadeStrength
                )
                .allowsHitTesting(false)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: ControlMetrics.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.20), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: ControlMetrics.cornerRadius, style: .continuous))
    }

    private var controlBar: some View {
        HStack(spacing: 0) {
            ControlBarButton(
                systemImage: "magnifyingglass",
                title: "Focus spotlight",
                help: spotlightControlHelp,
                isOn: manager.spotlightEnabled,
                action: manager.toggleSpotlight
            )

            controlBarDivider

            ControlBarButton(
                systemImage: "pencil.and.outline",
                title: "Annotate",
                help: annotationControlHelp,
                isOn: manager.annotationsEnabled,
                action: manager.toggleAnnotations
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

            controlBarDivider

            ControlBarButton(
                systemImage: "gearshape",
                title: "Settings",
                help: "Open Settings",
                isPresented: isSettingsPresented,
                action: { isSettingsPresented.toggle() }
            )
            .popover(
                isPresented: $isSettingsPresented,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .bottom
            ) {
                SettingsPopover(manager: manager)
            }
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
        sourceScroller
            .frame(width: ControlWindowSizing.contentWidth, height: ControlMetrics.contentHeight)
    }

    private var bottomDragHandle: some View {
        BottomDragHandle()
    }

    private var annotationControlHelp: String {
        if manager.isAnnotating {
            return "Draw temporary ink over the selected app window"
        }
        if manager.annotationsEnabled {
            return manager.state == .paused
                ? "Annotations will resume when sharing resumes"
                : "Annotations will start when a window is live"
        }
        return manager.isLive
            ? "Draw temporary ink over the selected app window"
            : "Enable annotations for the next shared window"
    }

    private var spotlightControlHelp: String {
        if manager.spotlightEnabled {
            return manager.isLive
                ? "Move the pointer to focus part of the selected window"
                : "The spotlight will appear when a window is live"
        }
        return manager.isLive
            ? "Dim and softly blur everything outside the pointer spotlight"
            : "Enable the spotlight for the next shared window"
    }

    private var sourceScroller: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ControlMetrics.sourceTileSpacing) {
                    ForEach(visibleShortcutSlots, id: \.self) { slot in
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
                .background {
                    GeometryReader { geometry in
                        let bounds = geometry.frame(
                            in: .named(ControlMetrics.sourceScrollCoordinateSpace)
                        )
                        Color.clear
                            .onAppear {
                                sourceScrollBounds = bounds
                            }
                            .onChange(of: bounds) { _, newBounds in
                                sourceScrollBounds = newBounds
                            }
                    }
                }
            }
            .coordinateSpace(name: ControlMetrics.sourceScrollCoordinateSpace)
            .frame(width: ControlWindowSizing.sourceAreaWidth, height: ControlMetrics.sourceViewportHeight)
            .mask {
                SourceScrollFadeMask(
                    leadingStrength: leadingSourceFadeStrength,
                    trailingStrength: trailingSourceFadeStrength
                )
            }
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

    private var leadingSourceFadeStrength: CGFloat {
        guard sourceScrollBounds.width > 0 else { return 0 }
        return min(
            max(-sourceScrollBounds.minX / ControlMetrics.sourceScrollFadeWidth, 0),
            1
        )
    }

    private var trailingSourceFadeStrength: CGFloat {
        guard sourceScrollBounds.width > 0 else { return 0 }
        let remainingDistance = sourceScrollBounds.maxX - ControlWindowSizing.sourceAreaWidth
        return min(
            max(remainingDistance / ControlMetrics.sourceScrollFadeWidth, 0),
            1
        )
    }

    private var visibleShortcutSlots: [Int] {
        let additionalSlots = Set(
            ShortcutSlot.all.filter { slot in
                manager.window(forShortcutSlot: slot) != nil
                    || manager.shortcutOwnerDescription(for: slot) != nil
            }
        )
        return ShortcutSlot.visibleSlots(including: additionalSlots)
    }

    private func windowButton(for source: WindowSource, shortcut: Int?) -> some View {
        let isSelected = source.id == manager.selectedWindowID
        return CompactWindowButton(
            source: source,
            shortcut: shortcut,
            isShortcutAvailable: shortcut.map {
                !manager.unavailableShortcutSlots.contains($0)
            } ?? true,
            isSelected: isSelected,
            isPaused: isSelected && manager.state == .paused,
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

    private var permissionStrip: some View {
        HStack(spacing: 5) {
            Image(systemName: "lock.screen")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.red)

            Text("Allow screen recording")
                .font(.caption.weight(.semibold))
                .lineLimit(1)

            Spacer(minLength: 2)

            PermissionActionButton(
                systemImage: "gearshape",
                title: "Open Screen Recording Settings",
                action: manager.openScreenRecordingSettings
            )
            PermissionActionButton(
                systemImage: "arrow.clockwise",
                title: "Restart BetterMeets",
                action: manager.restartApplication
            )
        }
    }

}

struct BottomDragHandle: View {
    @ViewBuilder
    var body: some View {
        if #available(macOS 15.0, *) {
            handle
                .gesture(WindowDragGesture())
        } else {
            ZStack {
                WindowDragSurface()
                handle.allowsHitTesting(false)
            }
        }
    }

    private var handle: some View {
        ZStack {
            // Keep the full hit target in the composited window region while
            // preserving the minimal line treatment.
            Color.white.opacity(0.001)

            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.30))
                .frame(
                    width: ControlMetrics.dragHandleWidth,
                    height: ControlMetrics.dragHandleHeight
                )
        }
        .frame(
            width: ControlWindowSizing.dragHandleHitWidth,
            height: ControlWindowSizing.dragHandleAreaHeight
        )
        .contentShape(Rectangle())
        .help("Drag to move BetterMeets")
        .accessibilityHidden(true)
    }
}
