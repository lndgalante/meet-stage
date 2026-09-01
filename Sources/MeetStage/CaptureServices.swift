import AppKit
import MeetStageCore
import ScreenCaptureKit

/// Platform services composed at the `CaptureManager` boundary. Keeping these
/// dependencies injectable prevents persistence, screenshot work, and cloud
/// provider construction from being hidden inside the coordinator.
@MainActor
protocol WindowThumbnailLoading: AnyObject {
    func load(for sources: [WindowSource]) async -> [WindowThumbnailResult]
}

struct WindowThumbnailResult: @unchecked Sendable {
    let windowID: CGWindowID
    let image: CGImage?
    let errorDescription: String?
}

/// An immutable ScreenCaptureKit window snapshot transferred into a child task.
/// The child immediately re-enters MainActor before using the framework object;
/// no mutable `WindowSource` or `NSImage` state crosses the boundary.
private struct WindowThumbnailRequest: @unchecked Sendable {
    let windowID: CGWindowID
    let window: SCWindow

    init(source: WindowSource) {
        windowID = source.id
        window = source.window
    }
}

@MainActor
final class WindowThumbnailLoader: WindowThumbnailLoading {
    static let defaultMaximumConcurrentLoads = 4

    private let maximumConcurrentLoads: Int

    init(maximumConcurrentLoads: Int = defaultMaximumConcurrentLoads) {
        self.maximumConcurrentLoads = max(1, maximumConcurrentLoads)
    }

    func load(for sources: [WindowSource]) async -> [WindowThumbnailResult] {
        let requests = sources.map(WindowThumbnailRequest.init(source:))
        return await BoundedAsyncMap.map(
            requests,
            maximumConcurrent: maximumConcurrentLoads
        ) { request in
            await Self.loadOne(request)
        }
    }

    nonisolated private static func loadOne(_ request: WindowThumbnailRequest) async
        -> WindowThumbnailResult
    {
        do {
            return WindowThumbnailResult(
                windowID: request.windowID,
                image: try await WindowSourceDiscovery.thumbnailImage(for: request.window),
                errorDescription: nil
            )
        } catch {
            return WindowThumbnailResult(
                windowID: request.windowID,
                image: nil,
                errorDescription: error.localizedDescription
            )
        }
    }
}

struct DemoBrainRegistry: Sendable {
    let claude: any DemoBrain
    let openAI: any DemoBrain

    static func live() -> DemoBrainRegistry {
        DemoBrainRegistry(
            claude: ClaudeDemoBrain(),
            openAI: OpenAIDemoBrain()
        )
    }

    func brain(for provider: DemoBrainProvider) -> any DemoBrain {
        provider == .openai ? openAI : claude
    }
}
