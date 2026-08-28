import AVFoundation
import Foundation
import Speech

/// One partial or finalized transcription result.
struct DemoTranscriptSegment: Sendable, Equatable {
    let text: String
    /// Volatile segments are tentative and are replaced as more audio arrives;
    /// only finalized segments should drive actions.
    let isFinal: Bool
}

enum DemoSpeechError: Error {
    case microphoneDenied
    case localeUnsupported
    case noCompatibleAudioFormat
}

/// Abstracts the live transcription source so the Demo Mode coordinator can be
/// exercised without the microphone or on-device speech models.
@MainActor
protocol DemoSpeechListening: AnyObject {
    func start(onSegment: @escaping @MainActor (DemoTranscriptSegment) -> Void) async throws
    func stop() async
}

/// Live, on-device narration transcription built on the macOS 26 SpeechAnalyzer
/// pipeline. Microphone audio is transcribed entirely on device; nothing is
/// sent to a network service.
@MainActor
final class DemoSpeechTranscriber: DemoSpeechListening {
    private let locale: Locale
    private let audioEngine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var isRunning = false
    /// Set by `stop()` so an in-flight `start()` unwinds instead of arming the
    /// microphone after teardown.
    private var isStopped = false

    init(locale: Locale = .current) {
        self.locale = locale
    }

    /// Current microphone authorization without prompting.
    static var microphoneAuthorization: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    /// Drives the permission-warning badge on the Demo Mode control.
    static var isMicrophoneAuthorized: Bool {
        microphoneAuthorization == .authorized
    }

    static var isMicrophoneDenied: Bool {
        switch microphoneAuthorization {
        case .denied, .restricted: true
        default: false
        }
    }

    @discardableResult
    static func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    func start(onSegment: @escaping @MainActor (DemoTranscriptSegment) -> Void) async throws {
        guard !isRunning else { return }
        isStopped = false
        guard await Self.requestMicrophoneAccess() else {
            throw DemoSpeechError.microphoneDenied
        }
        try checkNotStopped()

        guard let resolvedLocale = await resolveSupportedLocale() else {
            throw DemoSpeechError.localeUnsupported
        }
        AppLog.demoMode.notice(
            "Demo Mode transcribing in \(resolvedLocale.identifier(.bcp47), privacy: .public)"
        )

        let transcriber = SpeechTranscriber(
            locale: resolvedLocale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: []
        )
        self.transcriber = transcriber

        try await ensureModel(for: transcriber, locale: resolvedLocale)
        try checkNotStopped()

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        let inputFormat = audioEngine.inputNode.outputFormat(forBus: 0)
        guard
            let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
                compatibleWith: [transcriber]
            )
        else {
            throw DemoSpeechError.noCompatibleAudioFormat
        }
        try checkNotStopped()

        resultsTask = Task {
            do {
                for try await result in transcriber.results {
                    let segment = DemoTranscriptSegment(
                        text: String(result.text.characters),
                        isFinal: result.isFinal
                    )
                    guard !Task.isCancelled else { return }
                    onSegment(segment)
                }
            } catch {
                AppLog.demoMode.error(
                    "Transcription stream ended: \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        let (inputSequence, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        inputContinuation = continuation

        let converter = DemoAudioConverter(outputFormat: analyzerFormat)
        // The tap runs on AVAudioEngine's realtime audio thread. Mark it
        // `@Sendable` so it is nonisolated; without this the compiler infers the
        // enclosing @MainActor isolation and Swift 6 traps with an isolation
        // assertion the moment audio flows. Captures are Sendable (the converter
        // is @unchecked Sendable, the continuation is Sendable).
        audioEngine.inputNode.installTap(
            onBus: 0,
            bufferSize: 4_096,
            format: inputFormat
        ) { @Sendable buffer, _ in
            if let converted = converter.convert(buffer) {
                continuation.yield(AnalyzerInput(buffer: converted))
            }
        }
        try checkNotStopped()
        audioEngine.prepare()
        try audioEngine.start()

        try await analyzer.start(inputSequence: inputSequence)
        // A stop() could have interleaved during the await above; do not mark a
        // torn-down session as running.
        guard !isStopped, !Task.isCancelled else {
            await stop()
            throw CancellationError()
        }
        isRunning = true
        AppLog.demoMode.notice("Demo Mode is listening")
    }

    private func checkNotStopped() throws {
        if isStopped || Task.isCancelled {
            throw CancellationError()
        }
    }

    /// Tears down unconditionally so a partially-started session (for example if
    /// `start` threw after installing the tap) is still fully cleaned up.
    func stop() async {
        isStopped = true
        isRunning = false

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        inputContinuation?.finish()
        inputContinuation = nil

        // Cancel the results consumer before finalizing so teardown never
        // delivers a late segment from the previous session.
        resultsTask?.cancel()
        resultsTask = nil

        if let analyzer {
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
        }
        analyzer = nil
        transcriber = nil
    }

    /// Picks a locale the transcriber actually supports: the exact match, then
    /// Apple's equivalence, then any regional variant of the same language, then
    /// English (whose model is the most commonly pre-installed). This is what
    /// makes Demo Mode work for region tags like `en-AR` or `es-419` that never
    /// appear verbatim in the supported list.
    private func resolveSupportedLocale() async -> Locale? {
        let supported = await SpeechTranscriber.supportedLocales
        guard !supported.isEmpty else { return nil }

        let requestedTag = locale.identifier(.bcp47)
        if let exact = supported.first(where: { $0.identifier(.bcp47) == requestedTag }) {
            return exact
        }
        if let equivalent = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            return equivalent
        }
        if let language = locale.language.languageCode?.identifier,
            let sameLanguage = supported.first(where: {
                $0.language.languageCode?.identifier == language
            })
        {
            return sameLanguage
        }
        if let english = supported.first(where: {
            $0.language.languageCode?.identifier == "en"
        }) {
            return english
        }
        return supported.first
    }

    private func ensureModel(for transcriber: SpeechTranscriber, locale: Locale) async throws {
        let tag = locale.identifier(.bcp47)
        let installed = await SpeechTranscriber.installedLocales
        if installed.contains(where: { $0.identifier(.bcp47) == tag }) {
            return
        }

        if let request = try await AssetInventory.assetInstallationRequest(
            supporting: [transcriber]
        ) {
            AppLog.demoMode.notice("Downloading speech model for \(tag, privacy: .public)")
            try await request.downloadAndInstall()
        }
    }
}

/// Converts microphone tap buffers to the analyzer's format on the audio
/// thread. `@unchecked Sendable` is sound because AVAudioEngine invokes the tap
/// serially on one internal queue and this object is touched only there.
private final class DemoAudioConverter: @unchecked Sendable {
    private let outputFormat: AVAudioFormat
    private var converter: AVAudioConverter?

    // The converter input block is `@Sendable`, so its per-call state lives on
    // this instance rather than as captured local vars. AVAudioEngine invokes
    // the tap (and therefore `convert`) serially on one audio thread.
    private var pendingInput: AVAudioPCMBuffer?
    private var didProvidePendingInput = false

    init(outputFormat: AVAudioFormat) {
        self.outputFormat = outputFormat
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard buffer.format != outputFormat else { return buffer }

        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: outputFormat)
            converter?.primeMethod = .none
        }
        guard let converter else { return nil }

        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
        guard
            capacity > 0,
            let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity)
        else { return nil }

        pendingInput = buffer
        didProvidePendingInput = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { [self] _, inputStatus in
            if didProvidePendingInput {
                inputStatus.pointee = .noDataNow
                return nil
            }
            didProvidePendingInput = true
            inputStatus.pointee = .haveData
            return pendingInput
        }
        pendingInput = nil
        return status == .error ? nil : output
    }
}
