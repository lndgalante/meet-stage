import SwiftUI

struct PresenterPanelBackground: View {
    let cornerRadius: CGFloat
    var drawsShadow = true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                reduceTransparency
                    ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
                    : AnyShapeStyle(.regularMaterial)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [.black.opacity(0.06), .black.opacity(0.20)]
                                : [.white.opacity(0.12), .black.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.primary.opacity(contrast == .increased ? 0.55 : 0.28),
                                Color.primary.opacity(contrast == .increased ? 0.32 : 0.12)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(drawsShadow ? 0.40 : 0), radius: 18, y: 8)
            .shadow(color: .black.opacity(drawsShadow ? 0.24 : 0), radius: 3, y: 1)
    }
}
