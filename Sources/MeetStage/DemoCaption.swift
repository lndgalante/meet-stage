import SwiftUI

/// Presenter-facing status for the Demo Mode caption HUD.
enum DemoCaptionStatus: Equatable, Sendable {
    case listening
    case highlighting(String)
    case clicking(String)

    var symbol: String {
        switch self {
        case .listening: "waveform"
        case .highlighting: "sparkle.magnifyingglass"
        case .clicking: "cursorarrow.click.2"
        }
    }

    var text: String {
        switch self {
        case .listening: "Listening"
        case let .highlighting(name): "Highlighting \(name)"
        case let .clicking(name): "Opening \(name)"
        }
    }

    var isTransient: Bool {
        self != .listening
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

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: caption.status.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accentColor)
                .symbolRenderingMode(.hierarchical)

            Text(caption.status.text)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.leading, 11)
        .padding(.trailing, 13)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.28), radius: 8, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(caption.status.text)
    }

    private var accentColor: Color {
        switch caption.status {
        case .listening: Color(red: 0.21, green: 0.84, blue: 1)
        case .highlighting: Color(red: 0.36, green: 0.7, blue: 1)
        case .clicking: Color(red: 0.4, green: 0.85, blue: 0.55)
        }
    }
}
