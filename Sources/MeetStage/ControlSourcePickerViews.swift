import SwiftUI

struct SourceScrollFadeMask: View {
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

/// Edge affordance for the horizontally scrollable source row: a chevron fades
/// in on whichever side has more windows to reveal, so a clipped row reads as
/// "scroll this way for more" rather than as a muddy dark cut-off. It pairs with
/// the scroller's own alpha fade mask (which softens the partial tiles).
struct SourceScrollEdgeShadow: View {
    let leadingStrength: CGFloat
    let trailingStrength: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            chevron(systemName: "chevron.compact.left", strength: leadingStrength)
            Spacer(minLength: 0)
            chevron(systemName: "chevron.compact.right", strength: trailingStrength)
        }
        .padding(.horizontal, ControlMetrics.outerPadding)
        .padding(.vertical, ControlMetrics.sourceTileVerticalInset)
        // Align the edge affordances to the rail's shared six-point inset.
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func chevron(systemName: String, strength: CGFloat) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(0.76))
            .shadow(color: .black.opacity(0.56), radius: 2)
            .opacity(Double(min(max(strength, 0), 1)))
            .frame(height: ControlMetrics.sourceTileHeight)
    }
}

struct EmptyShortcutSlot: View {
    let slot: Int
    let pinnedWindowDescription: String?
    let shortcutModifier: GlobalShortcutModifier

    private var isUnavailablePin: Bool { pinnedWindowDescription != nil }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: ControlMetrics.sourceTileRadius, style: .continuous)
                .fill(Color.black.opacity(isUnavailablePin ? 0.20 : 0.14))

            RoundedRectangle(cornerRadius: ControlMetrics.sourceTileRadius, style: .continuous)
                .strokeBorder(
                    isUnavailablePin
                        ? ControlPalette.warning.opacity(0.42)
                        : Color.white.opacity(0.11),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                )

            Text(shortcutModifier.displayName(for: slot))
                .font(.caption2.bold().monospaced())
                .foregroundStyle(Color.white.opacity(isUnavailablePin ? 0.72 : 0.46))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.34), in: Capsule())
                .padding(4)

            if isUnavailablePin {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(ControlPalette.warning)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(5)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: ControlMetrics.sourceTileWidth, height: ControlMetrics.sourceTileHeight)
        .help(helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(shortcutModifier.spokenName(for: slot)), empty shortcut slot")
        .accessibilityHint(accessibilityHint)
    }

    private var helpText: String {
        if let pinnedWindowDescription {
            return "\(shortcutModifier.displayName(for: slot)): \(pinnedWindowDescription) is unavailable"
        }
        return "\(shortcutModifier.displayName(for: slot)): Empty shortcut slot"
    }

    private var accessibilityHint: String {
        if pinnedWindowDescription != nil {
            return "The pinned window is currently unavailable"
        }
        return "A window can be pinned here from its context menu"
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

    var body: some View {
        Button(action: action) {
            sourcePreview
                .frame(
                    width: ControlMetrics.sourceTileWidth,
                    height: ControlMetrics.sourceTileHeight,
                    alignment: .topLeading
                )
                .overlay(alignment: .bottomTrailing) {
                    if let icon = source.applicationIcon {
                        ApplicationIconBadge(icon: icon)
                            .padding(3)
                    }
                }
        }
        .buttonStyle(CompactIconButtonStyle())
        .overlay {
            RoundedRectangle(cornerRadius: ControlMetrics.sourceTileRadius, style: .continuous)
                .strokeBorder(ControlPalette.accent, lineWidth: 2)
                .padding(-2)
                .opacity(isKeyboardFocused ? 1 : 0)
        }
        .contextMenu {
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
        .popover(isPresented: $showPreview, arrowEdge: .bottom) {
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
            RoundedRectangle(cornerRadius: ControlMetrics.sourceTileRadius, style: .continuous)
                .fill(Color.black.opacity(0.78))

            if let thumbnail = source.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: ControlMetrics.sourcePreviewWidth,
                        height: ControlMetrics.sourcePreviewHeight
                    )
                    .clipped()
            } else if let icon = source.applicationIcon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .padding(10)
            } else {
                Image(systemName: "macwindow")
                    .foregroundStyle(Color.white.opacity(0.44))
            }

            LinearGradient(
                colors: [Color.black.opacity(0.30), .clear, Color.black.opacity(0.22)],
                startPoint: .top,
                endPoint: .bottom
            )

            Color.white.opacity(isHovering ? 0.045 : 0)

            VStack {
                HStack {
                    if let shortcut {
                        Text(shortcutModifier.displayName(for: shortcut))
                            .font(.caption2.bold().monospaced())
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .foregroundStyle(.white)
                            .background(
                                isShortcutAvailable
                                    ? Color.black.opacity(0.66)
                                    : Color.red.opacity(0.90),
                                in: Capsule()
                            )
                            .overlay {
                                Capsule()
                                    .strokeBorder(Color.white.opacity(0.13), lineWidth: 0.5)
                            }
                    }
                    Spacer()
                    if isPending {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(ControlPalette.warning)
                    }
                }
                Spacer()
                HStack {
                    if isPaused {
                        Image(systemName: "pause.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, ControlPalette.warning)
                            .font(.system(size: ControlMetrics.sourceBadgeIconSize))
                    } else if isSelected && !isPending {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, ControlPalette.accent)
                            .font(.system(size: ControlMetrics.sourceBadgeIconSize))
                    }
                    Spacer()
                }
            }
            .padding(4)
        }
        .frame(width: ControlMetrics.sourcePreviewWidth, height: ControlMetrics.sourcePreviewHeight)
        .clipShape(
            RoundedRectangle(cornerRadius: ControlMetrics.sourceTileRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: ControlMetrics.sourceTileRadius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: borderWidth)
        }
        .shadow(color: .black.opacity(0.28), radius: 2, y: 1)
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.14),
            value: visualState
        )
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.12),
            value: isHovering
        )
    }

    private var borderColor: Color {
        if isPending { return ControlPalette.warning }
        if isPaused { return ControlPalette.warning }
        if isSelected { return ControlPalette.accent }
        return .white.opacity(isHovering ? 0.26 : 0.12)
    }

    private var borderWidth: CGFloat {
        isPending || isSelected ? 1.5 : 1
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

private struct ApplicationIconBadge: View {
    let icon: NSImage

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .scaledToFit()
            .frame(
                width: ControlMetrics.sourceApplicationIconSize,
                height: ControlMetrics.sourceApplicationIconSize
            )
            .frame(
                width: ControlMetrics.sourceApplicationBadgeSize,
                height: ControlMetrics.sourceApplicationBadgeSize
            )
            .background(
                Color.black.opacity(0.72),
                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
            )
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.24), lineWidth: 0.75)
            }
            .shadow(color: Color.black.opacity(0.46), radius: 2, y: 1)
            .accessibilityHidden(true)
    }
}

private struct WindowHoverPreview: View {
    let source: WindowSource
    let shortcut: Int?
    let shortcutModifier: GlobalShortcutModifier
    let isShortcutAvailable: Bool

    @Environment(\.colorScheme) private var colorScheme

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
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        colorScheme == .dark
                            ? Color.white.opacity(0.10)
                            : Color.black.opacity(0.10),
                        lineWidth: 1
                    )
            }

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
                    Text(
                        isShortcutAvailable
                            ? shortcutModifier.displayName(for: shortcut)
                            : "\(shortcutModifier.displayName(for: shortcut)) unavailable"
                    )
                        .font(.caption.bold().monospaced())
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
