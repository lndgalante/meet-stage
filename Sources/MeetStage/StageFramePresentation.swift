import SwiftUI

struct StageFrameLayout: Equatable, Sendable {
    let contentFrame: CGRect
    let cornerRadius: CGFloat

    static func resolve(
        viewportSize: CGSize,
        sourceAspectRatio: CGFloat,
        paddingFraction: CGFloat,
        cornerRadius: CGFloat,
        isEnabled: Bool
    ) -> StageFrameLayout {
        guard viewportSize.width > 0, viewportSize.height > 0 else {
            return StageFrameLayout(contentFrame: .zero, cornerRadius: 0)
        }
        guard isEnabled else {
            return StageFrameLayout(
                contentFrame: CGRect(origin: .zero, size: viewportSize),
                cornerRadius: 0
            )
        }

        let safeAspectRatio = StageWindowSizing.normalizedAspectRatio(sourceAspectRatio)
        let inset =
            min(viewportSize.width, viewportSize.height)
            * min(max(paddingFraction, 0), 0.18)
        let availableWidth = max(viewportSize.width - inset * 2, 1)
        let availableHeight = max(viewportSize.height - inset * 2, 1)
        let availableAspectRatio = availableWidth / availableHeight
        let contentSize: CGSize
        if availableAspectRatio > safeAspectRatio {
            contentSize = CGSize(
                width: availableHeight * safeAspectRatio,
                height: availableHeight
            )
        } else {
            contentSize = CGSize(
                width: availableWidth,
                height: availableWidth / safeAspectRatio
            )
        }

        let frame = CGRect(
            x: (viewportSize.width - contentSize.width) / 2,
            y: (viewportSize.height - contentSize.height) / 2,
            width: contentSize.width,
            height: contentSize.height
        )
        return StageFrameLayout(
            contentFrame: frame,
            cornerRadius: min(max(cornerRadius, 0), min(contentSize.width, contentSize.height) / 4)
        )
    }
}

struct StageFrameBackdrop: View {
    let style: StageFrameStyle
    let blur: Double

    var body: some View {
        backdrop
            .scaleEffect(1.08)
            .blur(radius: CGFloat(blur) * 26)
            .overlay(Color.black.opacity(style == .graphite ? 0.08 : 0))
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var backdrop: some View {
        switch style {
        case .none:
            Color.black
        case .midnight:
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.10, blue: 0.22),
                    Color(red: 0.22, green: 0.10, blue: 0.34),
                    Color(red: 0.04, green: 0.07, blue: 0.14)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .ocean:
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.30, blue: 0.36),
                    Color(red: 0.05, green: 0.13, blue: 0.34),
                    Color(red: 0.14, green: 0.06, blue: 0.27)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .sunset:
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.42, blue: 0.34),
                    Color(red: 0.56, green: 0.25, blue: 0.72),
                    Color(red: 0.12, green: 0.14, blue: 0.34)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .graphite:
            RadialGradient(
                colors: [Color(white: 0.28), Color(white: 0.07)],
                center: .topLeading,
                startRadius: 0,
                endRadius: 720
            )
        }
    }
}

struct StageFrameSettingsPreview: View {
    let style: StageFrameStyle
    let padding: Double
    let cornerRadius: Double
    let blur: Double
    let shadow: Double

    var body: some View {
        GeometryReader { geometry in
            let layout = StageFrameLayout.resolve(
                viewportSize: geometry.size,
                sourceAspectRatio: 16 / 9,
                paddingFraction: padding,
                cornerRadius: cornerRadius * 0.32,
                isEnabled: true
            )

            ZStack {
                StageFrameBackdrop(style: style, blur: blur)

                LinearGradient(
                    colors: [Color(white: 0.14), Color(white: 0.04)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle()
                                .fill(.white.opacity(0.38))
                                .frame(width: 4, height: 4)
                        }
                    }
                    .padding(8)
                }
                .frame(
                    width: layout.contentFrame.width,
                    height: layout.contentFrame.height
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: layout.cornerRadius,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: layout.cornerRadius,
                        style: .continuous
                    )
                    .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                }
                .shadow(
                    color: .black.opacity(0.48 * shadow),
                    radius: 18 * shadow,
                    y: 8 * shadow
                )
                .shadow(
                    color: .black.opacity(0.20 * shadow),
                    radius: 4 * shadow,
                    y: 2 * shadow
                )
                .position(x: layout.contentFrame.midX, y: layout.contentFrame.midY)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
