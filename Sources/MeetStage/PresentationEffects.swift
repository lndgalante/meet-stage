import AppKit
import ApplicationServices
import Foundation
import SwiftUI

struct NormalizedWindowPoint: Equatable, Sendable {
    let x: CGFloat
    let y: CGFloat
}

struct ClickPresentation: Equatable, Identifiable, Sendable {
    let id = UUID()
    let location: NormalizedWindowPoint
}

struct GlobalClickLocation: Equatable, Sendable {
    let quartzX: CGFloat
    let quartzY: CGFloat
    let appKitX: CGFloat
    let appKitY: CGFloat

    var quartzPoint: CGPoint {
        CGPoint(x: quartzX, y: quartzY)
    }

    var appKitPoint: CGPoint {
        CGPoint(x: appKitX, y: appKitY)
    }
}

struct KeystrokePresentation: Equatable, Identifiable, Sendable {
    let id = UUID()
    let label: String
}

enum PresentationEffectFocusPolicy {
    static func shouldPresent(isEnabled: Bool, selectedSourceIsFocused: Bool) -> Bool {
        isEnabled && selectedSourceIsFocused
    }
}

enum ClickPresentationGeometry {
    static func normalizedLocation(
        for globalLocation: CGPoint,
        in sourceFrame: CGRect
    ) -> NormalizedWindowPoint? {
        guard sourceFrame.width > 0,
            sourceFrame.height > 0,
            globalLocation.x >= sourceFrame.minX,
            globalLocation.x <= sourceFrame.maxX,
            globalLocation.y >= sourceFrame.minY,
            globalLocation.y <= sourceFrame.maxY
        else { return nil }

        return NormalizedWindowPoint(
            x: (globalLocation.x - sourceFrame.minX) / sourceFrame.width,
            y: (globalLocation.y - sourceFrame.minY) / sourceFrame.height
        )
    }

    static func appKitOverlayFrame(
        sourceFrame: CGRect,
        globalClickLocation: CGPoint,
        appKitClickLocation: CGPoint
    ) -> CGRect {
        let localX = globalClickLocation.x - sourceFrame.minX
        let localYFromTop = globalClickLocation.y - sourceFrame.minY

        return CGRect(
            x: appKitClickLocation.x - localX,
            y: appKitClickLocation.y - (sourceFrame.height - localYFromTop),
            width: sourceFrame.width,
            height: sourceFrame.height
        )
    }
}

enum WindowFrameResolver {
    static func currentFrame(for windowID: CGWindowID, fallback: CGRect) -> CGRect {
        guard let windowInfo = CGWindowListCopyWindowInfo(
            [.optionIncludingWindow, .excludeDesktopElements],
            windowID
        ) as? [[CFString: Any]],
            let bounds = windowInfo.first?[kCGWindowBounds] as? NSDictionary,
            let frame = CGRect(dictionaryRepresentation: bounds),
            frame.width > 0,
            frame.height > 0
        else { return fallback }

        return frame
    }
}

@MainActor
final class GlobalMouseClickMonitor {
    typealias Handler = @MainActor (GlobalClickLocation) -> Void

    private let handler: Handler
    private let resources = MouseClickMonitorResources()

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func start() {
        guard resources.monitor == nil else { return }
        resources.monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let cgEvent = event.cgEvent else { return }
            let quartzPoint = cgEvent.location
            let appKitPoint = cgEvent.unflippedLocation
            let location = GlobalClickLocation(
                quartzX: quartzPoint.x,
                quartzY: quartzPoint.y,
                appKitX: appKitPoint.x,
                appKitY: appKitPoint.y
            )

            Task { @MainActor [weak self] in
                self?.handler(location)
            }
        }
    }

    func stop() {
        guard let monitor = resources.monitor else { return }
        NSEvent.removeMonitor(monitor)
        resources.monitor = nil
    }
}

private final class MouseClickMonitorResources: @unchecked Sendable {
    var monitor: Any?

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

@MainActor
final class SourceClickRipplePresenter {
    private var panels: [UUID: NSPanel] = [:]
    private var dismissTasks: [UUID: Task<Void, Never>] = [:]

    func show(
        _ presentation: ClickPresentation,
        sourceFrame: CGRect,
        clickLocation: GlobalClickLocation
    ) {
        let panel = ClickThroughPanel(
            contentRect: ClickPresentationGeometry.appKitOverlayFrame(
                sourceFrame: sourceFrame,
                globalClickLocation: clickLocation.quartzPoint,
                appKitClickLocation: clickLocation.appKitPoint
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .transient
        ]
        panel.contentView = NSHostingView(
            rootView: SourceClickRippleSurface(
                presentation: presentation,
                reducesMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            )
        )

        panels[presentation.id] = panel
        panel.orderFrontRegardless()

        dismissTasks[presentation.id]?.cancel()
        dismissTasks[presentation.id] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(560))
            guard !Task.isCancelled else { return }
            self?.dismiss(presentation.id)
        }
    }

    func dismissAll() {
        dismissTasks.values.forEach { $0.cancel() }
        dismissTasks.removeAll()
        panels.values.forEach { $0.close() }
        panels.removeAll()
    }

    private func dismiss(_ id: UUID) {
        dismissTasks[id]?.cancel()
        dismissTasks[id] = nil
        panels.removeValue(forKey: id)?.close()
    }
}

private final class ClickThroughPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct SourceClickRippleSurface: View {
    let presentation: ClickPresentation
    let reducesMotion: Bool

    var body: some View {
        GeometryReader { geometry in
            ClickRippleGlyph(reducesMotion: reducesMotion)
                .position(
                    x: presentation.location.x * geometry.size.width,
                    y: presentation.location.y * geometry.size.height
                )
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct ClickRippleGlyph: View {
    let reducesMotion: Bool

    @State private var isReceding = false

    private let color = Color(red: 1, green: 0.47, blue: 0.14)

    var body: some View {
        ZStack {
            Circle()
                .stroke(color, lineWidth: isReceding ? 1.5 : 3)
                .frame(
                    width: reducesMotion ? 24 : (isReceding ? 54 : 12),
                    height: reducesMotion ? 24 : (isReceding ? 54 : 12)
                )
                .opacity(isReceding ? 0 : 0.95)

            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .scaleEffect(isReceding ? 0.75 : 1)
                .opacity(isReceding ? 0 : 1)
        }
        .frame(width: 58, height: 58)
        .shadow(color: .black.opacity(0.34), radius: 2, y: 1)
        .task {
            await Task.yield()
            withAnimation(.easeOut(duration: reducesMotion ? 0.22 : 0.46)) {
                isReceding = true
            }
        }
    }
}

@MainActor
final class GlobalKeystrokeMonitor {
    typealias Handler = @MainActor (String) -> Void

    private let handler: Handler
    private let resources = KeystrokeMonitorResources()

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityPermission() {
        let options =
            [
                "AXTrustedCheckOptionPrompt": true
            ] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func start() {
        guard resources.monitor == nil else { return }
        resources.monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard !event.isARepeat,
                let label = KeystrokeFormatter.label(for: event)
            else { return }

            Task { @MainActor [weak self] in
                self?.handler(label)
            }
        }
    }

    func stop() {
        guard let monitor = resources.monitor else { return }
        NSEvent.removeMonitor(monitor)
        resources.monitor = nil
    }
}

private final class KeystrokeMonitorResources: @unchecked Sendable {
    var monitor: Any?

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

enum KeystrokeFormatter {
    private static let specialKeys: [UInt16: String] = [
        36: "Return",
        48: "Tab",
        49: "Space",
        51: "Delete",
        53: "Esc",
        71: "Clear",
        76: "Enter",
        115: "Home",
        116: "Page Up",
        117: "Forward Delete",
        119: "End",
        121: "Page Down",
        123: "←",
        124: "→",
        125: "↓",
        126: "↑"
    ]

    static func label(for event: NSEvent) -> String? {
        label(
            keyCode: event.keyCode,
            characters: event.charactersIgnoringModifiers,
            modifierFlags: event.modifierFlags
        )
    }

    static func label(
        keyCode: UInt16,
        characters: String?,
        modifierFlags: NSEvent.ModifierFlags
    ) -> String? {
        guard let key = keyLabel(keyCode: keyCode, characters: characters) else { return nil }

        var parts: [String] = []
        let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        parts.append(key)
        return parts.joined(separator: " ")
    }

    private static func keyLabel(keyCode: UInt16, characters: String?) -> String? {
        if let specialKey = specialKeys[keyCode] {
            return specialKey
        }

        guard let characters, !characters.isEmpty else { return nil }
        let printable = characters.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0)
        }
        guard !printable.isEmpty else { return nil }
        return String(String.UnicodeScalarView(printable)).uppercased()
    }
}
