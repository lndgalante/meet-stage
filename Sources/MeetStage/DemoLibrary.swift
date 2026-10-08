import Foundation

/// Saved demos, one per app, plus unsent prompt drafts. Each demo is encoded
/// on its own so one unreadable entry never drops the others.
struct DemoLibrary {
    static let key = "demo.library.v2"
    static let promptsKey = "demo.prompts.v2"

    private let defaults: UserDefaults
    private var demos: [RealTimeDemo]
    private var prompts: [String: String]

    init(defaults: UserDefaults) {
        self.defaults = defaults
        let decoder = JSONDecoder()
        demos = (defaults.array(forKey: Self.key) as? [Data] ?? []).compactMap { data in
            do {
                return try decoder.decode(RealTimeDemo.self, from: data)
            } catch {
                AppLog.demoMode.error("Skipped an unreadable saved demo: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        prompts = defaults.dictionary(forKey: Self.promptsKey) as? [String: String] ?? [:]
    }

    func demo(for source: DemoSource) -> RealTimeDemo? {
        demos.first { $0.app.matches(source) }
    }

    func prompt(for source: DemoSource) -> String {
        prompts[Self.appKey(source)] ?? ""
    }

    mutating func save(_ demo: RealTimeDemo) {
        demos.removeAll { $0.app == demo.app || $0.id == demo.id }
        demos.append(demo)
        persist()
    }

    /// Saves only when nobody changed the demo since `revision`.
    mutating func update(_ demo: RealTimeDemo, ifRevision revision: Int) -> Bool {
        guard let current = demos.first(where: { $0.id == demo.id }), current.revision == revision else { return false }
        save(demo)
        return true
    }

    mutating func savePrompt(_ prompt: String, for source: DemoSource) {
        let key = Self.appKey(source)
        guard prompts[key] != prompt else { return }
        prompts[key] = prompt.isEmpty ? nil : prompt
        defaults.set(prompts, forKey: Self.promptsKey)
    }

    mutating func remove(for source: DemoSource) {
        demos.removeAll { $0.app.matches(source) }
        persist()
    }

    private func persist() {
        let encoder = JSONEncoder()
        defaults.set(demos.compactMap { try? encoder.encode($0) }, forKey: Self.key)
    }

    private static func appKey(_ source: DemoSource) -> String {
        source.bundleID.isEmpty ? "name:\(source.name)" : source.bundleID
    }
}
