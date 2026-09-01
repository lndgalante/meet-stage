import AppKit
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
        guard viewportSize.width.isFinite,
            viewportSize.height.isFinite,
            viewportSize.width > 0,
            viewportSize.height > 0
        else {
            return StageFrameLayout(contentFrame: .zero, cornerRadius: 0)
        }
        guard isEnabled else {
            return StageFrameLayout(
                contentFrame: CGRect(origin: .zero, size: viewportSize),
                cornerRadius: 0
            )
        }

        let safeAspectRatio = StageWindowSizing.normalizedAspectRatio(sourceAspectRatio)
        let safePaddingFraction =
            paddingFraction.isFinite
            ? min(max(paddingFraction, 0), 0.18)
            : 0
        let safeCornerRadius = cornerRadius.isFinite ? max(cornerRadius, 0) : 0
        let inset =
            min(viewportSize.width, viewportSize.height)
            * safePaddingFraction
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
            cornerRadius: min(safeCornerRadius, min(contentSize.width, contentSize.height) / 4)
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
    let logo: NSImage?

    var body: some View {
        GeometryReader { geometry in
            let effectivePadding =
                logo == nil
                ? padding
                : max(padding, StageLogoAppearance.minimumStagePadding)
            let layout = StageFrameLayout.resolve(
                viewportSize: geometry.size,
                sourceAspectRatio: 16 / 9,
                paddingFraction: effectivePadding,
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

                if let logo {
                    StageLogoOverlay(
                        image: logo,
                        contentFrame: layout.contentFrame
                    )
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct StageLogoLayout: Equatable, Sendable {
    let frame: CGRect

    static func resolve(
        viewportSize: CGSize,
        contentFrame: CGRect,
        imageSize: CGSize
    ) -> StageLogoLayout? {
        guard
            viewportSize.width.isFinite,
            viewportSize.height.isFinite,
            viewportSize.width > 0,
            viewportSize.height > 0,
            imageSize.width.isFinite,
            imageSize.height.isFinite,
            imageSize.width > 0,
            imageSize.height > 0
        else { return nil }

        let edgeInset = min(max(min(viewportSize.width, viewportSize.height) * 0.012, 1), 16)
        let maximumWidth = min(viewportSize.width * 0.18, 220)
        let maximumHeight = min(viewportSize.height * 0.14, 96)

        let bottomCandidate = fittedSize(
            imageSize,
            inside: CGSize(
                width: maximumWidth,
                height: max(viewportSize.height - contentFrame.maxY - edgeInset * 2, 0)
            )
        )
        let trailingCandidate = fittedSize(
            imageSize,
            inside: CGSize(
                width: max(viewportSize.width - contentFrame.maxX - edgeInset * 2, 0),
                height: maximumHeight
            )
        )
        let logoSize =
            bottomCandidate.width * bottomCandidate.height
                >= trailingCandidate.width * trailingCandidate.height
            ? bottomCandidate
            : trailingCandidate
        guard logoSize.width > 0, logoSize.height > 0 else { return nil }

        let frame = CGRect(
            x: viewportSize.width - edgeInset - logoSize.width,
            y: viewportSize.height - edgeInset - logoSize.height,
            width: logoSize.width,
            height: logoSize.height
        )
        guard !frame.intersects(contentFrame) else { return nil }

        return StageLogoLayout(frame: frame)
    }

    private static func fittedSize(_ size: CGSize, inside bounds: CGSize) -> CGSize {
        guard bounds.width > 0, bounds.height > 0 else { return .zero }

        let scale = min(bounds.width / size.width, bounds.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}

enum StageLogoVisibilityPolicy {
    static func shouldShow(
        isLive: Bool,
        isAutoPresentationEnabled: Bool,
        hasLogo: Bool
    ) -> Bool {
        isLive && isAutoPresentationEnabled && hasLogo
    }
}

struct StageLogoOverlay: View {
    let image: NSImage
    let contentFrame: CGRect

    var body: some View {
        GeometryReader { geometry in
            if let layout = StageLogoLayout.resolve(
                viewportSize: geometry.size,
                contentFrame: contentFrame,
                imageSize: image.size
            ) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: layout.frame.width, height: layout.frame.height)
                    .position(x: layout.frame.midX, y: layout.frame.midY)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
