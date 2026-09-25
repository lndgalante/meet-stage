import SwiftUI

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
    @Environment(\.stageActionLayout) private var layout

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: systemImage)
                        .font(.system(size: ControlMetrics.controlBarIconSize, weight: .medium))
                        .offset(x: glyphOffset.width, y: glyphOffset.height)
                        .frame(width: 20)
                    if showsPermissionWarning {
                        PermissionWarningBadge().offset(x: 4, y: -5)
                    }
                }
                if layout == .sidebar {
                    Text(title)
                        .font(.callout)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if isOn == true {
                        Circle().fill(ControlPalette.accent).frame(width: 4, height: 4)
                    }
                }
            }
            .foregroundStyle(
                isActive
                    ? ControlPalette.accent
                    : Color.primary.opacity(isHovering || colorSchemeContrast == .increased ? 1 : 0.8)
            )
            .padding(.horizontal, layout == .sidebar ? 8 : 0)
            .frame(
                width: layout == .floating ? StageActionsMetrics.actionSize : nil,
                height: layout == .floating ? StageActionsMetrics.actionSize : ControlMetrics.controlBarButtonHeight
            )
            .background(
                buttonBackground, in: RoundedRectangle(cornerRadius: ControlMetrics.controlBarActionCornerRadius)
            )
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
        .frame(maxWidth: layout == .floating ? StageActionsMetrics.actionSize : .infinity)
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
