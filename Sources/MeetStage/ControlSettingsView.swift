import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum SettingsTab: String, CaseIterable, Identifiable {
    static let storageKey = "MeetStage.settings.selectedTab.v1"

    case general
    case stage
    case spotlight
    case annotations
    case clicks
    case keystrokes
    case demos

    var id: Self { self }

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .stage: String(localized: "Auto Polish")
        case .spotlight: String(localized: "Spotlight")
        case .annotations: String(localized: "Annotations")
        case .clicks: String(localized: "Click Highlights")
        case .keystrokes: String(localized: "Keystrokes")
        case .demos: String(localized: "Demos")
        }
    }

    /// Panes that configure a stage effect with an On/Off switch.
    var isEffect: Bool { self != .general && self != .demos }
}

struct BetterMeetsSettingsView: View {
    @ObservedObject var manager: CaptureManager
    @Environment(\.legibilityWeight) private var legibilityWeight
    @AppStorage(SettingsTab.storageKey) private var selectedTabRawValue = SettingsTab.general.rawValue
    @State private var isChoosingLogo = false
    @State private var isLogoDropTargeted = false
    @State private var logoImportError: String?
    var body: some View {
        HStack(spacing: 0) {
            List(SettingsTab.allCases, selection: selectedTabBinding) { tab in
                Text(tab.title)
                    .padding(.vertical, 5)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .frame(width: 165)
            .accessibilityLabel("Settings sections")
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(selectedTab.title)
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    if selectedTab.isEffect {
                        effectState
                    }
                    Group {
                        switch selectedTab {
                        case .general: generalSettings
                        case .stage: stageSettings
                        case .spotlight: spotlightSettings
                        case .annotations: annotationSettings
                        case .clicks: clickSettings
                        case .keystrokes: keystrokeSettings
                        case .demos: DemoSettingsView(demo: manager.demo)
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(minWidth: 700, minHeight: 440)
        .fontWeight(legibilityWeight == .bold ? .bold : nil)
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

    private var selectedTab: SettingsTab {
        SettingsTab(rawValue: selectedTabRawValue) ?? .general
    }

    private var selectedTabBinding: Binding<SettingsTab?> {
        Binding(
            get: { selectedTab },
            set: { if let tab = $0 { selectedTabRawValue = tab.rawValue } }
        )
    }

    private var effectState: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(effectIsEnabled ? "Enabled" : "Turn on to apply these settings")
                    .font(.callout.weight(.medium))
                Text(effectIsEnabled
                     ? (manager.isLive ? "Enabled for this stage" : "Ready for the next source")
                     : "The preview below shows how the effect will look")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Toggle(selectedTab.title, isOn: Binding(
                get: { effectIsEnabled },
                set: { _ in toggleEffect() }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
    }

    private var effectIsEnabled: Bool {
        switch selectedTab {
        case .general, .demos: false
        case .stage: manager.autoPresentationEnabled
        case .spotlight: manager.spotlightEnabled
        case .annotations: manager.annotationsEnabled
        case .clicks: manager.highlightsMouseClicks
        case .keystrokes: manager.highlightsKeystrokes
        }
    }

    private func toggleEffect() {
        switch selectedTab {
        case .general, .demos: break
        case .stage: manager.toggleAutoPresentation(focusSource: false)
        case .spotlight: manager.toggleSpotlight(focusSource: false)
        case .annotations: manager.toggleAnnotations(focusSource: false)
        case .clicks: manager.toggleMouseClickHighlighting()
        case .keystrokes: manager.toggleKeystrokeHighlighting()
        }
    }

    private var generalSettings: some View {
        VStack(spacing: 12) {
            SettingsPreviewWell {
                VStack(spacing: 5) {
                    KeystrokeBadge(
                        label: "\(manager.preferredShortcutModifier.symbolPrefix) 1",
                        size: .medium,
                        appearance: .dark
                    )
                    Text(
                        manager.globalShortcutsEnabled
                            ? "Select source windows with keys 1–9" : "Global shortcuts are off"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            SettingsFormRow(title: "Global shortcuts") {
                Toggle(
                    "Select windows from anywhere",
                    isOn: Binding(
                        get: { manager.globalShortcutsEnabled },
                        set: { manager.setGlobalShortcutsEnabled($0) }
                    )
                )
                .toggleStyle(.checkbox)
            }

            SettingsFormRow(title: "Modifier keys") {
                Picker(
                    "Modifier keys",
                    selection: Binding(
                        get: { manager.preferredShortcutModifier },
                        set: { manager.setGlobalShortcutModifier($0) }
                    )
                ) {
                    ForEach(GlobalShortcutModifier.allCases.filter { $0 != .disabled }) { modifier in
                        Text(modifier.symbolPrefix)
                            .help(modifier.label)
                            .accessibilityLabel(modifier.label)
                            .tag(modifier)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .disabled(!manager.globalShortcutsEnabled)
            }
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
            .overlay {
                if isLogoDropTargeted {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                return importLogoURL(url)
            } isTargeted: { isTargeted in
                isLogoDropTargeted = isTargeted
            }
            .help("Drop an image here to use it as the Stage logo")

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
        switch result {
        case let .success(urls):
            guard let url = urls.first else { return }
            _ = importLogoURL(url)
        case .failure:
            logoImportError =
                "The selected image couldn’t be opened. Choose another image and try again."
        }
    }

    @discardableResult
    private func importLogoURL(_ url: URL) -> Bool {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard manager.setStageLogoData(data) else {
                logoImportError = "Choose a valid image smaller than 10 MB."
                return false
            }
            return true
        } catch {
            logoImportError =
                "The selected image couldn’t be opened. Choose another image and try again."
            return false
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

struct SettingsFormRow<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(title)
                .font(.callout)
                .frame(width: 105, alignment: .trailing)

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

    @State private var hoveredColor: PresentationColor?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

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
                    .background(
                        Color.primary.opacity(hoverOpacity(for: color)),
                        in: Circle()
                    )
                    .contentShape(Circle())
                }
                .buttonStyle(ColorSwatchButtonStyle())
                .onHover { isHovering in
                    hoveredColor = isHovering ? color : nil
                }
                .help(color.label)
                .accessibilityLabel(color.label)
                .accessibilityValue(selection == color ? "Selected" : "Not selected")
                .accessibilityAddTraits(selection == color ? .isSelected : [])
            }
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.12),
            value: hoveredColor
        )
    }

    private func hoverOpacity(for color: PresentationColor) -> Double {
        guard hoveredColor == color else { return 0 }
        return colorSchemeContrast == .increased ? 0.16 : 0.08
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
