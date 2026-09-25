import SwiftUI

struct EmptyShortcutSlot: View {
    let slot: Int
    let pinnedWindowDescription: String?
    let shortcutModifier: GlobalShortcutModifier

    @Environment(\.colorSchemeContrast) private var contrast

    private var isUnavailable: Bool { pinnedWindowDescription != nil }

    var body: some View {
        VStack(spacing: ControlMetrics.sourceLabelSpacing) {
            Text(isUnavailable ? "Unavailable" : "Empty")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: ControlMetrics.sourceLabelHeight)

            ZStack {
                RoundedRectangle(cornerRadius: ControlMetrics.sourceTileRadius)
                    .fill(.primary.opacity(0.035))
                RoundedRectangle(cornerRadius: ControlMetrics.sourceTileRadius)
                    .strokeBorder(
                        isUnavailable ? ControlPalette.warning : .primary.opacity(contrast == .increased ? 0.5 : 0.20),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                    )
                if isUnavailable {
                    Image(systemName: "pin.slash")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(.secondary)
                }
                Text(shortcutModifier.displayName(for: slot))
                    .font(.system(size: 11, weight: .semibold).monospaced())
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
            .frame(height: ControlMetrics.sourcePreviewHeight)

        }
        .frame(width: ControlMetrics.sourceTileWidth)
        .help(helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(helpText)
        .accessibilityHint(
            isUnavailable
                ? "The pinned window will return here when it is available"
                : "A window can be pinned here from its context menu")
    }

    private var helpText: String {
        if let pinnedWindowDescription {
            return "\(shortcutModifier.displayName(for: slot)): \(pinnedWindowDescription) is unavailable"
        }
        return "\(shortcutModifier.displayName(for: slot)): Empty shortcut slot"
    }
}

struct CompactWindowButton: View {
    let source: WindowSource
    let shortcut: Int?
    let shortcutModifier: GlobalShortcutModifier
    let isShortcutAvailable: Bool
    let isSelected: Bool
    let isPaused: Bool
    let isPending: Bool
    let isKeyboardFocused: Bool
    let shortcutOwner: (Int) -> String?
    let action: () -> Void
    let pin: (Int) -> Void
    let unpin: () -> Void

    @State private var showPreview = false
    @State private var hoverTask: Task<Void, Never>?
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        Button {
            hoverTask?.cancel()
            showPreview = false
            action()
        } label: {
            VStack(spacing: ControlMetrics.sourceLabelSpacing) {
                identityRow
                sourcePreview
                Text(source.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: ControlMetrics.sourceTileWidth)
            .padding(6)
            .background(
                ControlPalette.accent.opacity(isSelected ? 0.09 : 0),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(CompactIconButtonStyle())
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.space) {
            showPreview.toggle()
            return .handled
        }
        .onKeyPress(.return) {
            showPreview = false
            action()
            return .handled
        }
        .contextMenu {
            Button(isPaused ? "Resume Sharing" : isSelected ? "Pause Sharing" : "Put on Stage", action: action)
            Button("Preview Window") { showPreview = true }
            Divider()
            Menu(shortcutModifier == .disabled ? "Pin Source Slot" : "Pin Global Shortcut") {
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
                Button(
                    "Unpin \(shortcutModifier.displayName(for: shortcut))",
                    role: .destructive,
                    action: unpin
                )
            }
        }
        .onHover { isHovering in
            self.isHovering = isHovering
            hoverTask?.cancel()

            if isHovering {
                hoverTask = Task { @MainActor in
                    do {
                        try await Task.sleep(for: .milliseconds(450))
                    } catch {
                        return
                    }
                    guard !Task.isCancelled else { return }
                    showPreview = true
                }
            } else {
                showPreview = false
            }
        }
        .popover(isPresented: $showPreview, arrowEdge: .trailing) {
            WindowHoverPreview(
                source: source,
                shortcut: shortcut,
                shortcutModifier: shortcutModifier,
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

    private var sourcePreview: some View {
        ZStack {
            Color.black.opacity(0.85)
            if let thumbnail = source.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFit()
            } else if let icon = source.applicationIcon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: "macwindow")
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .frame(width: ControlMetrics.sourcePreviewWidth, height: ControlMetrics.sourcePreviewHeight)
        .clipped()
        .overlay { Color.white.opacity(isHovering ? 0.08 : 0) }
        .overlay(alignment: .bottomTrailing) {
            if let shortcut {
                shortcutKeycap(shortcut)
                    .padding(5)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if isKeyboardFocused {
                Image(systemName: "return")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 4))
                    .padding(5)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: ControlMetrics.sourceTileRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ControlMetrics.sourceTileRadius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: isSelected || isPending || isKeyboardFocused ? 2 : 1)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: visualState)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
    }

    private var identityRow: some View {
        HStack(spacing: 4) {
            if let icon = source.applicationIcon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: ControlMetrics.sourceApplicationIconSize,
                        height: ControlMetrics.sourceApplicationIconSize)
            }
            Text(source.applicationName)
                .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                .lineLimit(1)
            Spacer(minLength: 0)
            if isPending {
                ProgressView().controlSize(.mini)
            } else if isPaused || isSelected {
                Image(systemName: isPaused ? "pause.fill" : "play.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isPaused ? ControlPalette.warning : ControlPalette.accent)
                    .frame(width: 12)
            }
        }
        .frame(height: ControlMetrics.sourceLabelHeight)
        .accessibilityHidden(true)
    }

    private func shortcutKeycap(_ slot: Int) -> some View {
        HStack(spacing: 3) {
            if !isShortcutAvailable {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
            }
            Text(shortcutModifier.displayName(for: slot))
                .font(.system(size: 11, weight: .semibold).monospaced())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(
            keycapColor,
            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
        }
    }

    private var keycapColor: Color {
        if !isShortcutAvailable { return .red.opacity(0.95) }
        if isPaused || isPending { return ControlPalette.warning }
        if isSelected { return ControlPalette.accent }
        return .black.opacity(0.82)
    }

    private var borderColor: Color {
        if isPending || isPaused { return ControlPalette.warning }
        if isSelected || isKeyboardFocused { return ControlPalette.accent }
        return .white.opacity(colorSchemeContrast == .increased ? 0.6 : isHovering ? 0.35 : 0.18)
    }

    private var visualState: Int {
        isPending ? 3 : isPaused ? 2 : isSelected ? 1 : 0
    }

    private var accessibilityLabel: String {
        let action = isPaused ? "Resume sharing" : isSelected ? "Pause sharing" : "Share"
        let name = "\(action) \(source.applicationName), \(source.title)"
        guard let shortcut else { return name }
        return "\(name), shortcut \(shortcutModifier.spokenName(for: shortcut))"
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
            Label("\(shortcutModifier.displayName(for: slot)) — Current", systemImage: "checkmark")
        } else if let owner = shortcutOwner(slot) {
            Text("\(shortcutModifier.displayName(for: slot)) — Replace \(owner)")
        } else {
            Text(shortcutModifier.displayName(for: slot))
        }
    }
}
