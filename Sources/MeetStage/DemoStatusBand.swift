import AppKit
import SwiftUI

/// The top of the panel's detail: what the demo is doing, why, and the one thing to do about it.
struct DemoStatusBand: View {
    let content: DemoPanelContent
    let diagnosticDetails: String?
    let perform: (PanelActionID) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    BandGlyph(glyph: content.glyph)
                    headline
                }
                .frame(height: 20)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(statusLabel)
                if let subline = content.subline {
                    SublineRow(subline: subline, details: content.showsCopyDetails ? diagnosticDetails : nil)
                        .frame(height: 16)
                }
            }
            .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
            if !content.transport.isEmpty || content.primary != nil {
                BandActions(
                    transport: content.transport, secondaries: content.secondaries, primary: content.primary,
                    perform: perform
                )
                .layoutPriority(1)
            }
        }
        .frame(height: content.subline == nil ? 20 : 38)
    }

    private var statusLabel: String {
        let headline = content.headline.accessibilityText
        guard let subline = content.subline else { return headline }
        return headline.hasSuffix(".") ? "\(headline) \(subline.text)" : "\(headline). \(subline.text)"
    }

    @ViewBuilder private var headline: some View {
        switch content.headline {
        case .text(let text):
            Text(text)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.tail)
        case .pipeline(let stage):
            PipelineHeadline(stage: stage)
        }
    }
}

/// The state's glyph: the only place the band uses colour.
private struct BandGlyph: View {
    let glyph: DemoPanelContent.Glyph

    var body: some View {
        Group {
            switch glyph {
            case .spinner:
                ProgressView().controlSize(.small)
            case .symbol(let name, let tint):
                Image(systemName: name)
                    .font(.title3)
                    .foregroundStyle(tint.style)
            }
        }
        .frame(width: 20, height: 20)
    }
}

extension DemoPanelContent.Tint {
    var style: AnyShapeStyle {
        switch self {
        case .accent: AnyShapeStyle(Color.accentColor)
        case .green: AnyShapeStyle(Color.green)
        case .orange: AnyShapeStyle(Color.orange)
        case .secondary: AnyShapeStyle(.secondary)
        }
    }
}

/// Build › Test › Ready, with stages done, current and still to come.
private struct PipelineHeadline: View {
    let stage: DemoPanelContent.PipelineStage

    var body: some View {
        HStack(spacing: 6) {
            part("Build", index: 1)
            separator
            part("Test", index: 2)
            separator
            part("Ready", index: 3)
        }
        .font(.title3)
        .lineLimit(1)
    }

    private var separator: some View {
        Text("›").foregroundStyle(.tertiary)
    }

    @ViewBuilder private func part(_ title: String, index: Int) -> some View {
        if index < stage.rawValue {
            HStack(spacing: 3) {
                Image(systemName: "checkmark").font(.callout.weight(.semibold))
                Text(title)
            }
            .foregroundStyle(.secondary)
        } else if index == stage.rawValue {
            Text(title).fontWeight(.semibold).foregroundStyle(.primary)
        } else {
            Text(title).foregroundStyle(.tertiary)
        }
    }
}

/// The band's second line. Facts drop parts to fit; a cut reason or notice gets
/// a More link that opens it in full.
private struct SublineRow: View {
    let subline: DemoPanelContent.Subline
    let details: String?

    var body: some View {
        Group {
            switch subline.kind {
            case .facts, .next:
                ViewThatFits(in: .horizontal) {
                    ForEach([subline.text] + subline.shorter, id: \.self) { text in
                        Text(text).fixedSize()
                    }
                    Text(subline.shorter.last ?? subline.text).truncationMode(.tail)
                }
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            case .reason, .notice:
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        noticeGlyph
                        message.fixedSize()
                        if let details { CopyDetailsButton(details: details) }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        noticeGlyph
                        message.truncationMode(.tail).layoutPriority(-1)
                        MoreLink(text: subline.text, details: details)
                        if let details { CopyDetailsButton(details: details, iconOnly: true) }
                    }
                }
            }
        }
        .font(.callout)
        .lineLimit(1)
        .help(subline.help ?? subline.text)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var message: some View {
        Text(subline.text)
            .foregroundStyle(.primary)
            .textSelection(.enabled)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var noticeGlyph: some View {
        if subline.kind == .notice {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
        }
    }
}

/// Opens a cut reason in full, selectable, with Copy Details when there are any.
struct MoreLink: View {
    let text: String
    var details: String?
    @State private var isShowing = false

    var body: some View {
        Button("More") { isShowing = true }
            .buttonStyle(.link)
            .font(.callout)
            .fixedSize()
            .accessibilityLabel("Show the full message")
            .popover(isPresented: $isShowing, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(text)
                        .font(.callout)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    if let details { CopyDetailsButton(details: details) }
                }
                .padding(14)
                .frame(width: 320, alignment: .leading)
            }
    }
}

/// Copies an API failure's details for a bug report, then says so for a moment.
struct CopyDetailsButton: View {
    let details: String
    var iconOnly = false
    @State private var copied = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let button = Button(action: copy) {
            Label(copied ? "Copied" : "Copy Details", systemImage: copied ? "checkmark" : "doc.on.doc")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .fixedSize()
        .help("Copy the API error, model and request ID")
        if iconOnly {
            button.labelStyle(.iconOnly)
        } else {
            button
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(details, forType: .string)
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { copied = false }
        }
    }
}

/// The band's trailing cluster: the transport, the secondaries and the one
/// primary. Narrow widths fold the secondaries into a split-button primary.
private struct BandActions: View {
    let transport: [PanelAction]
    let secondaries: [PanelAction]
    let primary: PanelAction?
    let perform: (PanelActionID) -> Void

    private enum Rung: Hashable { case full, split, splitShort }

    /// Widest first; the transport and the primary are never dropped.
    private var rungs: [Rung] {
        guard let primary, !secondaries.isEmpty else { return [.full] }
        return primary.shortTitle == nil ? [.full, .split] : [.full, .split, .splitShort]
    }

    /// The bezel of a large button adds about 12 pt a side to its label.
    private static let primaryMinimumLabelWidth: CGFloat = 112 - 24

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(rungs, id: \.self) { rung in
                cluster(rung).fixedSize()
            }
        }
    }

    private func cluster(_ rung: Rung) -> some View {
        HStack(spacing: 12) {
            if !transport.isEmpty { transportGroup }
            if rung == .full, !secondaries.isEmpty {
                HStack(spacing: 8) {
                    ForEach(secondaries) { action in
                        Button(action.title) { perform(action.id) }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                            .disabled(!action.isEnabled)
                            .help(action.help)
                    }
                }
            }
            if let primary {
                if rung == .full {
                    primaryButton(primary)
                } else {
                    splitButton(primary, short: rung == .splitShort)
                }
            }
        }
    }

    private var transportGroup: some View {
        ControlGroup {
            ForEach(transport) { action in
                Button {
                    perform(action.id)
                } label: {
                    Label(action.title, systemImage: action.symbol ?? "circle")
                }
                .disabled(!action.isEnabled)
                .help(action.help)
            }
        }
        .labelStyle(.iconOnly)
        .controlSize(.regular)
    }

    private func primaryLabel(_ action: PanelAction, title: String) -> some View {
        Label(title, systemImage: action.symbol ?? "circle")
            .fontWeight(.semibold)
            .frame(minWidth: Self.primaryMinimumLabelWidth)
    }

    @ViewBuilder private func primaryButton(_ action: PanelAction) -> some View {
        let button = Button {
            perform(action.id)
        } label: {
            primaryLabel(action, title: action.title)
        }
        .controlSize(.large)
        .disabled(!action.isEnabled)
        .help(action.help)
        if action.role == .interrupt {
            button.buttonStyle(.bordered)
        } else {
            button.buttonStyle(.borderedProminent)
        }
    }

    private func splitButton(_ action: PanelAction, short: Bool) -> some View {
        Menu {
            ForEach(secondaries) { secondary in
                Button(secondary.title) { perform(secondary.id) }
                    .disabled(!secondary.isEnabled)
            }
        } label: {
            primaryLabel(action, title: short ? action.shortTitle ?? action.title : action.title)
        } primaryAction: {
            if action.isEnabled { perform(action.id) }
        }
        .menuStyle(.button)
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!action.isEnabled && !secondaries.contains(where: \.isEnabled))
        .help(action.help)
        .accessibilityLabel(action.title)
    }
}
