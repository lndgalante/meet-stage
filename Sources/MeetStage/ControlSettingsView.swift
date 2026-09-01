import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum SettingsTab: String, CaseIterable, Identifiable {
    static let storageKey = "MeetStage.settings.selectedTab.v1"

    case general
    case stage
    case spotlight
    case annotations
    case demo
    case clicks
    case keystrokes

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .demo: "Demo"
        case .stage: "Stage"
        case .spotlight: "Focus"
        case .annotations: "Draw"
        case .clicks: "Clicks"
        case .keystrokes: "Keys"
        }
    }
}

struct BetterMeetsSettingsView: View {
    @ObservedObject var manager: CaptureManager
    @Environment(\.legibilityWeight) private var legibilityWeight
    @AppStorage(SettingsTab.storageKey) private var selectedTabRawValue = SettingsTab.general.rawValue
    @State private var isChoosingLogo = false
    @State private var isLogoDropTargeted = false
    @State private var logoImportError: String?
    @State private var brainKeyDraft = ""
    @State private var isConfirmingKeyRemoval = false
    /// Popover content is capped to this height and scrolls beyond it, so a tall
    /// tab (Demo) never overflows the screen above the button and overlaps rows.
    private static let maxTabContentHeight: CGFloat = 560
    // Start at the cap so the popover opens correctly sized for a tall tab, then
    // settles to the exact measured height (avoids a first-frame zero-height pop).
    @State private var tabContentHeight: CGFloat = maxTabContentHeight

    var body: some View {
        VStack(spacing: 16) {
            Picker(
                "Settings section",
                selection: selectedTabBinding
            ) {
                ForEach(SettingsTab.allCases) { tab in
                    Text(tab.title)
                        .tag(tab)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 500)

            // Some tabs (Demo especially) are taller than the popover can be on
            // shorter screens; scroll past the cap rather than clip or overlap
            // the last rows. Below the cap the popover fits the content exactly.
            ScrollView(.vertical, showsIndicators: false) {
                Group {
                    switch selectedTab {
                    case .general:
                        generalSettings
                    case .demo:
                        demoSettings
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
                // Keep the content clear of the scroll edges, and measure its
                // natural height so the popover fits it exactly until the cap.
                .padding(.horizontal, 2)
                .padding(.bottom, 2)
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.height
                } action: {
                    tabContentHeight = $0
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(tabContentHeight, Self.maxTabContentHeight))
        }
        .padding(18)
        .frame(width: 568)
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
        .alert(
            "Remove \(manager.demoBrainProvider.vendor) API Key?",
            isPresented: $isConfirmingKeyRemoval
        ) {
            Button("Remove Key", role: .destructive) {
                manager.setDemoBrainKey("")
                brainKeyDraft = ""
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The key will be deleted from your Keychain and cloud understanding will turn off.")
        }
        .onChange(of: manager.demoBrainProvider) { _, _ in
            brainKeyDraft = ""
        }
    }

    private var selectedTab: SettingsTab {
        SettingsTab(rawValue: selectedTabRawValue) ?? .general
    }

    private var selectedTabBinding: Binding<SettingsTab> {
        Binding(
            get: { selectedTab },
            set: { selectedTabRawValue = $0.rawValue }
        )
    }

    private var generalSettings: some View {
        VStack(spacing: 12) {
            SettingsPreviewWell {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 42, height: 42)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("BetterMeets")
                            .font(.headline)
                        Text("Global source switching")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            SettingsFormRow(title: "Global shortcuts") {
                Picker(
                    "Global shortcuts",
                    selection: Binding(
                        get: { manager.globalShortcutModifier },
                        set: { manager.setGlobalShortcutModifier($0) }
                    )
                ) {
                    ForEach(GlobalShortcutModifier.allCases) { modifier in
                        Text(modifier.label)
                            .tag(modifier)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 240)
            }

            DemoSettingsNote(
                symbol: "keyboard",
                text:
                    manager.globalShortcutModifier == .disabled
                    ? "Global shortcuts are off. Source slots and pins remain available in BetterMeets."
                    : "Source slots use \(manager.globalShortcutModifier.symbolPrefix)1 through \(manager.globalShortcutModifier.symbolPrefix)9. Choose Off if another app needs those shortcuts."
            )
        }
    }

    private var demoSettings: some View {
        VStack(spacing: 12) {
            SettingsPreviewWell {
                DemoHighlightPreview(color: manager.demoHighlightColor)
            }

            SettingsFormRow(title: "Voice actions") {
                Picker(
                    "Voice actions",
                    selection: Binding(
                        get: { manager.demoVoiceActions },
                        set: { manager.setDemoVoiceActions($0) }
                    )
                ) {
                    ForEach(DemoVoiceActions.allCases) { option in
                        Text(option.label)
                            .tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            SettingsFormRow(title: "Understanding") {
                Toggle(
                    "Conversational understanding",
                    isOn: Binding(
                        get: { manager.demoSmartUnderstanding },
                        set: { manager.setDemoSmartUnderstanding($0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(!manager.isDemoSmartUnderstandingAvailable)
            }

            if manager.demoSmartUnderstanding, !manager.isDemoConversationalTierAvailable {
                DemoSettingsNote(
                    text:
                        "Matches controls you describe, on device. Turn on Apple Intelligence "
                        + "for conversational commands like “open it” that refer back."
                )
            }

            SettingsFormRow(title: "Highlight color") {
                PresentationColorPicker(
                    selection: manager.demoHighlightColor,
                    onSelect: { manager.setDemoHighlightColor($0) }
                )
            }

            SettingsFormRow(title: "Zoom size") {
                Picker(
                    "Zoom size",
                    selection: Binding(
                        get: { manager.demoZoomSize },
                        set: { manager.setDemoZoomSize($0) }
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

            if manager.demoModeNeedsClickAccessibility {
                DemoSettingsNote(
                    text:
                        "Allow BetterMeets under Accessibility to open controls. "
                        + "Until then, controls are only highlighted.",
                    actionTitle: "Open Settings",
                    action: { manager.openAccessibilitySettings() }
                )
            }

            SettingsFormRow(title: "Model") {
                Picker(
                    "Model",
                    selection: Binding(
                        get: { manager.demoBrainProvider },
                        set: { manager.setDemoBrainProvider($0) }
                    )
                ) {
                    ForEach(DemoBrainProvider.allCases) { provider in
                        Text(provider.label)
                            .tag(provider)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            SettingsFormRow(title: "Conversation AI") {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        SecureField(
                            "\(manager.demoBrainProvider.vendor) API key",
                            text: $brainKeyDraft
                        )
                        .textFieldStyle(.roundedBorder)
                        Button("Save") {
                            manager.setDemoBrainKey(brainKeyDraft)
                            brainKeyDraft = ""
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(
                            brainKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )

                        if manager.hasDemoBrainKey {
                            Button("Remove…", role: .destructive) {
                                isConfirmingKeyRemoval = true
                            }
                        }
                    }
                    Text(
                        manager.hasDemoBrainKey
                            ? "\(manager.demoBrainProvider.vendor) key saved to your Keychain. Enables natural commands like “now open it”."
                            : "Add a \(manager.demoBrainProvider.vendor) key for natural commands like “now open it” (\(manager.demoBrainProvider.label))."
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            SettingsFormRow(title: "Cloud understanding") {
                VStack(alignment: .leading, spacing: 5) {
                    Toggle(
                        "Send screenshots to \(manager.demoBrainProvider.vendor)",
                        isOn: Binding(
                            get: { manager.demoCloudConsented },
                            set: { manager.setDemoCloudConsented($0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!manager.hasDemoBrainKey)

                    Text(
                        "When on, each command sends a screenshot of the shared window and "
                            + "your spoken words to \(manager.demoBrainProvider.vendor) to resolve the "
                            + "target. Turn off to keep everything on device (understanding is more limited)."
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
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

/// An inline advisory note inside a settings tab, with an optional action.
private struct DemoSettingsNote: View {
    var symbol = "exclamationmark.triangle.fill"
    let text: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(.orange)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderless)
                    .font(.caption.weight(.semibold))
                    .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

/// Static preview of the Demo Mode highlight over a sample control.
private struct DemoHighlightPreview: View {
    let color: PresentationColor

    var body: some View {
        Text("Discover")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.quaternary, in: Capsule())
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(color.color, lineWidth: 3)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(color.color.opacity(0.12))
                    )
                    .padding(-7)
                    .shadow(color: color.color.opacity(0.5), radius: 6)
            }
            .accessibilityHidden(true)
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
