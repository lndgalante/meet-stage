import SwiftUI

/// What the stage and the source overlay show for the current demo step.
struct DemoCue: Hashable {
    var effect: DemoEffect?
    var rect: NormRect?
    var key: String?

    init(effect: DemoEffect? = nil, rect: NormRect? = nil, key: String? = nil) {
        self.effect = effect
        self.rect = rect?.clampedToWindow
        self.key = key
    }

    var zoomFocus: NormalizedWindowPoint? {
        guard effect == .magnify, let rect, rect.isUsable else { return nil }
        return rect.center
    }

    /// Small details get a closer zoom than whole sections, so a magnified
    /// region fills roughly half of the stage either way.
    var zoomScale: Double {
        guard let rect, rect.isUsable else { return 1.7 }
        return min(2.6, max(1.35, 0.5 / max(rect.w, rect.h)))
    }

    var hasSourceOverlay: Bool {
        switch effect {
        case .spotlight, .draw: return rect?.isUsable == true
        case .magnify, nil: return key?.isEmpty == false
        }
    }
}

/// Where the stage draws the demo's virtual cursor, and how long it takes to get there.
struct DemoPointer: Equatable {
    var location: NormalizedWindowPoint
    var travel: Double
}

/// The system arrow, gliding between demo targets on the stage. The real
/// cursor stays with the presenter in BetterMeets.
struct DemoPointerLayer: View {
    let pointer: DemoPointer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let image = NSCursor.arrow.image
            let scale = 1.6
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let hotSpot = NSCursor.arrow.hotSpot
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size.width, height: size.height)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                .position(
                    x: pointer.location.x * geometry.size.width + size.width / 2 - hotSpot.x * scale,
                    y: pointer.location.y * geometry.size.height + size.height / 2 - hotSpot.y * scale)
                .animation(
                    reduceMotion ? nil : .timingCurve(0.25, 0.1, 0.25, 1, duration: max(pointer.travel, 0.05)),
                    value: pointer.location)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct DemoSourceEffectSurface: View {
    let cue: DemoCue
    let keySize: PresentationSize
    let keyAppearance: KeystrokeAppearance

    var body: some View {
        ZStack(alignment: .bottom) {
            DemoEffectLayer(cue: cue).id(cue)
            if let key = cue.key, !key.isEmpty {
                KeystrokeBadge(label: key, size: keySize, appearance: keyAppearance)
                    .padding(.bottom, 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct DemoEffectLayer: View {
    let cue: DemoCue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var shown = false

    var body: some View {
        GeometryReader { geometry in
            if let target = cue.rect, target.isUsable {
                let rect = target.bounds.resolved(in: CGRect(origin: .zero, size: geometry.size)).insetBy(
                    dx: -7, dy: -7)
                if cue.effect == .spotlight {
                    DemoSpotlightMask(aperture: rect)
                        .fill(.black.opacity(shown || reduceMotion ? 0.58 : 0), style: FillStyle(eoFill: true))
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.white.opacity(0.9), lineWidth: contrast == .increased ? 3 : 2)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .opacity(shown || reduceMotion ? 1 : 0)
                }
                if cue.effect == .draw {
                    Ellipse()
                        .trim(from: 0, to: shown || reduceMotion ? 1 : 0)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: rect.width + 14, height: rect.height + 14)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: cue.effect == .draw ? 0.5 : 0.25)) { shown = true }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct DemoSpotlightMask: Shape {
    let aperture: CGRect
    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addRoundedRect(in: aperture, cornerSize: CGSize(width: 8, height: 8))
        return path
    }
}
