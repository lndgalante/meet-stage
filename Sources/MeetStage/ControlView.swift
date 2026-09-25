import SwiftUI

enum ControlMetrics {
    static let sourceTileWidth: CGFloat = 148
    static let sourcePreviewWidth = sourceTileWidth
    static let sourcePreviewHeight: CGFloat = 84
    static let sourceTileRadius: CGFloat = 8
    static let sourceLabelHeight: CGFloat = 18
    static let sourceLabelSpacing: CGFloat = 4
    static let sourceApplicationIconSize: CGFloat = 14
    static let controlBarButtonHeight: CGFloat = 30
    static let controlBarActionCornerRadius: CGFloat = 8
    static let controlBarIconSize: CGFloat = 13
    static let clickHighlightGlyphOffset = CGSize(width: -0.5, height: -0.5)
    static let keystrokeHighlightGlyphOffset = CGSize(width: 0.25, height: -0.5)
}

enum ControlPalette {
    static let accent = Color.accentColor
    static let warning = Color.orange
}

struct ControlView: View {
    @ObservedObject var manager: CaptureManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedSourceID: CGWindowID?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Windows")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(manager.windows.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
                Button("Refresh Windows", systemImage: "arrow.clockwise") {
                    manager.refreshWindows()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(manager.isRefreshing)
                .help("Refresh windows (⌘R)")
            }
            .padding(.horizontal, 14)
            .frame(height: 36)

            if manager.needsScreenRecordingPermission {
                permissionNotice
            } else if manager.windows.isEmpty && unavailableSlots.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "macwindow")
                        .font(.title2)
                    Text(manager.isRefreshing ? "Finding windows…" : "Open an app to get started")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
                .padding(16)
                .frame(maxHeight: .infinity)
            } else {
                sourceScroller
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Window selector")
    }

    private var sourceScroller: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 12) {
                    ForEach(manager.displayedWindows) { source in
                        windowButton(for: source)
                            .id(source.id)
                    }
                    ForEach(unavailableSlots, id: \.self) { slot in
                        EmptyShortcutSlot(
                            slot: slot,
                            pinnedWindowDescription: manager.shortcutOwnerDescription(for: slot),
                            shortcutModifier: manager.globalShortcutModifier
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .onMoveCommand(perform: moveSourceFocus)
            .onChange(of: manager.pendingWindowID ?? manager.selectedWindowID) { _, sourceID in
                scrollTo(sourceID, using: proxy)
            }
            .onChange(of: focusedSourceID) { _, sourceID in
                scrollTo(sourceID, using: proxy)
            }
            .onAppear {
                scrollTo(manager.selectedWindowID, using: proxy)
            }
        }
    }

    private var unavailableSlots: [Int] {
        ShortcutSlot.all.filter {
            manager.window(forShortcutSlot: $0) == nil && manager.shortcutPins[$0] != nil
        }
    }

    private func windowButton(for source: WindowSource) -> some View {
        let shortcut = manager.shortcut(for: source)
        let isSelected = source.id == manager.selectedWindowID
        return CompactWindowButton(
            source: source,
            shortcut: shortcut,
            shortcutModifier: manager.globalShortcutModifier,
            isShortcutAvailable: shortcut.map { !manager.unavailableShortcutSlots.contains($0) } ?? true,
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

    private func scrollTo(_ sourceID: CGWindowID?, using proxy: ScrollViewProxy) {
        guard let sourceID else { return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1)) {
            proxy.scrollTo(sourceID, anchor: .center)
        }
    }

    private func moveSourceFocus(_ direction: MoveCommandDirection) {
        guard direction == .up || direction == .down else { return }
        let ids = manager.displayedWindows.map(\.id)
        guard !ids.isEmpty else { return }
        let current = (focusedSourceID ?? manager.selectedWindowID).flatMap { ids.firstIndex(of: $0) }
        let index = current ?? (direction == .down ? -1 : ids.count)
        focusedSourceID = ids[min(max(index + (direction == .down ? 1 : -1), 0), ids.count - 1)]
    }

    private var permissionNotice: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.rectangle")
                .font(.title2)
                .foregroundStyle(.orange)
            Text("Allow screen recording to see your windows")
                .font(.caption)
                .multilineTextAlignment(.center)
            Button("Allow Access") { manager.requestScreenRecordingPermission() }
            Button("Restart BetterMeets") { manager.restartApplication() }
                .buttonStyle(.link)
                .font(.caption)
        }
        .controlSize(.small)
        .padding(14)
        .frame(maxHeight: .infinity)
    }
}
