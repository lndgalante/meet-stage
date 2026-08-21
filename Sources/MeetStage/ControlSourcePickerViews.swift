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

struct SourceScrollEdgeShadow: View {
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

struct EmptyShortcutSlot: View {
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

struct CompactWindowButton: View {
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
                    }
                }
                .padding(4)
            }
            .frame(width: ControlMetrics.sourceTileWidth, height: ControlMetrics.sourceTileHeight)
            .overlay(alignment: .bottomTrailing) {
                if let icon = source.applicationIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(
                            width: ControlMetrics.sourceApplicationIconSize,
                            height: ControlMetrics.sourceApplicationIconSize
                        )
                        .offset(
                            x: ControlMetrics.sourceApplicationIconHorizontalOffset,
                            y: ControlMetrics.sourceApplicationIconVerticalOffset
                        )
                }
            }
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
