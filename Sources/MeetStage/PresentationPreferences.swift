import SwiftUI

enum PresentationColor: String, CaseIterable, Identifiable, Sendable {
    case red
    case orange
    case yellow
    case green
    case blue
    case purple

    var id: Self { self }

    var label: String {
        rawValue.capitalized
    }

    var color: Color {
        switch self {
        case .red:
            Color(red: 1, green: 0.29, blue: 0.25)
        case .orange:
            Color(red: 1, green: 0.47, blue: 0.14)
        case .yellow:
            Color(red: 1, green: 0.78, blue: 0.12)
        case .green:
            Color(red: 0.24, green: 0.78, blue: 0.35)
        case .blue:
            Color(red: 0.18, green: 0.64, blue: 1)
        case .purple:
            Color(red: 0.72, green: 0.44, blue: 1)
        }
    }

    var contrastingColor: Color {
        self == .yellow ? .black.opacity(0.78) : .white
    }
}

enum PresentationSize: String, CaseIterable, Identifiable, Sendable {
    case small
    case medium
    case large

    var id: Self { self }

    var label: String {
        rawValue.capitalized
    }
}

enum KeystrokeAppearance: String, CaseIterable, Identifiable, Sendable {
    case light
    case dark

    var id: Self { self }

    var label: String {
        rawValue.capitalized
    }
}
