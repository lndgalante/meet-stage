import SwiftUI

enum ControlMetrics {
    static let outerPadding = ControlWindowSizing.sourceRailInset
    static let sourceTileSpacing = ControlWindowSizing.sourceRailInset
    static let visibleSourceTileCount: CGFloat = 4
    static let sourceTileWidth: CGFloat =
        (ControlWindowSizing.sourceAreaWidth
            - sourceTileSpacing * (visibleSourceTileCount - 1))
        / visibleSourceTileCount
    static let sourceTileVerticalInset = ControlWindowSizing.sourceRailInset
    static let sourceViewportHeight = ControlWindowSizing.sourceRegionHeight
    static let sourceTileHeight =
        sourceViewportHeight - sourceTileVerticalInset * 2
    static let sourceTileRadius: CGFloat = 9
    static let sourcePreviewWidth = sourceTileWidth
    static let sourcePreviewHeight = sourceTileHeight
    static let sourceBadgeIconSize: CGFloat = 12
    static let sourceApplicationBadgeSize: CGFloat = 18
    static let sourceApplicationIconSize: CGFloat = 16
    // Wide enough that the trailing/leading tile clearly fades into the panel,
    // leaving a gutter the "more windows" chevron can sit in without touching the
    // thumbnail.
    static let sourceScrollFadeWidth: CGFloat = 22
    static let sourceScrollCoordinateSpace = "source-scroll"
    static let controlBarButtonHeight: CGFloat = 30
    static let controlBarActionSize: CGFloat = 28
    static let controlBarActionCornerRadius: CGFloat = 9.5
    static let controlBarIconSize: CGFloat = 13
    static let permissionActionSize: CGFloat = 28
    /// Match the visual leading/trailing inset to the action's bottom inset.
    static let effectBarInset: CGFloat =
        (ControlWindowSizing.effectBarHeight - controlBarActionSize) / 2
    static let clickHighlightGlyphOffset = CGSize(width: -0.5, height: -0.5)
    static let keystrokeHighlightGlyphOffset = CGSize(width: 0.25, height: -0.5)
}

enum ControlPalette {
    /// Follow the user's system accent for selection and active controls.
    static let accent = Color.accentColor
    static let warning = Color.orange
}

struct ControlView: View {
    @ObservedObject var manager: CaptureManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.legibilityWeight) private var legibilityWeight
    @State private var sourceScrollBounds = CGRect.zero
    @FocusState private var focusedSourceID: CGWindowID?

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
                .fill(panelBackground)
                .overlay {
                    panelShape.fill(
                        LinearGradient(
                            colors: panelTintColors,
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .overlay {
                    panelShape.strokeBorder(
                        LinearGradient(
                            colors: panelBorderColors,
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                }
                .frame(
                    width: ControlWindowSizing.panelWidth,
                    height: ControlWindowSizing.panelBodyHeight
                )
                .shadow(color: .black.opacity(0.40), radius: 18, y: 8)
                .shadow(color: .black.opacity(0.24), radius: 3, y: 1)
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
        .fontWeight(legibilityWeight == .bold ? .bold : nil)
        .background(WindowConfigurator(kind: .control))
        .contextMenu {
            Button("Settings…") {
                openSettings()
            }

            Divider()

            Button("Minimize Controller") {
                BetterMeetsWindowActions.minimizeController()
            }

            Button("Hide Controller") {
                BetterMeetsWindowActions.hideController()
            }
        }
        .task {
            openWindow(id: "stage")
            manager.startWindowMonitoring()
            manager.refreshWindows()
        }
    }

    private var panelBackground: AnyShapeStyle {
        if reduceTransparency {
            return AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
        }
        return AnyShapeStyle(.regularMaterial)
    }

    private var panelTintColors: [Color] {
        if colorScheme == .dark {
            return [Color.black.opacity(0.06), Color.black.opacity(0.20)]
        }
        return [Color.white.opacity(0.12), Color.black.opacity(0.05)]
    }

    private var panelBorderColors: [Color] {
        let topOpacity = colorSchemeContrast == .increased ? 0.55 : 0.28
        let bottomOpacity = colorSchemeContrast == .increased ? 0.32 : 0.12
        return [Color.primary.opacity(topOpacity), Color.primary.opacity(bottomOpacity)]
    }

    private var panelContent: some View {
        VStack(spacing: 0) {
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
            action: manager.toggleDemoMode,
            settingsAction: { showSettings(.demo) }
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
        .padding(.horizontal, ControlMetrics.effectBarInset)
    }

    // Fixed-size actions with flexible gaps keep the outer visual edges exactly
    // aligned to the effect bar's 4pt leading, trailing, and bottom inset.
    private var leftControlGroup: some View {
        HStack(spacing: 0) {
            ControlBarButton(
                systemImage: "wand.and.sparkles",
                title: "Auto polish",
                help: autoPresentationControlHelp,
                isOn: manager.autoPresentationEnabled,
                action: manager.toggleAutoPresentation,
                settingsAction: { showSettings(.stage) }
            )
            .frame(width: ControlMetrics.controlBarActionSize)

            Spacer(minLength: 0)

            ControlBarButton(
                systemImage: "magnifyingglass",
                title: "Focus spotlight",
                help: spotlightControlHelp,
                isOn: manager.spotlightEnabled,
                action: manager.toggleSpotlight,
                settingsAction: { showSettings(.spotlight) }
            )
            .frame(width: ControlMetrics.controlBarActionSize)

            Spacer(minLength: 0)

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

    private var rightControlGroup: some View {
        HStack(spacing: 0) {
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

            Spacer(minLength: 0)

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

            Spacer(minLength: 0)

            ControlBarButton(
                systemImage: "gearshape",
                title: "Settings",
                help: "Open Settings",
                action: { openSettings() }
            )
            .frame(width: ControlMetrics.controlBarActionSize)
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
            ? "Auto-zoom clicks, mirror the system pointer at 2×, and apply the selected frame"
            : "Polish the Demo Stage with activity zooms, a 2× system pointer, and a styled frame"
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
                                pinnedWindowDescription: manager.shortcutOwnerDescription(for: slot),
                                shortcutModifier: manager.globalShortcutModifier
                            )
                            .id("empty-shortcut-\(slot)")
                        }
                    }

                    ForEach(manager.unassignedDisplayedWindows) { source in
                        windowButton(for: source, shortcut: nil)
                            .id(source.id)
                    }
                }
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
                // Keep the compact thumbnails pinned to a stable optical row as
                // windows are added and removed from the horizontal scroller.
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
            .onMoveCommand(perform: moveSourceFocus)
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
            .onChange(of: focusedSourceID) { _, focusedID in
                guard let focusedID else { return }
                scrollToSource(focusedID, using: proxy)
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
            shortcutModifier: manager.globalShortcutModifier,
            isShortcutAvailable: shortcut.map {
                !manager.unavailableShortcutSlots.contains($0)
            } ?? true,
            isSelected: isSelected,
            isPaused: isSelected && manager.state == .paused,
            isPending: source.id == manager.pendingWindowID,
            isKeyboardFocused: focusedSourceID == source.id,
            shortcutOwner: manager.shortcutOwnerDescription(for:),
            action: { manager.select(source) },
            pin: { manager.pin(source, to: $0) },
            unpin: { manager.unpin(source) }
        )
        .focused($focusedSourceID, equals: source.id)
    }

    private func scrollToFocusedSource(using proxy: ScrollViewProxy) {
        guard let focusedID = manager.pendingWindowID ?? manager.selectedWindowID else { return }
        scrollToSource(focusedID, using: proxy)
    }

    private func scrollToSource(_ sourceID: CGWindowID, using proxy: ScrollViewProxy) {
        if reduceMotion {
            proxy.scrollTo(sourceID, anchor: .center)
        } else {
            withAnimation(.spring(response: 0.28, dampingFraction: 1)) {
                proxy.scrollTo(sourceID, anchor: .center)
            }
        }
    }

    private func moveSourceFocus(_ direction: MoveCommandDirection) {
        guard direction == .left || direction == .right else { return }
        let sourceIDs = manager.displayedWindows.map(\.id)
        guard !sourceIDs.isEmpty else { return }

        let currentID = focusedSourceID ?? manager.selectedWindowID
        let currentIndex =
            currentID.flatMap { sourceIDs.firstIndex(of: $0) }
            ?? (direction == .right ? -1 : sourceIDs.count)
        let offset = direction == .right ? 1 : -1
        let nextIndex = min(max(currentIndex + offset, 0), sourceIDs.count - 1)
        focusedSourceID = sourceIDs[nextIndex]
    }

    private func showSettings(_ tab: SettingsTab) {
        UserDefaults.standard.set(tab.rawValue, forKey: SettingsTab.storageKey)
        openSettings()
    }

    private var permissionStrip: some View {
        HStack(spacing: 5) {
            Image(systemName: "lock.screen")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(ControlPalette.warning)

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
        .padding(.leading, 9)
        .padding(.trailing, 3)
        .frame(height: ControlMetrics.sourceTileHeight)
        .background(
            ControlPalette.warning.opacity(0.10),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(ControlPalette.warning.opacity(0.22), lineWidth: 1)
        }
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
