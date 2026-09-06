import SwiftUI

/*
 THESIS: Recognize a window, switch it, and see what the audience is viewing.
 OWN-WORLD: Native macOS utility; real previews, app icons, system type and materials.
 STORY: App identity → preview → current sharing status.
 FIRST VIEWPORT: Four labeled sources, shortcut keycaps, and status with trailing guidance.
 FORM: Surface seed 324e2ed7; approved C, a compact filmstrip with labels above previews.
 FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, and DESIGN.md
 */

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
    static let sourceTileRadius: CGFloat = 8
    static let sourcePreviewWidth = sourceTileWidth
    static let sourcePreviewHeight: CGFloat = 66
    static let sourceLabelHeight: CGFloat = 18
    static let sourceLabelSpacing: CGFloat = 4
    static let sourceApplicationIconSize: CGFloat = 14
    static let sourceScrollFadeWidth: CGFloat = 22
    static let sourceScrollCoordinateSpace = "source-scroll"
    static let controlBarButtonHeight: CGFloat = 30
    static let controlBarActionSize: CGFloat = 28
    static let controlBarActionCornerRadius: CGFloat = 9.5
    static let controlBarIconSize: CGFloat = 13
    static let permissionActionSize: CGFloat = 28
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
    var openSettings: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.legibilityWeight) private var legibilityWeight
    @ScaledMetric(relativeTo: .caption) private var permissionIconSize: CGFloat = 14
    @State private var sourceScrollBounds = CGRect.zero
    @FocusState private var focusedSourceID: CGWindowID?

    var body: some View {
        VStack(spacing: 0) {
            sourceRow
                .frame(height: ControlWindowSizing.sourceRegionHeight)

            SourceStatusFooter(guidance: sourceGuidance)
        }
        .frame(width: ControlWindowSizing.panelWidth)
        .background {
            SourcePanelBackground()
        }
        .clipShape(RoundedRectangle(cornerRadius: ControlWindowSizing.panelCornerRadius, style: .continuous))
        .fontWeight(legibilityWeight == .bold ? .bold : nil)
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
            manager.startWindowMonitoring()
            manager.refreshWindows()
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

    private var sourceGuidance: SourceSelectionGuidance {
        let selected = manager.windows.first { $0.id == manager.selectedWindowID }
        let pending = manager.windows.first { $0.id == manager.pendingWindowID }
        let suggested = orderedSources.first
        let shortcut = suggested.flatMap { source in
            manager.shortcut(for: source).flatMap { slot in
                manager.globalShortcutModifier != .disabled
                    && !manager.unavailableShortcutSlots.contains(slot)
                    ? manager.globalShortcutModifier.displayName(for: slot) : nil
            }
        }
        return SourceSelectionGuidance(
            state: manager.state,
            selectedApplication: selected?.applicationName,
            pendingApplication: pending?.applicationName,
            suggestedApplication: suggested?.applicationName,
            shortcut: shortcut
        )
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
            .onKeyPress(.return) {
                guard let source = orderedSources.first(where: { $0.id == focusedSourceID }) else { return .ignored }
                manager.select(source)
                return .handled
            }
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

    private var orderedSources: [WindowSource] {
        visibleShortcutSlots.compactMap { manager.window(forShortcutSlot: $0) }
            + manager.unassignedDisplayedWindows
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
        let sourceIDs = orderedSources.map(\.id)
        guard !sourceIDs.isEmpty else { return }

        let currentID = focusedSourceID ?? manager.selectedWindowID
        let currentIndex =
            currentID.flatMap { sourceIDs.firstIndex(of: $0) }
            ?? (direction == .right ? -1 : sourceIDs.count)
        let offset = direction == .right ? 1 : -1
        let nextIndex = min(max(currentIndex + offset, 0), sourceIDs.count - 1)
        focusedSourceID = sourceIDs[nextIndex]
    }

    private var permissionStrip: some View {
        HStack(spacing: 5) {
            Image(systemName: "lock.screen")
                .font(.system(size: permissionIconSize, weight: .medium))
                .foregroundStyle(ControlPalette.warning)

            Text("Allow screen recording")
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.75)

            Spacer(minLength: 2)

            PermissionActionButton(
                systemImage: "gearshape",
                title: "Allow Screen Recording",
                action: manager.requestScreenRecordingPermission
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
