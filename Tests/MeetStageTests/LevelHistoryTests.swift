import Foundation
import Testing

@testable import MeetStage

@Suite("Microphone level")
@MainActor
struct LevelHistoryTests {
    /// The RMS of a signal at `decibels` below full scale.
    private func rms(_ decibels: Float) -> Float { pow(10, decibels / 20) }

    @Test("Loudness maps from −55 dBFS (0) to −12 dBFS (1)")
    func decibelScale() {
        #expect(abs(LevelMeter.level(rms: rms(-55))) < 0.0001)
        #expect(abs(LevelMeter.level(rms: rms(-12)) - 1) < 0.0001)
        #expect(abs(LevelMeter.level(rms: rms(-33.5)) - 0.5) < 0.0001)
        #expect(LevelMeter.level(rms: 0) == 0)
        #expect(LevelMeter.level(rms: 1) == 1)
    }

    @Test("One level per twentieth of a second of audio, whatever the buffer size")
    func twentyPerSecond() {
        let meter = LevelMeter(sampleRate: 48_000)
        let samples = [Float](repeating: rms(-33.5), count: 4_800)
        var levels: [Float] = []
        samples.withUnsafeBufferPointer { buffer in
            meter.consume(buffer.baseAddress!, frames: 4_800) { levels.append($0) }
        }
        #expect(levels.count == 2)
        #expect(levels.allSatisfy { abs($0 - 0.5) < 0.001 })

        // Small buffers add up to the same window.
        levels = []
        samples.withUnsafeBufferPointer { buffer in
            meter.consume(buffer.baseAddress!, frames: 1_000) { levels.append($0) }
            #expect(levels.isEmpty)
            meter.consume(buffer.baseAddress!, frames: 1_400) { levels.append($0) }
        }
        #expect(levels.count == 1)
    }

    @Test("A drop releases softly instead of snapping to silence")
    func softRelease() {
        let history = LevelHistory()
        history.append(1)
        history.append(0)
        #expect(abs((history.samples.last ?? 0) - 0.6) < 0.0001)
        history.append(0)
        #expect(abs((history.samples.last ?? 0) - 0.36) < 0.0001)
        history.append(0.8)
        #expect(history.samples.last == 0.8)
        #expect(history.samples.count == LevelHistory.capacity)
    }

    @Test("Reset clears every level, and the listener's test hook feeds the history")
    func reset() {
        let history = LevelHistory()
        history.append(0.7)
        history.reset()
        #expect(history.samples == [Float](repeating: 0, count: LevelHistory.capacity))

        let listener = SpeechListener()
        listener.simulateListening(levels: [0.2, 0.9])
        #expect(listener.isListening)
        #expect(listener.wantsToListen)
        #expect(listener.levels.samples.suffix(2) == [0.2, 0.9])
        listener.stop()
        #expect(listener.levels.samples.allSatisfy { $0 == 0 })
        listener.simulateState(.unavailable("No microphone is available."))
        #expect(!listener.wantsToListen)
    }
}
