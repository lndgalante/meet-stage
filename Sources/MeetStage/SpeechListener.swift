import AVFoundation
import CoreMedia
import NaturalLanguage
import Speech

/// Live, on-device transcription of the presenter's microphone for the
/// teleprompter. Audio and text never leave the Mac and nothing is stored.
@MainActor
final class SpeechListener: ObservableObject {
    enum State: Equatable {
        case off
        case preparing(String)
        case listening
        case unavailable(String)

        var isPreparing: Bool {
            if case .preparing = self { true } else { false }
        }
    }

    @Published private(set) var state: State = .off
    /// Input loudness, 0…1, for the listening indicator.
    @Published private(set) var level: Float = 0
    /// Recent words heard, most recent last.
    private(set) var transcriptWords: [String] = []
    /// Words dropped from the front of `transcriptWords`, so positions stay
    /// comparable across trimming and restarts.
    private(set) var droppedWords = 0
    /// The language being recognized, for the status text.
    private(set) var language: String?
    /// When the recognizer last reported speech, to notice a natural pause.
    private(set) var lastHeard = Date.distantPast
    var onTranscript: (() -> Void)?

    private var engine: AVAudioEngine?
    private var analyzer: SpeechAnalyzer?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var configurationObserver: NSObjectProtocol?
    private var finalizedWords: [String] = []
    private var generation = 0
    private var lastRequest: (vocabulary: [String], script: String) = ([], "")

    var isListening: Bool { state == .listening }
    /// The presenter wants to be followed: listening, starting, or reconnecting.
    /// The demo waits for their voice the whole time rather than falling back to a timer.
    private(set) var wantsToListen = false
    private var lastRestart = Date.distantPast

    /// Bumped by every request and by stop(), so a start that was overtaken never
    /// turns the microphone on (say, after the demo already finished).
    private var requestToken = 0

    /// Starts listening without waiting, so callers can rely on `wantsToListen` at once.
    func requestStart(vocabulary: [String], script: String) {
        requestToken += 1
        let token = requestToken
        wantsToListen = true
        Task { await start(vocabulary: vocabulary, script: script, token: token) }
    }

    /// Total words heard so far, including trimmed ones.
    var totalWords: Int { droppedWords + transcriptWords.count }

    /// The words heard since position `start` (from `totalWords`).
    func words(since start: Int) -> ArraySlice<String> {
        let index = max(0, start - droppedWords)
        return index < transcriptWords.count ? transcriptWords[index...] : []
    }

    /// Asks for the microphone and downloads the speech model ahead of time,
    /// so neither happens in front of an audience. Doesn't start listening.
    func prepare(script: String) async {
        guard state == .off else { return }
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
        guard SpeechTranscriber.isAvailable, state == .off else { return }
        let transcriber = SpeechTranscriber(
            locale: await Self.locale(for: script), transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults], attributeOptions: [])
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
        } catch {
            AppLog.demoMode.error("Speech model download failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func start(vocabulary: [String], script: String, token: Int) async {
        guard token == requestToken, wantsToListen else { return }
        switch state {
        case .listening, .preparing: return
        case .off, .unavailable: break
        }
        generation += 1
        let run = generation
        lastRequest = (vocabulary, script)
        state = .preparing("Getting the microphone ready")
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        guard run == generation else { return }
        guard granted else {
            wantsToListen = false
            state = .unavailable("Allow the microphone for BetterMeets in System Settings → Privacy & Security.")
            return
        }
        guard SpeechTranscriber.isAvailable else {
            wantsToListen = false
            state = .unavailable("On-device speech recognition isn’t available on this Mac.")
            return
        }
        let locale = await Self.locale(for: script)
        guard run == generation else { return }
        language = locale.localizedString(forIdentifier: locale.identifier)
        let transcriber = SpeechTranscriber(
            locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: [])
        var startedAnalyzer: SpeechAnalyzer?
        var startedContinuation: AsyncStream<AnalyzerInput>.Continuation?
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                guard run == generation else { return }
                state = .preparing("Downloading the speech model")
                try await request.downloadAndInstall()
            }
            guard run == generation else { return }
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let context = AnalysisContext()
            context.contextualStrings[.general] = Array(vocabulary.prefix(100))
            try await analyzer.setContext(context)
            guard run == generation else { return }
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                if run == generation {
                    wantsToListen = false
                    state = .unavailable("Couldn’t start speech recognition.")
                }
                return
            }
            let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingNewest(64))
            startedAnalyzer = analyzer
            startedContinuation = continuation
            try await analyzer.start(inputSequence: stream)
            guard run == generation else {
                continuation.finish()
                await analyzer.cancelAndFinishNow()
                return
            }

            let engine = AVAudioEngine()
            let input = engine.inputNode
            let inputFormat = input.outputFormat(forBus: 0)
            guard inputFormat.sampleRate > 0 else {
                continuation.finish()
                await analyzer.cancelAndFinishNow()
                // Unavailable means timed holds, never waiting on a voice that can't be heard.
                wantsToListen = false
                state = .unavailable("No microphone is available.")
                return
            }
            input.installTap(
                onBus: 0, bufferSize: 2_048, format: inputFormat,
                block: Self.makeTap(from: inputFormat, to: format, continuation: continuation) { [weak self] level in
                    Task { @MainActor in self?.level = level }
                })
            engine.prepare()
            try engine.start()

            self.engine = engine
            self.analyzer = analyzer
            self.continuation = continuation
            droppedWords += transcriptWords.count
            transcriptWords = []
            finalizedWords = []
            state = .listening
            // A new microphone (AirPods, a headset) stops the engine; listen again on the new one.
            configurationObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.restart() }
            }
            resultsTask = Task { [weak self] in
                do {
                    for try await result in transcriber.results {
                        guard let self, run == self.generation else { return }
                        let text = String(result.text.characters)
                        let isFinal = CMTimeCompare(result.range.end, result.resultsFinalizationTime) <= 0
                        self.receive(text, isFinal: isFinal)
                    }
                } catch {
                    AppLog.demoMode.error("Speech results ended: \(error.localizedDescription, privacy: .public)")
                }
                // The recognizer stopped on its own: say so instead of waiting for words that won't come.
                guard let self, run == self.generation else { return }
                self.stop()
                self.state = .unavailable("Speech recognition stopped. Turn Follow my voice off and on to retry.")
            }
        } catch {
            AppLog.demoMode.error("Speech recognition failed to start: \(error.localizedDescription, privacy: .public)")
            startedContinuation?.finish()
            if let startedAnalyzer { await startedAnalyzer.cancelAndFinishNow() }
            guard run == generation else { return }
            wantsToListen = false
            state = .unavailable("Couldn’t start speech recognition.")
        }
    }

    func stop() {
        wantsToListen = false
        requestToken += 1
        tearDown()
        state = .off
    }

    /// Releases the microphone and recognizer without changing what the presenter wants.
    private func tearDown() {
        generation += 1
        resultsTask?.cancel()
        resultsTask = nil
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        continuation?.finish()
        continuation = nil
        if let analyzer {
            Task { await analyzer.cancelAndFinishNow() }
        }
        analyzer = nil
        level = 0
    }

    /// The audio input changed (a new device, or another app reconfiguring the
    /// microphone). Reconnect without ever looking "off" to the prompter.
    private func restart() {
        guard state == .listening, Date().timeIntervalSince(lastRestart) > 2 else { return }
        lastRestart = Date()
        AppLog.demoMode.info("Audio input changed; restarting speech recognition")
        let request = lastRequest
        let token = requestToken
        tearDown()
        state = .off
        Task { await start(vocabulary: request.vocabulary, script: request.script, token: token) }
    }

    private func receive(_ text: String, isFinal: Bool) {
        lastHeard = Date()
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        if isFinal {
            finalizedWords.append(contentsOf: words)
            if finalizedWords.count > 400 {
                let extra = finalizedWords.count - 400
                finalizedWords.removeFirst(extra)
                droppedWords += extra
            }
            transcriptWords = finalizedWords
        } else {
            transcriptWords = finalizedWords + words
        }
        onTranscript?()
    }

    #if DEBUG
        /// Test hook: behave as if listening and hearing `text`.
        func simulateHearing(_ text: String, isFinal: Bool = false) {
            wantsToListen = true
            receive(text, isFinal: isFinal)
        }
    #endif

    /// Recognizes the language the script is written in, which can differ from
    /// the Mac's (a Spanish Mac presenting in English).
    private static func locale(for script: String) async -> Locale {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(script)
        if let language = recognizer.dominantLanguage, script.split(separator: " ").count >= 6,
            let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language.rawValue))
        {
            return locale
        }
        return await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) ?? Locale(identifier: "en-US")
    }

    /// The audio tap runs on a real-time audio thread, so it is built outside
    /// the main actor and only touches Sendable values.
    nonisolated private static func makeTap(
        from inputFormat: AVAudioFormat, to format: AVAudioFormat,
        continuation: AsyncStream<AnalyzerInput>.Continuation, level: @escaping @Sendable (Float) -> Void
    ) -> AVAudioNodeTapBlock {
        let converter = UncheckedBox(AVAudioConverter(from: inputFormat, to: format))
        let meter = UncheckedBox(LevelThrottle())
        return { buffer, _ in
            if let samples = buffer.floatChannelData?[0], buffer.frameLength > 0, meter.value.shouldReport() {
                var sum: Float = 0
                for index in 0..<Int(buffer.frameLength) { sum += samples[index] * samples[index] }
                let rms = (sum / Float(buffer.frameLength)).squareRoot()
                level(min(1, rms * 12))
            }
            guard let converter = converter.value else { return }
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * format.sampleRate / inputFormat.sampleRate) + 32
            guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
            var supplied = false
            var error: NSError?
            converter.convert(to: output, error: &error) { _, status in
                if supplied {
                    status.pointee = .noDataNow
                    return nil
                }
                supplied = true
                status.pointee = .haveData
                return buffer
            }
            if error == nil, output.frameLength > 0 {
                continuation.yield(AnalyzerInput(buffer: output))
            }
        }
    }
}

/// Reports the input level about ten times a second, not on every buffer.
private final class LevelThrottle {
    private var last = ContinuousClock.now
    func shouldReport() -> Bool {
        let now = ContinuousClock.now
        guard now - last >= .milliseconds(90) else { return false }
        last = now
        return true
    }
}

/// Carries a non-Sendable value that is only ever used from one thread.
private final class UncheckedBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
