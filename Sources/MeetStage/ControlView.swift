import SwiftUI

enum ControlMetrics {
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
    @ObservedObject private var windowState = BetterMeetsWindowState.shared
    @FocusState private var focusedSourceID: CGWindowID?

    var body: some View {
        VStack(spacing: 0) {
            if manager.needsScreenRecordingPermission {
                permissionNotice
            } else if manager.windows.isEmpty && unavailableSlots.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "macwindow")
                        .font(.title2)
                    Text(manager.isRefreshing ? "Finding windows…" : "No windows")
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
        .onChange(of: windowState.sourceFocusRequest) { _, _ in
            focusedSourceID = manager.selectedWindowID ?? manager.displayedWindows.first?.id
        }
    }

    private var sourceScroller: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 8) {
                    ForEach(manager.displayedWindows) { source in
                        windowButton(for: source)
                            .id(source.id)
                    }
                    ForEach(unavailableSlots, id: \.self) { slot in
                        EmptyShortcutSlot(
                            slot: slot,
                            pinnedWindowDescription: manager.shortcutOwnerDescription(for: slot),
                            shortcutModifier: manager.globalShortcutModifier,
                            unpin: { manager.unpinSlot(slot) }
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onMoveCommand(perform: moveSourceFocus)
            .onChange(of: manager.pendingWindowID ?? manager.selectedWindowID) { _, sourceID in
                if focusedSourceID != nil {
                    focusedSourceID = sourceID
                }
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
            action: {
                focusedSourceID = source.id
                manager.select(source)
            },
            pin: { manager.pin(source, to: $0) },
            unpin: { manager.unpin(source) }
        )
        .focused($focusedSourceID, equals: source.id)
    }

    private func scrollTo(_ sourceID: CGWindowID?, using proxy: ScrollViewProxy) {
        guard let sourceID else { return }
        proxy.scrollTo(sourceID)
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
            Text("Screen recording required")
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .controlSize(.small)
        .padding(14)
        .frame(maxHeight: .infinity)
    }
}
