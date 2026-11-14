import Foundation

/// Per-device storage for things that must not sync (the refresh log).
final class UserDefaultsKeyValueStore: KeyValueStore {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func data(forKey key: String) -> Data? { defaults.data(forKey: key) }
    func set(_ data: Data?, forKey key: String) { defaults.set(data, forKey: key) }
}

enum RefreshSource: String, Codable, Equatable {
    case background, timer, foreground
}

struct RefreshEntry: Codable, Equatable, Identifiable {
    var date: Date
    var source: RefreshSource
    var id: Date { date }
}

/// When each refresh ran and why, newest first, kept for Settings, Diagnostics. Task 15 reads it to see how often
/// iOS really runs the background task.
final class RefreshLog {
    static let storageKey = "refresh.log.v1"
    static let limit = 60

    private let kv: KeyValueStore
    private(set) var entries: [RefreshEntry]

    init(store: KeyValueStore) {
        kv = store
        entries = store.data(forKey: Self.storageKey).flatMap { try? JSONDecoder().decode([RefreshEntry].self, from: $0) } ?? []
    }

    func record(_ source: RefreshSource, at date: Date = Date()) {
        entries.insert(RefreshEntry(date: date, source: source), at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
        kv.set(try? JSONEncoder().encode(entries), forKey: Self.storageKey)
    }
}
