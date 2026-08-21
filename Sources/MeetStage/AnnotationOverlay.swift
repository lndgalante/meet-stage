import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Presents the interactive annotation surface over the selected source
/// window while `AnnotationSession` remains independent of AppKit lifecycle.
@MainActor
final class SourceAnnotationPresenter {
    private var panel: AnnotationPanel?
    private let frameTracker = SourceOverlayFrameTracker()

    func show(
        session: AnnotationSession,
        sourceWindowID: CGWindowID,
        fallbackSourceFrame: CGRect,
        onFinish: @escaping @MainActor () -> Void
    ) {
        dismiss()

        let panel = AnnotationPanel(
            contentRect: SourceOverlayGeometry.currentAppKitFrame(
                for: sourceWindowID,
                fallbackSourceFrame: fallbackSourceFrame
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        AnnotationWindowPolicy.configure(panel)
        panel.onCancel = onFinish
        panel.contentView = NSHostingView(
            rootView: SourceAnnotationSurface(
                session: session,
                onFinish: onFinish
            )
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
        panel?.close()
        panel = nil
    }
}

enum AnnotationWindowPolicy {
    // The selected source windows are normal-level, while BetterMeets' compact
    // controller is floating. This slot keeps ink above the source without
    // making the controller unreachable when the two overlap.
    static let sourceOverlayLevel = NSWindow.Level(
        rawValue: NSWindow.Level.normal.rawValue + 2
    )

    @MainActor
    static func configure(_ panel: AnnotationPanel) {
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = sourceOverlayLevel
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .transient
        ]
    }
}

final class AnnotationPanel: NSPanel {
    var onCancel: (@MainActor () -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }
}

struct SourceAnnotationSurface: View {
    @ObservedObject var session: AnnotationSession
    let onFinish: @MainActor () -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                AnnotationInkLayer(
                    session: session,
                    acceptsInput: true
                )

                if geometry.size.width >= 320, geometry.size.height >= 160 {
                    annotationModeIndicator
                        .padding(.top, 12)
                }
            }
        }
        .background(Color.clear)
    }

    private var annotationModeIndicator: some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil.tip")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(red: 0.21, green: 0.84, blue: 1))

            Text("Drawing")
                .font(.caption.weight(.semibold))

            Text("Esc")
                .font(.system(.caption2, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4, style: .continuous))

            Button("Done", action: onFinish)
                .buttonStyle(.borderless)
                .font(.caption.weight(.semibold))
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.28), radius: 8, y: 3)
        .accessibilityElement(children: .contain)
    }
}
