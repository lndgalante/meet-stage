import AppKit
import SwiftUI

/// A small notice over whatever app the presenter is in, for when a demo
/// finishes building or needs them while BetterMeets is in the background.
struct DemoToastContent: Equatable {
    enum Kind: Equatable {
        case ready, attention
    }

    var kind: Kind
    var title: String
    var detail: String
}

/// Shows `DemoToastContent` in a floating panel near the top of the screen. It
/// never takes focus; its button brings BetterMeets forward, which macOS allows
/// because the presenter clicked it.
@MainActor
final class DemoToastController {
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?

    func show(_ content: DemoToastContent) {
        dismiss()
        let view = DemoToastView(
            content: content,
            open: { [weak self] in
                self?.dismiss()
                BetterMeetsWindowActions.showStage()
            }, close: { [weak self] in self?.dismiss() })
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        host.frame.size = size
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = host
        // The screen the presenter is looking at: the one under the pointer.
        let screen =
            NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height - 12))
        }
        panel.orderFrontRegardless()
        self.panel = panel

        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
        if content.kind == .ready {
            dismissTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled else { return }
                self?.dismiss()
            }
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        activationObserver = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct DemoToastView: View {
    let content: DemoToastContent
    let open: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: content.kind == .ready ? "checkmark.seal.fill" : "exclamationmark.bubble.fill")
                .font(.title2)
                .foregroundStyle(content.kind == .ready ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(content.title).font(.headline)
                Text(content.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: 300, alignment: .leading)
            Button("Open BetterMeets", action: open)
                .buttonStyle(.borderedProminent)
            Button(action: close) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.1)))
        .padding(8)
        .accessibilityElement(children: .contain)
    }
}
