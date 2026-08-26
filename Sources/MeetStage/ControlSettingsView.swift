import SwiftUI
import UniformTypeIdentifiers

struct SettingsPopover: View {
    @ObservedObject var manager: CaptureManager
    @State private var selectedTab: SettingsTab = .stage
    @State private var isChoosingLogo = false
    @State private var logoImportError: String?

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
            .frame(width: 432)

            Group {
                switch selectedTab {
                case .stage:
                    stageSettings
                case .spotlight:
                    spotlightSettings
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
        .frame(width: 504)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings")
        .fileImporter(
            isPresented: $isChoosingLogo,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false,
            onCompletion: importLogo
        )
        .alert(
            "Couldn’t Add Logo",
            isPresented: Binding(
                get: { logoImportError != nil },
                set: { if !$0 { logoImportError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                logoImportError = nil
            }
        } message: {
            Text(logoImportError ?? "Choose another image and try again.")
        }
    }

    private var stageSettings: some View {
        VStack(spacing: 12) {
            SettingsPreviewWell {
                StageFrameSettingsPreview(
                    style: manager.stageFrameStyle,
                    padding: manager.stageFramePadding,
                    cornerRadius: manager.stageFrameCornerRadius,
                    blur: manager.stageFrameBlur,
                    shadow: manager.stageFrameShadow,
                    logo: manager.stageLogo
                )
                .frame(width: 112, height: 63)
            }

            SettingsFormRow(title: "Backdrop") {
                Picker(
                    "Stage backdrop",
                    selection: Binding(
                        get: { manager.stageFrameStyle },
                        set: { manager.setStageFrameStyle($0) }
                    )
                ) {
                    ForEach(StageFrameStyle.allCases) { style in
                        Text(style.label)
                            .tag(style)
                    }
                }
                .labelsHidden()
            }

            SettingsFormRow(title: "Logo") {
                HStack(spacing: 8) {
                    Button(manager.stageLogo == nil ? "Choose Image…" : "Replace…") {
                        isChoosingLogo = true
                    }

                    if manager.stageLogo != nil {
                        Button("Remove", role: .destructive) {
                            manager.removeStageLogo()
                        }
                    }
                }
            }
        }
    }

    private func importLogo(_ result: Result<[URL], any Error>) {
        do {
            guard let url = try result.get().first else {
                return
            }
            let isAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if isAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard manager.setStageLogoData(data) else {
                logoImportError = "Choose a valid image smaller than 10 MB."
                return
            }
        } catch {
            logoImportError =
                "The selected image couldn’t be opened. Choose another image and try again."
        }
    }

    private var spotlightSettings: some View {
        VStack(spacing: 12) {
            SettingsPreviewWell {
                SpotlightSettingsPreview(
                    size: manager.spotlightSize,
                    outsideOpacity: manager.spotlightOutsideOpacity
                )
            }

            SettingsFormRow(title: "Spotlight size") {
                Picker(
                    "Spotlight size",
                    selection: Binding(
                        get: { manager.spotlightSize },
                        set: { manager.setSpotlightSize($0) }
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

            SettingsFormRow(title: "Outside opacity") {
                SettingsPercentageSlider(
                    label: "Outside opacity",
                    value: Binding(
                        get: { manager.spotlightOutsideOpacity },
                        set: { manager.setSpotlightOutsideOpacity($0) }
                    ),
                    range: SpotlightAppearance.outsideOpacityRange
                )
            }

        }
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

            SettingsFormRow(title: "Ripple color") {
                PresentationColorPicker(
                    selection: manager.clickHighlightColor,
                    onSelect: { manager.setClickHighlightColor($0) }
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
    case stage
    case spotlight
    case annotations
    case clicks
    case keystrokes

    var id: Self { self }

    var title: String {
        switch self {
        case .stage: "Stage"
        case .spotlight: "Focus"
        case .annotations: "Draw"
        case .clicks: "Clicks"
        case .keystrokes: "Keys"
        }
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
                .frame(width: 112, alignment: .trailing)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 30)
    }
}

private struct SettingsPercentageSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step = 0.05

    var body: some View {
        HStack(spacing: 10) {
            Slider(
                value: $value,
                in: range,
                step: step
            )
            .labelsHidden()
            .accessibilityLabel(label)
            .accessibilityValue(percentageLabel)

            Text(percentageLabel)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }

    private var percentageLabel: String {
        "\(Int((value * 100).rounded()))%"
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
