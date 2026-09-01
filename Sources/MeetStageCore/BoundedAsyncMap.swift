/// Runs an asynchronous transform with a fixed upper bound on in-flight child
/// tasks while preserving input order in the returned results.
public enum BoundedAsyncMap {
    public static func map<Input: Sendable, Output: Sendable>(
        _ inputs: [Input],
        maximumConcurrent: Int,
        operation: @escaping @Sendable (Input) async -> Output
    ) async -> [Output] {
        guard !inputs.isEmpty else { return [] }
        let limit = max(1, maximumConcurrent)

        return await withTaskGroup(of: IndexedResult<Output>.self) { group in
            var nextIndex = 0
            var orderedResults = Array<Output?>(repeating: nil, count: inputs.count)

            func submit(_ index: Int) {
                let input = inputs[index]
                group.addTask {
                    IndexedResult(index: index, output: await operation(input))
                }
            }

            for index in 0..<min(limit, inputs.count) {
                submit(index)
                nextIndex += 1
            }

            while let result = await group.next() {
                orderedResults[result.index] = result.output
                if nextIndex < inputs.count {
                    submit(nextIndex)
                    nextIndex += 1
                }
            }

            return orderedResults.compactMap { $0 }
        }
    }
}

private struct IndexedResult<Output: Sendable>: Sendable {
    let index: Int
    let output: Output
}
