import SwiftUI

private enum ControlMetrics {
    static let outerPadding: CGFloat = 5
    static let cornerRadius: CGFloat = 14
    static let controlBarCornerRadius: CGFloat = 12
    static let contentHeight: CGFloat = 44
    static let sourceTileWidth: CGFloat = 44
    static let sourceTileHeight: CGFloat = 44
    static let sourceTileSpacing: CGFloat = 4
    static let sourceTileHorizontalInset: CGFloat = 4
    static let sourceTileVerticalInset: CGFloat = 0
    static let sourceViewportHeight: CGFloat = 44
    static let sourceTileRadius: CGFloat = 9
    static let sourceBadgeIconSize: CGFloat = 12
    static let sourceScrollFadeWidth: CGFloat = 14
    static let sourceScrollShadowWidth: CGFloat = 18
    static let sourceScrollCoordinateSpace = "source-scroll"
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
            RoundedRectangle(cornerRadius: ControlMetrics.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.20), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: ControlMetrics.cornerRadius, style: .continuous))
    }

    private var controlBar: some View {
        HStack(spacing: 0) {
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
            .overlay {
                SourceScrollEdgeShadow(
                    leadingStrength: leadingSourceFadeStrength,
                    trailingStrength: trailingSourceFadeStrength
                )
                .allowsHitTesting(false)
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

// MARK: - Settings

private struct SettingsPopover: View {
    @ObservedObject var manager: CaptureManager
    @State private var selectedTab: SettingsTab = .annotations

    var body: some View {
        VStack(spacing: 16) {
            Picker(
                "Settings section",
                selection: $selectedTab
            ) {
                ForEach(SettingsTab.allCases) { tab in
                    Text(tab.title)
                        .tag(tab)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 330)

            Group {
                switch selectedTab {
                case .annotations:
                    annotationSettings
                case .clicks:
                    clickSettings
                case .keystrokes:
                    keystrokeSettings
                }
            }
        }
        .padding(18)
        .frame(width: 420)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings")
    }

    private var annotationSettings: some View {
        VStack(spacing: 12) {
            SettingsPreviewWell {
                ZStack {
                    AnnotationPreviewStroke()
                        .stroke(
                            Color.black.opacity(0.42),
                            style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
                        )
                    AnnotationPreviewStroke()
                        .stroke(
                            manager.annotationColor.color,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                        )
                }
                .frame(width: 124, height: 34)
            }

            SettingsFormRow(title: "Pen color") {
                PresentationColorPicker(
                    selection: manager.annotationColor,
                    onSelect: { manager.setAnnotationColor($0) }
                )
            }

            SettingsFormRow(title: "Fade after") {
                Picker(
                    "Fade after",
                    selection: Binding(
                        get: { manager.annotationLifetimeSeconds },
                        set: { manager.setAnnotationLifetimeSeconds($0) }
                    )
                ) {
                    ForEach(AnnotationTiming.supportedLifetimeSeconds, id: \.self) { seconds in
                        Text("\(seconds)s")
                            .tag(seconds)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

        }
    }

    private var clickSettings: some View {
        VStack(spacing: 12) {
            SettingsPreviewWell(hidesContentFromAccessibility: false) {
                ClickRipplePreview(
                    color: manager.clickHighlightColor,
                    size: manager.clickHighlightSize
                )
            }

            SettingsFormRow(title: "Ripple size") {
                Picker(
                    "Ripple size",
                    selection: Binding(
                        get: { manager.clickHighlightSize },
                        set: { manager.setClickHighlightSize($0) }
                    )
                ) {
                    ForEach(PresentationSize.allCases) { size in
                        Text(size.label)
                            .tag(size)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            SettingsFormRow(title: "Ripple color") {
                PresentationColorPicker(
                    selection: manager.clickHighlightColor,
                    onSelect: { manager.setClickHighlightColor($0) }
                )
            }

        }
    }

    private var keystrokeSettings: some View {
        VStack(spacing: 12) {
            SettingsPreviewWell {
                KeystrokeBadge(
                    label: "⌘ K",
                    size: manager.keystrokeHighlightSize,
                    appearance: manager.keystrokeAppearance
                )
            }

            SettingsFormRow(title: "Key size") {
                Picker(
                    "Key size",
                    selection: Binding(
                        get: { manager.keystrokeHighlightSize },
                        set: { manager.setKeystrokeHighlightSize($0) }
                    )
                ) {
                    ForEach(PresentationSize.allCases) { size in
                        Text(size.label)
                            .tag(size)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            SettingsFormRow(title: "Appearance") {
                Picker(
                    "Appearance",
                    selection: Binding(
                        get: { manager.keystrokeAppearance },
                        set: { manager.setKeystrokeAppearance($0) }
                    )
                ) {
                    ForEach(KeystrokeAppearance.allCases) { appearance in
                        Text(appearance.label)
                            .tag(appearance)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

        }
    }
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case annotations
    case clicks
    case keystrokes

    var id: Self { self }

    var title: String {
        rawValue.capitalized
    }
}

private struct SettingsFormRow<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 14) {
            Text(title)
                .font(.callout.weight(.medium))
                .frame(width: 92, alignment: .trailing)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 30)
    }
}

private struct SettingsPreviewWell<Content: View>: View {
    let hidesContentFromAccessibility: Bool
    let content: Content

    init(
        hidesContentFromAccessibility: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.hidesContentFromAccessibility = hidesContentFromAccessibility
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Color.primary.opacity(0.045),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .frame(height: 72)
            .accessibilityHidden(hidesContentFromAccessibility)
    }
}

private struct PresentationColorPicker: View {
    let selection: PresentationColor
    let onSelect: (PresentationColor) -> Void

    var body: some View {
        HStack(spacing: 7) {
            ForEach(PresentationColor.allCases) { color in
                Button {
                    onSelect(color)
                } label: {
                    ZStack {
                        if selection == color {
                            Circle()
                                .strokeBorder(Color.primary.opacity(0.88), lineWidth: 2)
                                .frame(width: 28, height: 28)
                        }

                        Circle()
                            .fill(color.color)
                            .frame(width: 22, height: 22)
                            .overlay {
                                Circle()
                                    .strokeBorder(Color.black.opacity(0.16), lineWidth: 1)
                            }

                        if selection == color {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(color.contrastingColor)
                        }
                    }
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
                }
                .buttonStyle(ColorSwatchButtonStyle())
                .help(color.label)
                .accessibilityLabel(color.label)
                .accessibilityValue(selection == color ? "Selected" : "Not selected")
            }
        }
    }
}

private struct ColorSwatchButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.96 : 1))
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.1),
                value: configuration.isPressed
            )
    }
}

private struct ClickRipplePreview: View {
    let color: PresentationColor
    let size: PresentationSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulseGeneration = 0
    @State private var isPlaying = true

    var body: some View {
        let metrics = ClickRippleMetrics(size: size)

        ZStack {
            Group {
                if reduceMotion {
                    staticPreview(
                        metrics: metrics,
                        diameter: metrics.reducedMotionDiameter,
                        lineWidth: 2
                    )
                } else if isPlaying {
                    ClickRippleGlyph(
                        presentation: ClickPresentation(
                            location: NormalizedWindowPoint(x: 0.5, y: 0.5),
                            color: color,
                            size: size
                        ),
                        reducesMotion: false
                    )
                    .id(previewIdentity)
                } else {
                    staticPreview(
                        metrics: metrics,
                        diameter: metrics.initialDiameter,
                        lineWidth: 3
                    )
                }
            }
            .accessibilityHidden(true)

            if !reduceMotion {
                playbackButton
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(7)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: playbackConfiguration) {
            guard isPlaying, !reduceMotion else { return }

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(800))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                pulseGeneration &+= 1
            }
        }
    }

    private var previewConfiguration: String {
        "\(color.rawValue)-\(size.rawValue)-\(reduceMotion)"
    }

    private var previewIdentity: String {
        "\(previewConfiguration)-\(pulseGeneration)"
    }

    private var playbackConfiguration: String {
        "\(previewConfiguration)-\(isPlaying)"
    }

    private var playbackButton: some View {
        Button {
            isPlaying.toggle()
            if isPlaying {
                pulseGeneration &+= 1
            }
        } label: {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 8, weight: .bold))
                .symbolRenderingMode(.monochrome)
                .offset(x: isPlaying ? 0 : 0.5)
                .frame(width: 22, height: 22)
                .background(Color.primary.opacity(0.09), in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.13), lineWidth: 1)
                }
                .contentShape(Circle())
        }
        .buttonStyle(CompactIconButtonStyle())
        .help(isPlaying ? "Pause ripple preview" : "Play ripple preview")
        .accessibilityLabel(isPlaying ? "Pause ripple preview" : "Play ripple preview")
        .accessibilityValue(isPlaying ? "Playing" : "Paused")
        .accessibilityHint("The ripple preview repeats every 800 milliseconds")
    }

    private func staticPreview(
        metrics: ClickRippleMetrics,
        diameter: CGFloat,
        lineWidth: CGFloat
    ) -> some View {
        ZStack {
            Circle()
                .stroke(color.color, lineWidth: lineWidth)
                .frame(width: diameter, height: diameter)
                .opacity(0.82)

            Circle()
                .fill(color.color)
                .frame(width: metrics.dotDiameter, height: metrics.dotDiameter)
        }
        .frame(width: metrics.canvasDiameter, height: metrics.canvasDiameter)
        .shadow(color: .black.opacity(0.26), radius: 2, y: 1)
    }
}

private struct AnnotationPreviewStroke: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 2, y: rect.midY + 8))
        path.addCurve(
            to: CGPoint(x: rect.maxX - 2, y: rect.midY - 6),
            control1: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.minY - 2),
            control2: CGPoint(x: rect.minX + rect.width * 0.64, y: rect.maxY + 3)
        )
        return path
    }
}

// MARK: - Source picker

private struct SourceScrollFadeMask: View {
    let leadingStrength: CGFloat
    let trailingStrength: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            LinearGradient(
                colors: [Color.black.opacity(1 - leadingStrength), .black],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: ControlMetrics.sourceScrollFadeWidth)

            Rectangle()
                .fill(.black)

            LinearGradient(
                colors: [.black, Color.black.opacity(1 - trailingStrength)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: ControlMetrics.sourceScrollFadeWidth)
        }
    }
}

private struct SourceScrollEdgeShadow: View {
    let leadingStrength: CGFloat
    let trailingStrength: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            LinearGradient(
                colors: [Color.black.opacity(0.55 * leadingStrength), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: ControlMetrics.sourceScrollShadowWidth)

            Spacer(minLength: 0)

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.55 * trailingStrength)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: ControlMetrics.sourceScrollShadowWidth)
        }
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
    let isPaused: Bool
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
                        }
                    }
                    Spacer()
                    HStack {
                        if isPaused {
                            Image(systemName: "pause.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .orange)
                                .font(.system(size: ControlMetrics.sourceBadgeIconSize))
                                .transition(.opacity.combined(with: .scale(scale: 0.75)))
                        } else if isSelected && !isPending {
                            Image(systemName: "checkmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .blue)
                                .font(.system(size: ControlMetrics.sourceBadgeIconSize))
                                .transition(.opacity.combined(with: .scale(scale: 0.75)))
                        }
                        Spacer()
                        if let icon = source.applicationIcon {
                            Image(nsImage: icon)
                                .resizable()
                                .scaledToFit()
                                .frame(
                                    width: ControlMetrics.sourceBadgeIconSize,
                                    height: ControlMetrics.sourceBadgeIconSize
                                )
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
        .accessibilityValue(
            isPending ? "Switching" : isPaused ? "Paused" : isSelected ? "Live" : "Not live"
        )
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var borderColor: Color {
        if isPending { return .orange }
        if isPaused { return .orange }
        if isSelected { return .blue }
        return .white.opacity(0.14)
    }

    private var borderWidth: CGFloat {
        isPending || isSelected ? 2 : 1
    }

    private var visualState: Int {
        isPending ? 3 : isPaused ? 2 : isSelected ? 1 : 0
    }

    private var accessibilityLabel: String {
        let action = isPaused ? "Resume sharing" : isSelected ? "Pause sharing" : "Share"
        let name = "\(action) \(source.applicationName), \(source.title)"
        guard let shortcut else { return name }
        return "\(name), shortcut Option \(shortcut)"
    }

    private var accessibilityHint: String {
        if isPaused {
            return "Resumes this window. Open the context menu to pin a global shortcut."
        }
        if isSelected {
            return "Pauses this window. Open the context menu to pin a global shortcut."
        }
        return "Selects this window. Open the context menu to pin a global shortcut."
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

// MARK: - Shared controls

private struct PermissionActionButton: View {
    let systemImage: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 24, height: ControlMetrics.contentHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(CompactIconButtonStyle())
        .help(title)
        .accessibilityLabel(title)
    }
}

private struct ControlBarButton: View {
    let systemImage: String
    let title: String
    let help: String
    var isOn: Bool?
    var isPresented: Bool?
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
                        .font(.system(size: ControlMetrics.controlBarIconSize, weight: .medium))
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
                    isActive
                        ? Color.primary
                        : (isHovering && isEnabled ? Color.primary : Color.secondary)
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
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.12),
            value: isPresented
        )
    }

    private var buttonBackground: Color {
        guard isEnabled else { return .clear }
        if isActive {
            return Color.primary.opacity(isHovering ? 0.16 : 0.11)
        }
        return isHovering ? Color.primary.opacity(0.07) : .clear
    }

    private var isActive: Bool {
        isOn == true || isPresented == true
    }

    private var accessibilityValue: String {
        guard isEnabled else { return "Unavailable" }
        if let isPresented {
            return isPresented ? "Open" : "Closed"
        }
        guard let isOn else { return "Coming soon" }
        if showsPermissionWarning { return "Permission required" }
        return isOn ? "On" : "Off"
    }
}

private struct CompactIconButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.96 : 1))
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.1),
                value: configuration.isPressed
            )
    }
}
