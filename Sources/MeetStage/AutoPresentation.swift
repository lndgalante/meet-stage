import AppKit
import Foundation
import SwiftUI

struct AutoZoomTransform: Equatable, Sendable {
    static let identity = AutoZoomTransform(scale: 1, offset: .zero)

    let scale: CGFloat
    let offset: CGSize

    static func resolve(
        focus: NormalizedWindowPoint?,
        requestedScale: CGFloat,
        viewportSize: CGSize,
        reducesMotion: Bool
    ) -> AutoZoomTransform {
        guard
            let focus,
            viewportSize.width > 0,
            viewportSize.height > 0
        else { return .identity }

        let scale =
            reducesMotion
            ? min(max(requestedScale, 1), 1.12)
            : min(max(requestedScale, 1), 2)
        let clampedFocus = AutoZoomCameraPolicy.clampedFocus(
            focus,
            scale: scale
        )
        let desiredX =
            viewportSize.width / 2
            - clampedFocus.x * viewportSize.width * scale
        let desiredY =
            viewportSize.height / 2
            - clampedFocus.y * viewportSize.height * scale
        let minimumX = viewportSize.width - viewportSize.width * scale
        let minimumY = viewportSize.height - viewportSize.height * scale

        return AutoZoomTransform(
            scale: scale,
            offset: CGSize(
                width: min(max(desiredX, minimumX), 0),
                height: min(max(desiredY, minimumY), 0)
            )
        )
    }
}

enum AutoZoomCameraPolicy {
    static let safeZoneInsetRatio: CGFloat = 0.22

    static func clampedFocus(
        _ focus: NormalizedWindowPoint,
        scale: CGFloat
    ) -> NormalizedWindowPoint {
        let safeScale = max(scale, 1)
        let halfVisibleSpan = 1 / (safeScale * 2)
        return NormalizedWindowPoint(
            x: min(max(focus.x, halfVisibleSpan), 1 - halfVisibleSpan),
            y: min(max(focus.y, halfVisibleSpan), 1 - halfVisibleSpan)
        )
    }

    static func focusFollowingPointer(
        current: NormalizedWindowPoint,
        pointer: NormalizedWindowPoint,
        scale: CGFloat,
        safeZoneInsetRatio: CGFloat = safeZoneInsetRatio
    ) -> NormalizedWindowPoint {
        let safeScale = max(scale, 1)
        let visibleSpan = 1 / safeScale
        let halfVisibleSpan = visibleSpan / 2
        let inset = visibleSpan * min(max(safeZoneInsetRatio, 0), 0.49)
        let current = clampedFocus(current, scale: safeScale)

        let safeLeft = current.x - halfVisibleSpan + inset
        let safeRight = current.x + halfVisibleSpan - inset
        let safeTop = current.y - halfVisibleSpan + inset
        let safeBottom = current.y + halfVisibleSpan - inset

        var nextX = current.x
        var nextY = current.y
        if pointer.x < safeLeft {
            nextX -= safeLeft - pointer.x
        } else if pointer.x > safeRight {
            nextX += pointer.x - safeRight
        }
        if pointer.y < safeTop {
            nextY -= safeTop - pointer.y
        } else if pointer.y > safeBottom {
            nextY += pointer.y - safeBottom
        }

        return clampedFocus(
            NormalizedWindowPoint(x: nextX, y: nextY),
            scale: safeScale
        )
    }
}

@MainActor
final class AutoPresentationSession: ObservableObject {
    static let zoomHoldDuration = Duration.milliseconds(1_900)

    @Published private(set) var zoomFocus: NormalizedWindowPoint?
    /// A per-focus scale set by Demo Mode when it drives the camera directly.
    /// When nil, callers fall back to the global Auto Polish zoom size.
    @Published private(set) var zoomScaleOverride: CGFloat?
    let cursor = AutoPresentationCursorSession()

    private var zoomDismissTask: Task<Void, Never>?

    deinit {
        zoomDismissTask?.cancel()
    }

    /// Focuses the stage camera on a control for a fixed hold, independent of
    /// pointer following. Used by Demo Mode to frame a named control while it is
    /// highlighted. Unlike `registerClick`, this does not track the pointer, so
    /// the framing stays put through the narration.
    func focus(
        on point: NormalizedWindowPoint,
        zoomScale: CGFloat,
        hold: Duration
    ) {
        zoomScaleOverride = zoomScale
        zoomFocus = AutoZoomCameraPolicy.clampedFocus(point, scale: zoomScale)

        zoomDismissTask?.cancel()
        zoomDismissTask = Task { [weak self] in
            do {
                try await Task.sleep(for: hold)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.zoomFocus = nil
            self?.zoomScaleOverride = nil
            self?.zoomDismissTask = nil
        }
    }

    func updatePointer(
        _ location: NormalizedWindowPoint?,
        zoomScale: CGFloat
    ) {
        cursor.update(location: location)
        guard let location, let zoomFocus else { return }
        let nextFocus = AutoZoomCameraPolicy.focusFollowingPointer(
            current: zoomFocus,
            pointer: location,
            scale: zoomScale
        )
        if nextFocus != zoomFocus {
            self.zoomFocus = nextFocus
        }
    }

    func registerClick(
        at location: NormalizedWindowPoint,
        zoomScale: CGFloat
    ) {
        cursor.update(location: location)
        zoomScaleOverride = nil
        if let zoomFocus {
            self.zoomFocus = AutoZoomCameraPolicy.focusFollowingPointer(
                current: zoomFocus,
                pointer: location,
                scale: zoomScale
            )
        } else {
            zoomFocus = AutoZoomCameraPolicy.clampedFocus(
                location,
                scale: zoomScale
            )
        }

        zoomDismissTask?.cancel()
        zoomDismissTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.zoomHoldDuration)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.zoomFocus = nil
            self?.zoomDismissTask = nil
        }
    }

    func cancelZoom() {
        zoomDismissTask?.cancel()
        zoomDismissTask = nil
        zoomFocus = nil
        zoomScaleOverride = nil
    }

    func clear() {
        cancelZoom()
        cursor.update(location: nil)
    }
}

@MainActor
final class AutoPresentationCursorSession: ObservableObject {
    @Published private(set) var location: NormalizedWindowPoint?
    @Published private(set) var appearance = SystemCursorAppearance.current()

    private static let appearanceRefreshInterval: TimeInterval = 0.1
    private var lastAppearanceRefreshTime: TimeInterval = 0

    func update(location: NormalizedWindowPoint?) {
        refreshSystemCursorIfNeeded()
        if self.location != location {
            self.location = location
        }
    }

    private func refreshSystemCursorIfNeeded() {
        let currentTime = ProcessInfo.processInfo.systemUptime
        guard currentTime - lastAppearanceRefreshTime >= Self.appearanceRefreshInterval else {
            return
        }
        lastAppearanceRefreshTime = currentTime

        let appearance = SystemCursorAppearance.current()
        if appearance.cursorIdentifier != self.appearance.cursorIdentifier
            || appearance.imageSize != self.appearance.imageSize
            || appearance.hotSpot != self.appearance.hotSpot
        {
            self.appearance = appearance
        }
    }
}

struct EnlargedSystemCursorLayer: View {
    @ObservedObject var session: AutoPresentationCursorSession

    var body: some View {
        GeometryReader { geometry in
            if let location = session.location {
                let frame = EnlargedCursorGeometry.frame(
                    pointerLocation: location,
                    viewportSize: geometry.size,
                    imageSize: session.appearance.imageSize,
                    hotSpot: session.appearance.hotSpot
                )

                Image(nsImage: session.appearance.image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .transition(.opacity)
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct SystemCursorAppearance {
    let cursorIdentifier: ObjectIdentifier
    let image: NSImage
    let imageSize: CGSize
    let hotSpot: CGPoint

    static func current() -> SystemCursorAppearance {
        let cursor = activeSystemCursor() ?? .arrow
        return SystemCursorAppearance(
            cursorIdentifier: ObjectIdentifier(cursor),
            image: cursor.image,
            imageSize: cursor.image.size,
            hotSpot: cursor.hotSpot
        )
    }

    private static func activeSystemCursor() -> NSCursor? {
        // `NSCursor.current` is scoped to BetterMeets. macOS 26's compatibility
        // accessor is the only AppKit API that exposes the cursor another app is
        // currently displaying. Resolve it dynamically so a future nil result
        // degrades to the native arrow without relying on a custom cursor asset.
        let selector = NSSelectorFromString("currentSystemCursor")
        guard NSCursor.responds(to: selector),
            let unmanagedCursor = NSCursor.perform(selector)
        else { return nil }
        return unmanagedCursor.takeUnretainedValue() as? NSCursor
    }
}

enum EnlargedCursorGeometry {
    static let magnification: CGFloat = 2

    static func frame(
        pointerLocation: NormalizedWindowPoint,
        viewportSize: CGSize,
        imageSize: CGSize,
        hotSpot: CGPoint
    ) -> CGRect {
        let renderedSize = CGSize(
            width: imageSize.width * magnification,
            height: imageSize.height * magnification
        )
        let pointer = CGPoint(
            x: pointerLocation.x * viewportSize.width,
            y: pointerLocation.y * viewportSize.height
        )
        return CGRect(
            x: pointer.x - hotSpot.x * magnification,
            y: pointer.y - hotSpot.y * magnification,
            width: renderedSize.width,
            height: renderedSize.height
        )
    }
}

extension PresentationSize {
    var autoZoomScale: CGFloat {
        switch self {
        case .small: 1.35
        case .medium: 1.58
        case .large: 1.82
        }
    }
}
