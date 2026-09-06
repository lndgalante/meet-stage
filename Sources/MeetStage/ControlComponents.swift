import SwiftUI

struct PermissionActionButton: View {
    let systemImage: String
    let title: String
    let action: () -> Void

    @State private var isHovering = false
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(isHovering ? 0.10 : 0))

                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(
                        Color.primary.opacity(
                            isHovering || colorSchemeContrast == .increased ? 0.96 : 0.72
                        )
                    )
            }
            .frame(
                width: ControlMetrics.permissionActionSize,
                height: ControlMetrics.permissionActionSize
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(CompactIconButtonStyle())
        .focused($isFocused)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(ControlPalette.accent, lineWidth: 2)
                .opacity(isFocused ? 1 : 0)
        }
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
        .help(title)
        .accessibilityLabel(title)
    }
}

struct ControlBarButton: View {
    let systemImage: String
    let title: String
    let help: String
    var isOn: Bool?
    var isPresented: Bool?
    var glyphOffset = CGSize.zero
    var isEnabled = true
    var showsPermissionWarning = false
    let action: () -> Void
    var settingsAction: (() -> Void)? = nil

    @State private var isHovering = false
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(
                    cornerRadius: ControlMetrics.controlBarActionCornerRadius,
                    style: .continuous
                )
                .fill(buttonBackground)

                ZStack {
                    Image(systemName: systemImage)
                        .font(.system(size: ControlMetrics.controlBarIconSize, weight: .medium))
                        .symbolRenderingMode(.monochrome)
                        .offset(x: glyphOffset.width, y: glyphOffset.height)

                    if showsPermissionWarning {
                        PermissionWarningBadge()
                            .offset(x: 9, y: -9)
                    }
                }
                .foregroundStyle(
                    isActive
                        ? ControlPalette.accent
                        : Color.primary.opacity(
                            isHovering && isEnabled || colorSchemeContrast == .increased ? 0.92 : 0.62
                        )
                )
            }
            .frame(
                width: ControlMetrics.controlBarActionSize,
                height: ControlMetrics.controlBarActionSize
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(CompactIconButtonStyle())
        .focused($isFocused)
        .disabled(!isEnabled)
        .help(help)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(help)
        .accessibilityAddTraits(isOn == true ? .isSelected : [])
        .frame(maxWidth: .infinity)
        .frame(height: ControlMetrics.controlBarButtonHeight)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .contextMenu {
            if let settingsAction {
                Button("\(title) Settings…", action: settingsAction)
            }
        }
        .overlay {
            RoundedRectangle(
                cornerRadius: ControlMetrics.controlBarActionCornerRadius,
                style: .continuous
            )
            .strokeBorder(ControlPalette.accent, lineWidth: 2)
            .opacity(isFocused ? 1 : 0)
        }
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
            return ControlPalette.accent.opacity(isHovering ? 0.20 : 0.14)
        }
        return isHovering ? Color.primary.opacity(0.08) : .clear
    }

    private var isActive: Bool {
        isOn == true || isPresented == true
    }

    private var accessibilityValue: String {
        guard isEnabled else { return String(localized: "Unavailable") }
        if let isPresented {
            return isPresented ? String(localized: "Open") : String(localized: "Closed")
        }
        guard let isOn else { return String(localized: "Available") }
        if showsPermissionWarning { return String(localized: "Permission required") }
        return isOn ? String(localized: "On") : String(localized: "Off")
    }
}

/// A high-contrast "action needed" badge for control-bar toggles whose feature
/// is blocked on a permission.
struct PermissionWarningBadge: View {
    var body: some View {
        Image(systemName: "exclamationmark")
            .font(.system(size: 7, weight: .black))
            .foregroundStyle(.white)
            .frame(width: 12, height: 12)
            .background(Circle().fill(ControlPalette.warning))
            .overlay(Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.35), radius: 1.5, y: 0.5)
            .accessibilityHidden(true)
    }
}

struct CompactIconButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.96 : 1))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.1),
                value: configuration.isPressed
            )
    }
}

/// The larger voice control marks listening with an accent fill and static halo.
struct DemoHeroButton: View {
    let isListening: Bool
    let showsPermissionWarning: Bool
    let help: String
    let action: () -> Void
    var settingsAction: (() -> Void)? = nil

    @State private var isHovering = false
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var diameter: CGFloat { StageActionsMetrics.heroDiameter }

    var body: some View {
        Button(action: action) {
            ZStack {
                halo
                disc
                Image(systemName: "waveform.badge.mic")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(iconStyle)
                    // Optically center the mic glyph (its badge sits lower-right).
                    .offset(x: -0.5, y: -0.5)

                if showsPermissionWarning {
                    PermissionWarningBadge()
                        .frame(width: diameter, height: diameter, alignment: .topTrailing)
                        .offset(x: 1, y: -1)
                }
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
        }
        .buttonStyle(HeroPressStyle())
        .focused($isFocused)
        .onHover { isHovering = $0 }
        .contextMenu {
            if let settingsAction {
                Button("Voice Settings…", action: settingsAction)
            }
        }
        .overlay {
            Circle()
                .strokeBorder(ControlPalette.accent, lineWidth: 2)
                .padding(-3)
                .opacity(isFocused ? 1 : 0)
        }
        .help(help)
        .accessibilityLabel("Demo mode")
        .accessibilityValue(showsPermissionWarning ? "Permission required" : (isListening ? "On" : "Off"))
        .accessibilityAddTraits(isListening ? [.isSelected] : [])
        .accessibilityHint(help)
        .animation(
            reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1),
            value: isListening
        )
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovering)
    }

    // The static halo marks the live state without implying an audio level or
    // creating perpetual motion in a widget that stays on screen for long demos.
    private var halo: some View {
        Circle()
            .fill(ControlPalette.accent)
            .frame(width: diameter, height: diameter)
            .blur(radius: 12)
            .opacity(isListening ? 0.28 : 0)
            .scaleEffect(isListening ? 1.16 : 1)
            .allowsHitTesting(false)
    }

    private var disc: some View {
        Circle()
            .fill(discFill)
            // Top-lit specular sheen: reads as a raised physical control even in
            // the calm off-state, without a heavier fill.
            .overlay(
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.primary.opacity(isListening ? 0.22 : 0.16),
                                Color.primary.opacity(0)
                            ],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                    .blendMode(.plusLighter)
            )
            .overlay(
                Circle().strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.primary.opacity(
                                colorSchemeContrast == .increased ? 0.82 : (isListening ? 0.62 : 0.30)
                            ),
                            Color.primary.opacity(isListening ? 0.26 : 0.12)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            )
            // Layered elevation: a wide ambient shadow plus a tight contact
            // shadow lift the disc off the bar (shadows for depth, border for edge).
            .shadow(color: .black.opacity(0.42), radius: 10, y: 5)
            .shadow(color: .black.opacity(0.26), radius: 2, y: 1)
            .brightness(isHovering ? 0.035 : 0)
    }

    private var discFill: AnyShapeStyle {
        if isListening {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        ControlPalette.accent,
                        ControlPalette.accent.opacity(0.72)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        return AnyShapeStyle(
            LinearGradient(
                colors: [
                    Color(nsColor: .controlBackgroundColor),
                    Color(nsColor: .underPageBackgroundColor)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var iconStyle: Color {
        if isListening { return Color(nsColor: .selectedControlTextColor) }
        return Color.primary.opacity(
            isHovering || colorSchemeContrast == .increased ? 0.94 : 0.72
        )
    }
}

/// Press feedback tuned for the larger hero: the standard 0.96 scale plus a
/// brief dip in opacity, interrupted-friendly and reduce-motion aware.
private struct HeroPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.96 : 1))
            .opacity(configuration.isPressed ? 0.90 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}
