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
    // Taller than the tile so the app-icon badge straddling each tile's
    // bottom-right corner isn't clipped by the scroller's mask.
    static let sourceViewportHeight: CGFloat = 56
    static let sourceTileRadius: CGFloat = 9
    static let sourcePreviewTrailingInset: CGFloat = 5
    static let sourcePreviewBottomInset: CGFloat = 6
    static let sourcePreviewWidth = sourceTileWidth - sourcePreviewTrailingInset
    static let sourcePreviewHeight = sourceTileHeight - sourcePreviewBottomInset
    static let sourceBadgeIconSize: CGFloat = 12
    static let sourceApplicationBadgeSize: CGFloat = 22
    static let sourceApplicationIconSize: CGFloat = 25
    // Wide enough that the trailing/leading tile clearly fades into the panel,
    // leaving a gutter the "more windows" chevron can sit in without touching the
    // thumbnail.
    static let sourceScrollFadeWidth: CGFloat = 26
    static let sourceScrollCoordinateSpace = "source-scroll"
    static let dragHandleWidth: CGFloat = 40
    static let dragHandleHeight: CGFloat = 3
    static let controlBarButtonHeight: CGFloat = 30
    static let controlBarIconSize: CGFloat = 12
    /// Small inset so the outer buttons sit just shy of the panel edge.
    static let effectBarEdgeInset: CGFloat = 3
    static let clickHighlightGlyphOffset = CGSize(width: -0.5, height: -0.5)
    static let keystrokeHighlightGlyphOffset = CGSize(width: 0.25, height: -0.5)
}

struct ControlView: View {
    @ObservedObject var manager: CaptureManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sourceScrollBounds = CGRect.zero
    @State private var isSettingsPresented = false

    private var panelShape: ControlPanelShape {
        ControlPanelShape(
            cornerRadius: ControlWindowSizing.panelCornerRadius,
            notchCenterX: ControlWindowSizing.panelWidth / 2,
            notchCenterY: ControlWindowSizing.heroCenterY,
            notchRadius: ControlWindowSizing.heroNotchRadius
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            // One cohesive panel: a single material surface + one border, its
            // bottom edge cradling the hero in a notch. Inset from the window by
            // the shadow margin so its drop shadow renders fully.
            panelShape
                .fill(.regularMaterial)
                .overlay(panelShape.strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
                .frame(
                    width: ControlWindowSizing.panelWidth,
                    height: ControlWindowSizing.panelBodyHeight
                )
                .shadow(color: .black.opacity(0.30), radius: 13, y: 5)
                .offset(y: ControlWindowSizing.panelTop)

            panelContent
                .frame(
                    width: ControlWindowSizing.panelWidth,
                    height: ControlWindowSizing.panelBodyHeight,
                    alignment: .top
                )
                // Round the content (dark source tiles) to the panel silhouette
                // so nothing squares off at the corners.
                .clipShape(panelShape)
                .offset(y: ControlWindowSizing.panelTop)

            demoHero
                .position(
                    x: ControlWindowSizing.size.width / 2,
                    y: ControlWindowSizing.heroCenterYAbsolute
                )
                .zIndex(1.5)
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

    private var panelContent: some View {
        VStack(spacing: 0) {
            topGrabHandle
                .frame(height: ControlWindowSizing.grabRegionHeight)

            sourceRow
                .frame(height: ControlWindowSizing.sourceRegionHeight)

            effectBar
                .frame(height: ControlWindowSizing.effectBarHeight)
        }
    }

    private var sourceRow: some View {
        Group {
            if manager.needsScreenRecordingPermission {
                permissionStrip
                    .padding(.horizontal, ControlMetrics.outerPadding)
            } else {
                sourcePanel
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var demoHero: some View {
        DemoHeroButton(
            isListening: manager.demoModeEnabled,
            showsPermissionWarning: manager.needsMicrophonePermission
                || manager.demoModeNeedsClickAccessibility
                || manager.demoModeUnavailableReason != nil,
            help: demoModeControlHelp,
            action: manager.toggleDemoMode
        )
    }

    private var effectBar: some View {
        HStack(spacing: 0) {
            leftControlGroup
                .frame(maxWidth: .infinity)

            // Center gap the hero button's notch occupies.
            Color.clear.frame(width: ControlWindowSizing.heroGap)

            rightControlGroup
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, ControlMetrics.effectBarEdgeInset)
    }

    // Three equal-width slots; each button fills its slot and centers its glyph,
    // so the icons are evenly distributed with equal gaps between them.
    private var leftControlGroup: some View {
        HStack(spacing: 0) {
            ControlBarButton(
                systemImage: "wand.and.sparkles",
                title: "Auto polish",
                help: autoPresentationControlHelp,
                isOn: manager.autoPresentationEnabled,
                action: manager.toggleAutoPresentation
            )
            .frame(maxWidth: .infinity)

            ControlBarButton(
                systemImage: "magnifyingglass",
                title: "Focus spotlight",
                help: spotlightControlHelp,
                isOn: manager.spotlightEnabled,
                action: manager.toggleSpotlight
            )
            .frame(maxWidth: .infinity)

            ControlBarButton(
                systemImage: "pencil.and.outline",
                title: "Annotate",
                help: annotationControlHelp,
                isOn: manager.annotationsEnabled,
                action: manager.toggleAnnotations
            )
            .frame(maxWidth: .infinity)
        }
    }

    private var rightControlGroup: some View {
        HStack(spacing: 0) {
            ControlBarButton(
                systemImage: "cursorarrow.rays",
                title: "Highlight clicks",
                help: "Show click ripples on the selected window and Demo Stage",
                isOn: manager.highlightsMouseClicks,
                glyphOffset: ControlMetrics.clickHighlightGlyphOffset,
                action: manager.toggleMouseClickHighlighting
            )
            .frame(maxWidth: .infinity)

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
            .frame(maxWidth: .infinity)

            ControlBarButton(
                systemImage: "gearshape",
                title: "Settings",
                help: "Open Settings",
                isPresented: isSettingsPresented,
                action: { isSettingsPresented.toggle() }
            )
            .frame(maxWidth: .infinity)
            .popover(
                isPresented: $isSettingsPresented,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .bottom
            ) {
                SettingsPopover(manager: manager)
            }
        }
    }

    private var sourcePanel: some View {
        sourceScroller
            .frame(
                width: ControlWindowSizing.contentWidth,
                height: ControlMetrics.sourceViewportHeight
            )
            .overlay {
                SourceScrollEdgeShadow(
                    leadingStrength: leadingSourceFadeStrength,
                    trailingStrength: trailingSourceFadeStrength
                )
                .allowsHitTesting(false)
            }
    }

    private var topGrabHandle: some View {
        TopGrabHandle()
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

    private var autoPresentationControlHelp: String {
        manager.autoPresentationEnabled
            ? "Auto-zoom clicks, mirror the system pointer at 3×, and apply the selected frame"
            : "Polish the Demo Stage with activity zooms, a 3× system pointer, and a styled frame"
    }

    private var demoModeControlHelp: String {
        if manager.needsMicrophonePermission {
            return "Allow microphone access, then turn on Demo Mode"
        }
        if let reason = manager.demoModeUnavailableReason {
            return reason
        }
        if manager.demoModeEnabled {
            if manager.demoMode.isListening {
                return manager.demoModeNeedsClickAccessibility
                    ? "Listening — allow Accessibility to open controls, not just highlight them"
                    : "Listening — name a control to highlight it, or say “click” to open it"
            }
            return "Demo Mode starts listening when a window is live"
        }
        return "Highlight and open controls by voice as you narrate your demo"
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
                // Top-align the tiles so the badge straddling each tile's bottom
                // corner overhangs into the scroller's extra height, not clipped.
                .frame(maxHeight: .infinity, alignment: .top)
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

/// A grab affordance at the top of the panel: a short pill in a full-width hit
/// strip, so the panel reads like a draggable sheet with a clear handle.
struct TopGrabHandle: View {
    var body: some View {
        ZStack {
            Color.white.opacity(0.001)

            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.28))
                .frame(
                    width: ControlMetrics.dragHandleWidth,
                    height: ControlMetrics.dragHandleHeight
                )
        }
        .frame(maxWidth: .infinity)
        .frame(height: ControlWindowSizing.grabRegionHeight)
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
        .help("Drag to move BetterMeets")
        .accessibilityHidden(true)
    }
}

/// The controller's single rounded surface: a rounded rectangle whose bottom
/// edge dips into a downward semicircular notch at center, cradling the hero
/// voice button so it reads as part of the panel rather than a pasted-on disc.
struct ControlPanelShape: Shape, InsettableShape {
    var cornerRadius: CGFloat
    var notchCenterX: CGFloat
    /// The disc center's Y (from the panel top). Above the bottom edge, so only
    /// the disc's lower cap protrudes and the notch traces just that cap.
    var notchCenterY: CGFloat
    var notchRadius: CGFloat
    var inset: CGFloat = 0

    func inset(by amount: CGFloat) -> ControlPanelShape {
        var copy = self
        copy.inset += amount
        return copy
    }

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: inset, dy: inset)
        let radius = max(0, min(cornerRadius - inset, min(rect.width, rect.height) / 2))
        let notch = max(0, notchRadius - inset)
        let cx = rect.minX + notchCenterX - inset
        let cy = rect.minY + notchCenterY
        let bottom = rect.maxY

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
            radius: radius, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: bottom - radius))
        path.addArc(
            center: CGPoint(x: rect.maxX - radius, y: bottom - radius),
            radius: radius, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        // Bottom edge dips DOWN to trace only the disc's protruding lower cap
        // (the disc center sits above the edge, so most of it is embedded).
        let rise = max(0, bottom - cy)
        let half = notch > rise ? (notch * notch - rise * rise).squareRoot() : 0
        let start = Angle(radians: atan2(rise, half))
        let end = Angle(radians: atan2(rise, -half))
        path.addLine(to: CGPoint(x: cx + half, y: bottom))
        path.addArc(center: CGPoint(x: cx, y: cy), radius: notch, startAngle: start, endAngle: end, clockwise: true)
        path.addLine(to: CGPoint(x: rect.minX + radius, y: bottom))
        path.addArc(
            center: CGPoint(x: rect.minX + radius, y: bottom - radius),
            radius: radius, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(
            center: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
            radius: radius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}
