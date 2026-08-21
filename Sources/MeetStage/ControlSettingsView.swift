import SwiftUI

struct SettingsPopover: View {
    @ObservedObject var manager: CaptureManager
    @State private var selectedTab: SettingsTab = .annotations

    var body: some View {
        VStack(spacing: 16) {
            Picker(
                "Settings section",
                selection: $selectedTab
            ) {
                ForEach(SettingsTab.allCases) { tab in
                    Text(tab.title)
                        .tag(tab)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 330)

            Group {
                switch selectedTab {
                case .annotations:
                    annotationSettings
                case .clicks:
                    clickSettings
                case .keystrokes:
                    keystrokeSettings
                }
            }
        }
        .padding(18)
        .frame(width: 420)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings")
    }

    private var annotationSettings: some View {
        VStack(spacing: 12) {
            SettingsPreviewWell {
                ZStack {
                    AnnotationPreviewStroke()
                        .stroke(
                            Color.black.opacity(0.42),
                            style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
                        )
                    AnnotationPreviewStroke()
                        .stroke(
                            manager.annotationColor.color,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                        )
                }
                .frame(width: 124, height: 34)
            }

            SettingsFormRow(title: "Pen color") {
                PresentationColorPicker(
                    selection: manager.annotationColor,
                    onSelect: { manager.setAnnotationColor($0) }
                )
            }

            SettingsFormRow(title: "Fade after") {
                Picker(
                    "Fade after",
                    selection: Binding(
                        get: { manager.annotationLifetimeSeconds },
                        set: { manager.setAnnotationLifetimeSeconds($0) }
                    )
                ) {
                    ForEach(AnnotationTiming.supportedLifetimeSeconds, id: \.self) { seconds in
                        Text("\(seconds)s")
                            .tag(seconds)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

        }
    }

    private var clickSettings: some View {
        VStack(spacing: 12) {
            SettingsPreviewWell(hidesContentFromAccessibility: false) {
                ClickRipplePreview(
                    color: manager.clickHighlightColor,
                    size: manager.clickHighlightSize
                )
            }

            SettingsFormRow(title: "Ripple size") {
                Picker(
                    "Ripple size",
                    selection: Binding(
                        get: { manager.clickHighlightSize },
                        set: { manager.setClickHighlightSize($0) }
                    )
                ) {
                    ForEach(PresentationSize.allCases) { size in
                        Text(size.label)
                            .tag(size)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            SettingsFormRow(title: "Ripple color") {
                PresentationColorPicker(
                    selection: manager.clickHighlightColor,
                    onSelect: { manager.setClickHighlightColor($0) }
                )
            }

        }
    }

    private var keystrokeSettings: some View {
        VStack(spacing: 12) {
            SettingsPreviewWell {
                KeystrokeBadge(
                    label: "⌘ K",
                    size: manager.keystrokeHighlightSize,
                    appearance: manager.keystrokeAppearance
                )
            }

            SettingsFormRow(title: "Key size") {
                Picker(
                    "Key size",
                    selection: Binding(
                        get: { manager.keystrokeHighlightSize },
                        set: { manager.setKeystrokeHighlightSize($0) }
                    )
                ) {
                    ForEach(PresentationSize.allCases) { size in
                        Text(size.label)
                            .tag(size)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            SettingsFormRow(title: "Appearance") {
                Picker(
                    "Appearance",
                    selection: Binding(
                        get: { manager.keystrokeAppearance },
                        set: { manager.setKeystrokeAppearance($0) }
                    )
                ) {
                    ForEach(KeystrokeAppearance.allCases) { appearance in
                        Text(appearance.label)
                            .tag(appearance)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

        }
    }
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case annotations
    case clicks
    case keystrokes

    var id: Self { self }

    var title: String {
        rawValue.capitalized
    }
}

private struct SettingsFormRow<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 14) {
            Text(title)
                .font(.callout.weight(.medium))
                .frame(width: 92, alignment: .trailing)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 30)
    }
}

private struct SettingsPreviewWell<Content: View>: View {
    let hidesContentFromAccessibility: Bool
    let content: Content

    init(
        hidesContentFromAccessibility: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.hidesContentFromAccessibility = hidesContentFromAccessibility
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
            .frame(height: 72)
            .accessibilityHidden(hidesContentFromAccessibility)
    }
}

private struct PresentationColorPicker: View {
    let selection: PresentationColor
    let onSelect: (PresentationColor) -> Void

    var body: some View {
        HStack(spacing: 7) {
            ForEach(PresentationColor.allCases) { color in
                Button {
                    onSelect(color)
                } label: {
                    ZStack {
                        if selection == color {
                            Circle()
                                .strokeBorder(Color.primary.opacity(0.88), lineWidth: 2)
                                .frame(width: 28, height: 28)
                        }

                        Circle()
                            .fill(color.color)
                            .frame(width: 22, height: 22)
                            .overlay {
                                Circle()
                                    .strokeBorder(Color.black.opacity(0.16), lineWidth: 1)
                            }

                        if selection == color {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(color.contrastingColor)
                        }
                    }
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
                }
                .buttonStyle(ColorSwatchButtonStyle())
                .help(color.label)
                .accessibilityLabel(color.label)
                .accessibilityValue(selection == color ? "Selected" : "Not selected")
                .accessibilityAddTraits(selection == color ? .isSelected : [])
            }
        }
    }
}

private struct ColorSwatchButtonStyle: ButtonStyle {
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

private struct ClickRipplePreview: View {
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

private struct AnnotationPreviewStroke: Shape {
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
