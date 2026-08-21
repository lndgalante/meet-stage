import SwiftUI

/// Visualizes spotlight appearance without requiring a live capture source.
struct SpotlightSettingsPreview: View {
    let size: PresentationSize
    let outsideOpacity: Double

    var body: some View {
        GeometryReader { geometry in
            let diameter = previewDiameter(in: geometry.size)
            let aperture = CGRect(
                x: geometry.size.width * 0.87 - diameter / 2,
                y: geometry.size.height / 2 - diameter / 2,
                width: diameter,
                height: diameter
            )

            ZStack {
                previewContent

                SpotlightEffectLayer(
                    aperture: aperture,
                    outsideOpacity: outsideOpacity
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var previewContent: some View {
        HStack(spacing: 14) {
            VStack(spacing: 7) {
                Circle()
                    .fill(Color.accentColor.opacity(0.78))
                    .frame(width: 17, height: 17)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.primary.opacity(0.16))
                    .frame(width: 16, height: 5)
            }

            VStack(alignment: .leading, spacing: 7) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.primary.opacity(0.28))
                    .frame(width: 76, height: 7)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.primary.opacity(0.13))
                    .frame(width: 118, height: 6)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.primary.opacity(0.13))
                    .frame(width: 94, height: 6)
            }

            Spacer(minLength: 6)

            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor.opacity(0.82))
                .frame(width: 64, height: 28)
        }
        .padding(.horizontal, 22)
    }

    private func previewDiameter(in viewportSize: CGSize) -> CGFloat {
        let scale: CGFloat
        switch size {
        case .small:
            scale = 0.48
        case .medium:
            scale = 0.66
        case .large:
            scale = 0.84
        }
        return viewportSize.height * scale
    }
}

/// Gives each presentation preview consistent framing and accessibility.
struct SettingsPreviewWell<Content: View>: View {
    let hidesContentFromAccessibility: Bool
    let height: CGFloat
    let content: Content

    init(
        hidesContentFromAccessibility: Bool = true,
        height: CGFloat = 72,
        @ViewBuilder content: () -> Content
    ) {
        self.hidesContentFromAccessibility = hidesContentFromAccessibility
        self.height = height
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Color.primary.opacity(0.045),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .frame(height: height)
            .accessibilityHidden(hidesContentFromAccessibility)
    }
}

/// Replays the click animation while keeping playback under user control.
struct ClickRipplePreview: View {
    let color: PresentationColor
    let size: PresentationSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulseGeneration = 0
    @State private var isPlaying = true

    var body: some View {
        let metrics = ClickRippleMetrics(size: size)

        ZStack {
            Group {
                if reduceMotion {
                    staticPreview(
                        metrics: metrics,
                        diameter: metrics.reducedMotionDiameter,
                        lineWidth: 2
                    )
                } else if isPlaying {
                    ClickRippleGlyph(
                        presentation: ClickPresentation(
                            location: NormalizedWindowPoint(x: 0.5, y: 0.5),
                            color: color,
                            size: size
                        ),
                        reducesMotion: false
                    )
                    .id(previewIdentity)
                } else {
                    staticPreview(
                        metrics: metrics,
                        diameter: metrics.initialDiameter,
                        lineWidth: 3
                    )
                }
            }
            .accessibilityHidden(true)

            if !reduceMotion {
                playbackButton
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(7)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: playbackConfiguration) {
            guard isPlaying, !reduceMotion else { return }

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(800))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                pulseGeneration &+= 1
            }
        }
    }

    private var previewConfiguration: String {
        "\(color.rawValue)-\(size.rawValue)-\(reduceMotion)"
    }

    private var previewIdentity: String {
        "\(previewConfiguration)-\(pulseGeneration)"
    }

    private var playbackConfiguration: String {
        "\(previewConfiguration)-\(isPlaying)"
    }

    private var playbackButton: some View {
        Button {
            isPlaying.toggle()
            if isPlaying {
                pulseGeneration &+= 1
            }
        } label: {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 8, weight: .bold))
                .symbolRenderingMode(.monochrome)
                .offset(x: isPlaying ? 0 : 0.5)
                .frame(width: 22, height: 22)
                .background(Color.primary.opacity(0.09), in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.13), lineWidth: 1)
                }
                .contentShape(Circle())
        }
        .buttonStyle(CompactIconButtonStyle())
        .help(isPlaying ? "Pause ripple preview" : "Play ripple preview")
        .accessibilityLabel(isPlaying ? "Pause ripple preview" : "Play ripple preview")
        .accessibilityValue(isPlaying ? "Playing" : "Paused")
        .accessibilityHint("The ripple preview repeats every 800 milliseconds")
    }

    private func staticPreview(
        metrics: ClickRippleMetrics,
        diameter: CGFloat,
        lineWidth: CGFloat
    ) -> some View {
        ZStack {
            Circle()
                .stroke(color.color, lineWidth: lineWidth)
                .frame(width: diameter, height: diameter)
                .opacity(0.82)

            Circle()
                .fill(color.color)
                .frame(width: metrics.dotDiameter, height: metrics.dotDiameter)
        }
        .frame(width: metrics.canvasDiameter, height: metrics.canvasDiameter)
        .shadow(color: .black.opacity(0.26), radius: 2, y: 1)
    }
}

struct AnnotationPreviewStroke: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 2, y: rect.midY + 8))
        path.addCurve(
            to: CGPoint(x: rect.maxX - 2, y: rect.midY - 6),
            control1: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.minY - 2),
            control2: CGPoint(x: rect.minX + rect.width * 0.64, y: rect.maxY + 3)
        )
        return path
    }
}
