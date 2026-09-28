import SwiftUI

struct EmptyShortcutSlot: View {
    let slot: Int
    let pinnedWindowDescription: String?
    let shortcutModifier: GlobalShortcutModifier
    let unpin: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "pin.slash")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Window unavailable")
                    .font(.callout.weight(.medium))
                Text(pinnedWindowDescription ?? "Pinned window")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Button("Unpin", action: unpin)
                    .buttonStyle(.link)
                    .font(.caption)
            }
            Spacer(minLength: 0)
            Text(shortcutModifier.displayName(for: slot))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu { Button("Unpin Window", action: unpin) }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Unpin Window", unpin)
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
    var compact = false
    let shortcutOwner: (Int) -> String?
    let action: () -> Void
    let pin: (Int) -> Void
    let unpin: () -> Void

    @State private var showPreview = false
    @State private var hoverTask: Task<Void, Never>?
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            hoverTask?.cancel()
            showPreview = false
            action()
        } label: {
            Group {
                if compact {
                    HStack(spacing: 10) {
                        sourcePreview.frame(width: 64, height: 40)
                        VStack(alignment: .leading, spacing: 4) {
                            identityRow
                            if source.hasDistinctTitle { titleLabel }
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        identityRow
                        sourcePreview.aspectRatio(16 / 9, contentMode: .fit)
                        if source.hasDistinctTitle { titleLabel }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(6)
            .background(
                (isPaused ? Color.orange : Color.primary).opacity(isSelected ? 0.07 : 0),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(borderColor, lineWidth: 2)
            }
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
            Button(isPaused ? "Resume Stage" : "Put on Stage", action: action)
                .disabled(isSelected && !isPaused)
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
            isPending ? "Preparing" : isPaused ? "Paused" : isSelected ? "On stage" : "Not on stage"
        )
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var sourcePreview: some View {
        Color.black
            .overlay {
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
            .clipped()
            .overlay { Color.white.opacity(isHovering ? 0.08 : 0) }
            .clipShape(RoundedRectangle(cornerRadius: ControlMetrics.sourceTileRadius, style: .continuous))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
    }

    private var titleLabel: some View {
        Text(source.title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(compact ? 2 : 1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var identityRow: some View {
        HStack(spacing: 4) {
            if !compact, let icon = source.applicationIcon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: ControlMetrics.sourceApplicationIconSize,
                        height: ControlMetrics.sourceApplicationIconSize)
            }
            Text(source.applicationName)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(compact ? 2 : 1)
            Spacer(minLength: 0)
            if isPending {
                ProgressView().controlSize(.mini)
            } else if isPaused || isSelected {
                Image(systemName: isPaused ? "pause.fill" : "circle.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isPaused ? ControlPalette.warning : ControlPalette.accent)
                    .frame(width: 10)
            }
            if let shortcut { shortcutKeycap(shortcut) }
        }
        .frame(minHeight: ControlMetrics.sourceLabelHeight)
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
        .foregroundStyle(isShortcutAvailable ? Color.secondary : .red)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
        .fixedSize()
    }

    private var borderColor: Color {
        if isPending || isPaused { return ControlPalette.warning }
        if isSelected || isKeyboardFocused { return ControlPalette.accent }
        return .clear
    }

    private var accessibilityLabel: String {
        let action = isPaused ? "Resume" : "Select"
        let name = "\(action) \(source.applicationName), \(source.title)"
        guard let shortcut else { return name }
        return "\(name), shortcut \(shortcutModifier.spokenName(for: shortcut))"
    }

    private var accessibilityHint: String {
        if isPaused {
            return "Resumes this window. Press Space to preview, or open the context menu to pin it."
        }
        if isSelected {
            return "This window is already on stage. Use Pause Stage to hide it."
        }
        return "Puts this window on stage. Press Space to preview, or open the context menu to pin it."
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
