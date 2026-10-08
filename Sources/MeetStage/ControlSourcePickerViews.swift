import SwiftUI

struct EmptyShortcutSlot: View {
    let slot: Int
    let pinnedWindowDescription: String?
    let shortcutModifier: GlobalShortcutModifier
    let unpin: () -> Void

    var body: some View {
        Button(action: unpin) {
            Image(systemName: "pin.slash")
                .font(.title2)
                .foregroundStyle(.orange)
                .frame(width: 68, height: 68)
        }
        .buttonStyle(CompactIconButtonStyle())
        .help(
            "\(pinnedWindowDescription ?? "Pinned window") is unavailable. Unpin \(shortcutModifier.displayName(for: slot))."
        )
        .contextMenu { Button("Unpin Window", action: unpin) }
        .accessibilityLabel("Unpin unavailable window: \(pinnedWindowDescription ?? "Pinned window")")
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
    let shortcutOwner: (Int) -> String?
    let action: () -> Void
    let pin: (Int) -> Void
    let unpin: () -> Void

    @State private var showPreview = false
    @State private var hoverTask: Task<Void, Never>?
    @State private var isHovering = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button {
            hoverTask?.cancel()
            showPreview = false
            action()
        } label: {
            applicationIcon
                .frame(width: 56, height: 56)
                .frame(width: 68, height: 68)
                .background(
                    (isPaused ? Color.orange : Color.primary)
                        .opacity(isSelected ? 0.12 : isHovering ? 0.06 : 0),
                    in: RoundedRectangle(cornerRadius: 16)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(borderColor, lineWidth: 2)
                }
                .overlay(alignment: .topTrailing) {
                    if isPending {
                        ProgressView().controlSize(.mini)
                    } else if isPaused {
                        Image(systemName: "pause.circle.fill")
                            .foregroundStyle(.orange)
                            .background(.background, in: Circle())
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if let shortcut {
                        Text(shortcutModifier.displayName(for: shortcut))
                            .font(.caption2.weight(.semibold).monospaced())
                            .foregroundStyle(isShortcutAvailable ? Color.primary : .red)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Color(nsColor: .windowBackgroundColor.withAlphaComponent(1)),
                                in: Capsule()
                            )
                            .overlay {
                                Capsule()
                                    .strokeBorder(
                                        .primary.opacity(contrast == .increased ? 0.5 : 0.1),
                                        lineWidth: 1
                                    )
                            }
                            .padding(3)
                            .accessibilityHidden(true)
                    }
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

    @ViewBuilder
    private var applicationIcon: some View {
        if let icon = source.applicationIcon {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "macwindow")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
        }
    }

    private var borderColor: Color {
        if isPending || isPaused { return ControlPalette.warning }
        if isSelected { return ControlPalette.accent }
        if isKeyboardFocused { return .secondary }
        return contrast == .increased ? .secondary : .clear
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
