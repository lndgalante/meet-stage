import SwiftUI

/// Claude's mark: a multi-hue edge around something it's working on. It turns
/// while Claude drives the app and holds still otherwise, and with Reduce
/// Motion. It never takes input.
struct DemoGlow: View {
    var cornerRadius: CGFloat
    var lineWidth: CGFloat = 2
    var turns = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let colors: [Color] = [.accentColor, .purple, .pink, .orange, .accentColor]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !turns || reduceMotion)) { context in
            let degrees =
                turns && !reduceMotion
                ? (context.date.timeIntervalSinceReferenceDate * 90).truncatingRemainder(dividingBy: 360) : 0
            let gradient = AngularGradient(colors: Self.colors, center: .center, angle: .degrees(degrees))
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            ZStack {
                shape.strokeBorder(gradient, lineWidth: lineWidth * 3).blur(radius: 10).opacity(0.55)
                shape.strokeBorder(gradient, lineWidth: lineWidth)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The stage's edge while BetterMeets builds, tests or resets a demo in the
/// app, so it's clear the app is being operated on purpose.
struct DemoDrivingGlow: View {
    @ObservedObject var demo: DemoSession
    var cornerRadius: CGFloat

    var body: some View {
        ZStack {
            if isDriving {
                DemoGlow(cornerRadius: cornerRadius, turns: true)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.3), value: isDriving)
    }

    private var isDriving: Bool {
        switch demo.phase {
        case .scouting, .returning, .running(.verify, _, _): true
        default: false
        }
    }
}
