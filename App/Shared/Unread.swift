import Foundation
import MergeableCore

/// What is synced between devices (through `NSUbiquitousKeyValueStore` in the app).
struct UnreadState: Codable, Equatable {
    /// Per account: everything last updated before this is read. Set the first time an account is seen, so a fresh
    /// install doesn't show the whole inbox as unread, and by "Mark all read".
    var accountMarkers: [String: Date] = [:]
    /// Per PR node ID: the PR's `updatedAt` when it was last opened.
    var openedAt: [String: Date] = [:]
}

/// Unread = a PR whose `updatedAt` is after the later of its account's marker and the time it was last opened.
/// Opening an item marks it read. State lives in a `KeyValueStore` so tests use memory and the app uses iCloud.
final class UnreadTracker {
    static let storageKey = "unread.v1"
    static let maxOpened = 2000

    private let kv: KeyValueStore
    private(set) var state: UnreadState

    init(store: KeyValueStore) {
        kv = store
        state = store.data(forKey: Self.storageKey).flatMap { try? JSONDecoder().decode(UnreadState.self, from: $0) } ?? UnreadState()
    }

    /// Picks up changes another device synced.
    func reload() {
        if let s = kv.data(forKey: Self.storageKey).flatMap({ try? JSONDecoder().decode(UnreadState.self, from: $0) }) { state = s }
    }

    func isUnread(_ pr: PullRequestSummary, account: AccountID) -> Bool {
        guard let marker = state.accountMarkers[account.rawValue] else { return false }
        let opened = state.openedAt[pr.nodeID] ?? .distantPast
        return pr.updatedAt > max(marker, opened)
    }

    /// Unread PRs in a snapshot, once each even if they appear in several sections.
    func unreadCount(_ snapshot: InboxSnapshot, account: AccountID) -> Int {
        var seen = Set<String>()
        var n = 0
        for section in InboxSection.allCases {
            for pr in snapshot.sections[section] ?? [] where seen.insert(pr.nodeID).inserted {
                if isUnread(pr, account: account) { n += 1 }
            }
        }
        return n
    }

    /// Sets the baseline for accounts seen for the first time.
    func ensureMarker(for account: AccountID, now: Date = Date()) {
        guard state.accountMarkers[account.rawValue] == nil else { return }
        state.accountMarkers[account.rawValue] = now
        save()
    }

    func markOpened(_ pr: PullRequestSummary) {
        if let existing = state.openedAt[pr.nodeID], existing >= pr.updatedAt { return }
        state.openedAt[pr.nodeID] = pr.updatedAt
        save()
    }

    func markAllRead(account: AccountID, now: Date = Date()) {
        state.accountMarkers[account.rawValue] = now
        save()
    }

    private func save() {
        if state.openedAt.count > Self.maxOpened {
            let newest = state.openedAt.sorted { $0.value > $1.value }.prefix(Self.maxOpened)
            state.openedAt = Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0.value) })
        }
        kv.set(try? JSONEncoder().encode(state), forKey: Self.storageKey)
    }
}
