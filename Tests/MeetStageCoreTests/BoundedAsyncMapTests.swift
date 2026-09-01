import Testing
@testable import MeetStageCore

@Suite("Bounded asynchronous map")
struct BoundedAsyncMapTests {
    @Test("Bounds concurrent work and preserves input order")
    func boundsWorkAndPreservesOrder() async {
        let probe = ConcurrencyProbe()
        let results = await BoundedAsyncMap.map(
            Array(0..<12),
            maximumConcurrent: 3
        ) { value in
            await probe.begin()
            try? await Task.sleep(for: .milliseconds(5))
            await probe.end()
            return value * 2
        }

        #expect(results == Array(0..<12).map { $0 * 2 })
        #expect(await probe.maximumActive == 3)
    }
}

private actor ConcurrencyProbe {
    private var active = 0
    private(set) var maximumActive = 0

    func begin() {
        active += 1
        maximumActive = max(maximumActive, active)
    }

    func end() {
        active -= 1
    }
}
