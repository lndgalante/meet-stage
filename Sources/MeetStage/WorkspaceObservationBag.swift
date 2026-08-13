import Foundation

/// Owns non-Sendable Objective-C notification tokens so `CaptureManager` does
/// not access them from its nonisolated deinitializer.
final class WorkspaceObservationBag: @unchecked Sendable {
    private let center: NotificationCenter
    private var tokens: [NSObjectProtocol] = []

    init(center: NotificationCenter) {
        self.center = center
    }

    func store(_ tokens: [NSObjectProtocol]) {
        self.tokens.append(contentsOf: tokens)
    }

    deinit {
        tokens.forEach(center.removeObserver)
    }
}
