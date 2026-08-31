import SwiftUI

struct PermissionActionButton: View {
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
                        PermissionWarningBadge()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(.top, 2)
                            .padding(.trailing, 2)
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

/// A high-contrast "action needed" badge for control-bar toggles whose feature
/// is blocked on a permission.
struct PermissionWarningBadge: View {
    var body: some View {
        Image(systemName: "exclamationmark")
            .font(.system(size: 8, weight: .black))
            .foregroundStyle(.white)
            .frame(width: 13, height: 13)
            .background(Circle().fill(Color.orange))
            .overlay(Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.35), radius: 1.5, y: 0.5)
            .accessibilityHidden(true)
    }
}

struct CompactIconButtonStyle: ButtonStyle {
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

/// The promoted Demo Mode voice control: a circular hero button that nests into
/// the control bar's center gap and protrudes below it. When listening it takes
/// on an accent fill with a breathing halo so "live" reads at a glance; off, it
/// is a calm elevated disc. Emphasis by size, elevation, and color — never by
/// motion alone (there is always a static color/icon cue).
struct DemoHeroButton: View {
    let isListening: Bool
    let showsPermissionWarning: Bool
    let help: String
    let action: () -> Void

    @State private var isHovering = false
    @State private var isBreathing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var diameter: CGFloat { ControlWindowSizing.heroDiameter }
    private static let accent = Color(red: 0.20, green: 0.72, blue: 1)

    var body: some View {
        Button(action: action) {
            ZStack {
                halo
                disc
                Image(systemName: "waveform.badge.mic")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(iconStyle)
                    // Optically center the mic glyph (its badge sits lower-right).
                    .offset(x: -0.5, y: -0.5)

                if showsPermissionWarning {
                    PermissionWarningBadge()
                        .frame(width: diameter, height: diameter, alignment: .topTrailing)
                }
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
        }
        .buttonStyle(HeroPressStyle())
        .onHover { isHovering = $0 }
        .help(help)
        .accessibilityLabel("Demo mode")
        .accessibilityValue(showsPermissionWarning ? "Permission required" : (isListening ? "On" : "Off"))
        .accessibilityAddTraits(isListening ? [.isSelected] : [])
        .accessibilityHint(help)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isListening)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovering)
        .task(id: isListening) {
            isBreathing = isListening && !reduceMotion
        }
    }

    // Soft outer glow that breathes while listening — a "live mic" cue paired
    // with the accent fill and icon, so removing motion loses no information.
    private var halo: some View {
        Circle()
            .fill(Self.accent)
            .frame(width: diameter, height: diameter)
            .blur(radius: 10)
            .opacity(isListening ? (isBreathing ? 0.55 : 0.32) : 0)
            .scaleEffect(isListening ? (isBreathing ? 1.28 : 1.12) : 1)
            .animation(
                isBreathing
                    ? .easeInOut(duration: 1.6).repeatForever(autoreverses: true)
                    : .easeOut(duration: 0.25),
                value: isBreathing
            )
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
                                Color.white.opacity(isListening ? 0.22 : 0.14),
                                Color.white.opacity(0)
                            ],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                    .blendMode(.plusLighter)
            )
            .overlay(
                Circle().strokeBorder(
                    isListening ? Color.white.opacity(0.55) : Color.white.opacity(0.20),
                    lineWidth: 1
                )
            )
            // Layered elevation: a wide ambient shadow plus a tight contact
            // shadow lift the disc off the bar (shadows for depth, border for edge).
            .shadow(color: .black.opacity(0.32), radius: 8, y: 3)
            .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
            .brightness(isHovering ? 0.05 : 0)
    }

    private var discFill: AnyShapeStyle {
        if isListening {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Self.accent.opacity(0.98),
                        Self.accent.opacity(0.78)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        return AnyShapeStyle(.regularMaterial)
    }

    private var iconStyle: Color {
        if isListening { return .white }
        return isHovering ? .primary : .secondary
    }
}

/// Press feedback tuned for the larger hero: the standard 0.96 scale plus a
/// brief dip in opacity, interrupted-friendly and reduce-motion aware.
private struct HeroPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.96 : 1))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}
