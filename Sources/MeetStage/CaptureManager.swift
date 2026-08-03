import AppKit
import CoreMedia
import ScreenCaptureKit

@MainActor
final class CaptureManager: ObservableObject {
    // SCStreamConfiguration.backgroundColor is an unretained CGColorRef. Keep
    // this object alive for the lifetime of the process; assigning a temporary
    // NSColor.cgColor leaves ScreenCaptureKit with a dangling pointer when it
    // copies the configuration asynchronously.
    private static let blackBackground = CGColor(gray: 0, alpha: 1)

    @Published private(set) var windows: [WindowSource] = []
    @Published private(set) var selectedWindowID: CGWindowID?
    @Published private(set) var selectedWindowDescription = "Nothing selected"
    @Published private(set) var state: CaptureState = .idle

    let renderer = SampleBufferRenderer()

    private let sampleQueue = DispatchQueue(
        label: "dev.poc.meetstage.screen-frames",
        qos: .userInteractive
    )
    private lazy var streamOutput = CaptureStreamOutput(renderer: renderer) { [weak self] message in
        Task { @MainActor in
            self?.state = .failed(message)
        }
    }

    private var stream: SCStream?
    private var pendingSelection: WindowSource?
    private var selectionTask: Task<Void, Never>?

    var isCapturing: Bool {
        stream != nil
    }

    var errorMessage: String? {
        guard case let .failed(message) = state else { return nil }
        return message
    }

    func refreshWindows() {
        guard state != .loading else { return }
        state = .loading

        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false,
                    onScreenWindowsOnly: true
                )

                let ownBundleIdentifier = Bundle.main.bundleIdentifier
                let candidates = content.windows
                    .filter { window in
                        let frame = window.frame
                        let title = window.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        let bundleIdentifier = window.owningApplication?.bundleIdentifier

                        return window.windowLayer == 0
                            && frame.width >= 160
                            && frame.height >= 100
                            && !title.isEmpty
                            && window.owningApplication != nil
                            && bundleIdentifier != ownBundleIdentifier
                    }
                    .map(WindowSource.init(window:))
                    .sorted {
                        let first = "\($0.applicationName) \($0.title)"
                        let second = "\($1.applicationName) \($1.title)"
                        return first.localizedCaseInsensitiveCompare(second) == .orderedAscending
                    }

                windows = candidates
                state = stream == nil ? .idle : .capturing
                await loadThumbnails(for: candidates)
            } catch {
                state = .failed(Self.friendlyMessage(for: error))
            }
        }
    }

    func select(_ source: WindowSource) {
        pendingSelection = source
        selectedWindowID = source.id
        selectedWindowDescription = "\(source.applicationName) — \(source.title)"

        guard selectionTask == nil else { return }
        selectionTask = Task { [weak self] in
            await self?.processPendingSelections()
        }
    }

    func stopCapture() {
        pendingSelection = nil
        selectionTask?.cancel()
        selectionTask = nil

        guard let stream else {
            state = .idle
            selectedWindowID = nil
            selectedWindowDescription = "Nothing selected"
            return
        }

        self.stream = nil
        Task {
            do {
                try await stream.stopCapture()
                state = .idle
                selectedWindowID = nil
                selectedWindowDescription = "Nothing selected"
            } catch {
                state = .failed(Self.friendlyMessage(for: error))
            }
        }
    }

    func openScreenRecordingSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func processPendingSelections() async {
        while !Task.isCancelled, let nextSelection = pendingSelection {
            pendingSelection = nil
            state = .switching

            do {
                try await switchCapture(to: nextSelection)
                state = .capturing
            } catch {
                state = .failed(Self.friendlyMessage(for: error))
            }
        }

        selectionTask = nil
    }

    private func switchCapture(to source: WindowSource) async throws {
        let filter = SCContentFilter(desktopIndependentWindow: source.window)

        if let stream {
            try await stream.updateContentFilter(filter)
            return
        }

        let configuration = SCStreamConfiguration()
        configuration.width = 1920
        configuration.height = 1080
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 3
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = true
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = true
        configuration.backgroundColor = Self.blackBackground
        configuration.capturesAudio = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.ignoreGlobalClipSingleWindow = true
        configuration.streamName = "Meet Presenter Stage"

        let newStream = SCStream(
            filter: filter,
            configuration: configuration,
            delegate: streamOutput
        )
        try newStream.addStreamOutput(
            streamOutput,
            type: .screen,
            sampleHandlerQueue: sampleQueue
        )
        try await newStream.startCapture()
        stream = newStream
    }

    private func loadThumbnails(for sources: [WindowSource]) async {
        for source in sources {
            guard let index = windows.firstIndex(where: { $0.id == source.id }) else { continue }

            do {
                let filter = SCContentFilter(desktopIndependentWindow: source.window)
                let configuration = SCStreamConfiguration()
                configuration.width = 480
                configuration.height = 270
                configuration.pixelFormat = kCVPixelFormatType_32BGRA
                configuration.scalesToFit = true
                configuration.preservesAspectRatio = true
                configuration.backgroundColor = Self.blackBackground
                configuration.ignoreShadowsSingleWindow = true
                configuration.ignoreGlobalClipSingleWindow = true

                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: configuration
                )
                windows[index].thumbnail = NSImage(
                    cgImage: image,
                    size: NSSize(width: image.width, height: image.height)
                )
            } catch {
                // A window can close while its thumbnail is loading. Keep the card
                // with an app-icon fallback and allow refresh to remove it.
            }
        }
    }

    private static func friendlyMessage(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == SCStreamErrorDomain || nsError.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain" {
            return "Screen capture is unavailable. Grant Meet Stage access in System Settings → Privacy & Security → Screen & System Audio Recording, then quit and reopen the app."
        }
        return error.localizedDescription
    }
}

private final class CaptureStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let renderer: SampleBufferRenderer
    private let onFailure: @Sendable (String) -> Void

    init(renderer: SampleBufferRenderer, onFailure: @escaping @Sendable (String) -> Void) {
        self.renderer = renderer
        self.onFailure = onFailure
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .screen else { return }
        renderer.enqueue(sampleBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onFailure(error.localizedDescription)
    }
}
