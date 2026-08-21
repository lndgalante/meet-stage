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
                        HStack {
                            Spacer()

                            Image(systemName: "exclamationmark")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(.orange)
                                .frame(width: 8, height: 8)
                        }
                        .padding(.trailing, 4)
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
