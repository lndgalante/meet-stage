import Foundation

/// Saved demos, any number per app, the one each app last had open, and
/// unsent prompt drafts. Each demo is encoded on its own so one unreadable
/// entry never drops the others.
struct DemoLibrary {
    static let key = "demo.library.v2"
    static let promptsKey = "demo.prompts.v2"
    static let selectionKey = "demo.selection.v2"

    private let defaults: UserDefaults
    private var demos: [RealTimeDemo]
    private var prompts: [String: String]
    /// App key to the ID of the demo it last had open, or `newDemo`.
    private var selection: [String: String]
    /// Marks an app that was writing a new demo, so it reopens on the request field.
    private static let newDemo = "new"

    init(defaults: UserDefaults) {
        self.defaults = defaults
        let decoder = JSONDecoder()
        demos = (defaults.array(forKey: Self.key) as? [Data] ?? []).compactMap { data in
            do {
                return try decoder.decode(RealTimeDemo.self, from: data)
            } catch {
                AppLog.demoMode.error(
                    "Skipped an unreadable saved demo: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        prompts = defaults.dictionary(forKey: Self.promptsKey) as? [String: String] ?? [:]
        selection = defaults.dictionary(forKey: Self.selectionKey) as? [String: String] ?? [:]
    }

    /// This app's demos in the order they were made.
    func demos(for source: DemoSource) -> [RealTimeDemo] {
        demos.filter { $0.app.matches(source) }
    }

    /// The demo this app last had open, else its newest; nil while it's writing a new one.
    func demo(for source: DemoSource) -> RealTimeDemo? {
        let selected = selection[Self.appKey(source)]
        guard selected != Self.newDemo else { return nil }
        let mine = demos(for: source)
        return mine.first { $0.id.uuidString == selected } ?? mine.last
    }

    func demo(id: UUID) -> RealTimeDemo? {
        demos.first { $0.id == id }
    }

    func prompt(for source: DemoSource) -> String {
        prompts[Self.appKey(source)] ?? ""
    }

    /// Replaces the demo with the same ID in place, or adds it.
    mutating func save(_ demo: RealTimeDemo) {
        if let index = demos.firstIndex(where: { $0.id == demo.id }) {
            demos[index] = demo
        } else {
            demos.append(demo)
        }
        persist()
    }

    /// Remembers the demo an app has open; nil falls back to its newest.
    mutating func select(_ id: UUID?, for source: DemoSource) {
        setSelection(id?.uuidString, for: source)
    }

    mutating func selectNewDemo(for source: DemoSource) {
        setSelection(Self.newDemo, for: source)
    }

    private mutating func setSelection(_ value: String?, for source: DemoSource) {
        let key = Self.appKey(source)
        guard selection[key] != value else { return }
        selection[key] = value
        defaults.set(selection, forKey: Self.selectionKey)
    }

    mutating func remove(id: UUID) {
        demos.removeAll { $0.id == id }
        persist()
    }

    mutating func savePrompt(_ prompt: String, for source: DemoSource) {
        let key = Self.appKey(source)
        guard prompts[key] != prompt else { return }
        prompts[key] = prompt.isEmpty ? nil : prompt
        defaults.set(prompts, forKey: Self.promptsKey)
    }

    private func persist() {
        let encoder = JSONEncoder()
        defaults.set(demos.compactMap { try? encoder.encode($0) }, forKey: Self.key)
    }

    /// Names an app across launches: its bundle ID, or its name when it has none.
    static func appKey(_ source: DemoSource) -> String {
        source.bundleID.isEmpty ? "name:\(source.name)" : source.bundleID
    }
}
