import SwiftUI

/// Presenter-facing status for the Demo Mode caption HUD.
enum DemoCaptionStatus: Equatable, Sendable {
    case listening
    case thinking
    case highlighting(String)
    case clicking(String)
    /// A generic action caption ("Typing…", "Circling Swap", "Zooming to …").
    case acting(symbol: String, text: String)

    var symbol: String {
        switch self {
        case .listening: "waveform"
        case .thinking: "ellipsis"
        case .highlighting: "sparkle.magnifyingglass"
        case .clicking: "cursorarrow.click.2"
        case let .acting(symbol, _): symbol
        }
    }

    var text: String {
        switch self {
        case .listening: "Listening"
        case .thinking: "Thinking…"
        case let .highlighting(name): "Highlighting \(name)"
        case let .clicking(name): "Opening \(name)"
        case let .acting(_, text): text
        }
    }

    /// Transient statuses auto-revert to listening; listening and thinking are
    /// held until explicitly replaced (thinking ends when the async work does).
    var isTransient: Bool {
        switch self {
        case .highlighting, .clicking, .acting: true
        case .listening, .thinking: false
        }
    }
}

/// A single caption instance. Identity drives the HUD's enter/exit transition.
struct DemoCaption: Identifiable, Equatable, Sendable {
    let id = UUID()
    let status: DemoCaptionStatus
}

/// The compact material pill shown over the source window. It never renders on
/// the Demo Stage, so meeting viewers do not see it.
struct DemoCaptionHUD: View {
    let caption: DemoCaption

    @State private var isPulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.legibilityWeight) private var legibilityWeight

    private var isThinking: Bool { caption.status == .thinking }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: caption.status.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accentColor)
                .symbolRenderingMode(.hierarchical)
                .opacity(isThinking && !reduceMotion ? (isPulsing ? 0.45 : 1) : 1)
                .animation(
                    isThinking && !reduceMotion
                        ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
                        : .default,
                    value: isPulsing
                )
                .task(id: isThinking) {
                    isPulsing = isThinking
                }

            Text(caption.status.text)
                .font(.caption)
                .fontWeight(legibilityWeight == .bold ? .bold : .semibold)
                .lineLimit(1)
        }
        .padding(.leading, 11)
        .padding(.trailing, 13)
        .padding(.vertical, 7)
        .background(
            reduceTransparency
                ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
                : AnyShapeStyle(.regularMaterial),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .strokeBorder(
                    Color.primary.opacity(colorSchemeContrast == .increased ? 0.58 : 0.22),
                    lineWidth: colorSchemeContrast == .increased ? 1.5 : 1
                )
        }
        .shadow(color: Color.black.opacity(0.28), radius: 8, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(caption.status.text)
    }

    private var accentColor: Color {
        switch caption.status {
        case .listening: Color(red: 0.21, green: 0.84, blue: 1)
        case .thinking: Color(red: 0.66, green: 0.55, blue: 1)
        case .highlighting: Color(red: 0.36, green: 0.7, blue: 1)
        case .clicking: Color(red: 0.4, green: 0.85, blue: 0.55)
        case .acting: Color(red: 0.98, green: 0.75, blue: 0.35)
        }
    }
}
