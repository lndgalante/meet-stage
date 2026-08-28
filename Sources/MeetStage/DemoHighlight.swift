import AppKit
import Foundation
import SwiftUI

/// A timed ring drawn around a control that narration named. Like every
/// presentation effect it is a single Sendable value rendered on both the
/// source-window overlay (for the presenter) and the Demo Stage (for viewers).
struct DemoHighlightPresentation: Identifiable, Equatable, Sendable {
    let id = UUID()
    let bounds: NormalizedAnnotationBounds
    let color: PresentationColor
    let kind: DemoIntentKind

    var duration: Duration {
        kind == .click ? .milliseconds(2_400) : .milliseconds(2_800)
    }
}

/// Renders the current Demo Mode highlights inside a viewport. Used verbatim on
/// the source overlay and the Demo Stage so both surfaces stay identical.
struct DemoHighlightSurface: View {
    let highlights: [DemoHighlightPresentation]
    let reducesMotion: Bool

    var body: some View {
        GeometryReader { geometry in
            ForEach(highlights) { highlight in
                DemoHighlightRing(
                    rect: highlight.bounds.resolved(in: CGRect(origin: .zero, size: geometry.size)),
                    color: highlight.color.color,
                    isClick: highlight.kind == .click,
                    reducesMotion: reducesMotion
                )
                .id(highlight.id)
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct DemoHighlightRing: View {
    let rect: CGRect
    let color: Color
    let isClick: Bool
    let reducesMotion: Bool

    @State private var isPresented = false

    private var padding: CGFloat {
        max(6, min(rect.width, rect.height) * 0.16)
    }

    private var cornerRadius: CGFloat {
        min(18, min(rect.width, rect.height) * 0.5 + padding)
    }

    var body: some View {
        let outer = rect.insetBy(dx: -padding, dy: -padding)
        let lineWidth: CGFloat = isClick ? 4 : 3

        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(color, lineWidth: lineWidth)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(color.opacity(isClick ? 0.16 : 0.10))
                )
                .frame(width: outer.width, height: outer.height)
                .shadow(color: color.opacity(0.55), radius: 8)
                .shadow(color: .black.opacity(0.28), radius: 2, y: 1)
                .opacity(reducesMotion ? 1 : (isPresented ? 1 : 0))
                .scaleEffect(reducesMotion ? 1 : (isPresented ? 1 : 1.14))
        }
        .frame(width: outer.width, height: outer.height)
        .position(x: rect.midX, y: rect.midY)
        .task {
            await Task.yield()
            guard !reducesMotion else {
                isPresented = true
                return
            }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.7)) {
                isPresented = true
            }
        }
    }
}

/// Presents Demo Mode highlights and the presenter caption over the real source
/// window. ScreenCaptureKit captures only the source window's own pixels, so
/// this overlay panel is visible to the presenter but never to meeting viewers.
/// The caption is therefore private; the highlight ring is re-rendered on the
/// Demo Stage separately so viewers still see it.
@MainActor
final class DemoSourceOverlayPresenter {
    private var panel: SpotlightPanel?
    private let frameTracker = SourceOverlayFrameTracker()
    private var sourceWindowID: CGWindowID?

    func show(
        session: DemoModeSession,
        sourceWindowID: CGWindowID,
        fallbackSourceFrame: CGRect
    ) {
        if panel != nil, self.sourceWindowID == sourceWindowID {
            return
        }
        dismiss()
        self.sourceWindowID = sourceWindowID

        let panel = SpotlightPanel(
            contentRect: SourceOverlayGeometry.currentAppKitFrame(
                for: sourceWindowID,
                fallbackSourceFrame: fallbackSourceFrame
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        SpotlightWindowPolicy.configure(panel)
        panel.contentView = NSHostingView(
            rootView: DemoSourceOverlay(session: session)
        )
        self.panel = panel
        panel.orderFrontRegardless()

        frameTracker.start(
            sourceWindowID: sourceWindowID,
            fallbackSourceFrame: fallbackSourceFrame
        ) { [weak panel] frame in
            guard let panel, panel.frame != frame else { return }
            panel.setFrame(frame, display: true)
        }
    }

    func dismiss() {
        frameTracker.stop()
        sourceWindowID = nil
        panel?.close()
        panel = nil
    }
}

/// The presenter-only overlay: highlight rings plus a small caption that shows
/// what Demo Mode heard and did.
private struct DemoSourceOverlay: View {
    @ObservedObject var session: DemoModeSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            DemoHighlightSurface(
                highlights: session.highlights,
                reducesMotion: reduceMotion
            )

            if let caption = session.caption {
                DemoCaptionHUD(caption: caption)
                    .padding(.top, 16)
                    .id(caption.id)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .move(edge: .top))
                    )
            }
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.9),
            value: session.caption?.id
        )
    }
}
