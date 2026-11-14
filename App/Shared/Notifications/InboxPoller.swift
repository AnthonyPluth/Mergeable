import Foundation
import MergeableCore

// MARK: dependencies (protocols so tests never touch the network, disk or UserNotifications)

/// The two GitHub reads the poller needs. `GitHubClient` conforms.
protocol InboxSource: Sendable {
    func inbox(for account: Account) async throws -> InboxSnapshot
    func status(_ key: PRKey, as account: AccountID) async throws -> PRStatus
}
extension GitHubClient: InboxSource {}

protocol AlertSink: Sendable {
    func post(_ alerts: [LocalAlert]) async
}

/// What the poller remembers per PAT account between runs. Kept on this device only: restoring it from iCloud after a
/// reinstall would replay stale differences as alerts (Review Focus 4).
struct PollState: Codable, Equatable {
    var snapshot: InboxSnapshot?
    var notifiedReady: Set<String> = []
}
extension InboxSnapshot: Equatable {
    public static func == (a: InboxSnapshot, b: InboxSnapshot) -> Bool { a.sections == b.sections }
}

protocol PollStateStore: Sendable {
    func load(_ account: AccountID) -> PollState?
    func save(_ state: PollState, for account: AccountID)
    func remove(_ account: AccountID)
}

/// One JSON file per account under a directory (Application Support/Mergeable/poll by default).
struct FilePollStateStore: PollStateStore {
    let directory: URL

    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Mergeable", isDirectory: true).appendingPathComponent("poll", isDirectory: true)
    }

    init(directory: URL = FilePollStateStore.defaultDirectory) { self.directory = directory }

    private func file(_ id: AccountID) -> URL {
        let safe = id.rawValue.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? String($0) : "_" }.joined()
        return directory.appendingPathComponent("\(safe).json")
    }

    func load(_ account: AccountID) -> PollState? {
        guard let d = try? Data(contentsOf: file(account)) else { return nil }
        return try? JSONDecoder().decode(PollState.self, from: d)
    }

    func save(_ state: PollState, for account: AccountID) {
        guard let d = try? JSONEncoder().encode(state) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? d.write(to: file(account), options: .atomic)
    }

    func remove(_ account: AccountID) { try? FileManager.default.removeItem(at: file(account)) }
}

final class MemoryPollStateStore: PollStateStore, @unchecked Sendable {
    private let lock = NSLock()
    private var states: [AccountID: PollState] = [:]
    func load(_ account: AccountID) -> PollState? { lock.lock(); defer { lock.unlock() }; return states[account] }
    func save(_ state: PollState, for account: AccountID) { lock.lock(); defer { lock.unlock() }; states[account] = state }
    func remove(_ account: AccountID) { lock.lock(); defer { lock.unlock() }; states[account] = nil }
}

/// Per-account "show alerts" switch for polled accounts. On by default; per device.
protocol AlertToggles: Sendable {
    func isEnabled(_ account: AccountID) -> Bool
    func setEnabled(_ on: Bool, for account: AccountID)
}

final class UserDefaultsAlertToggles: AlertToggles, @unchecked Sendable {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    private func key(_ a: AccountID) -> String { "alerts.disabled.\(a.rawValue)" }
    func isEnabled(_ account: AccountID) -> Bool { !defaults.bool(forKey: key(account)) }
    func setEnabled(_ on: Bool, for account: AccountID) { defaults.set(!on, forKey: key(account)) }
}

final class MemoryAlertToggles: AlertToggles, @unchecked Sendable {
    private let lock = NSLock()
    private var off: Set<AccountID> = []
    func isEnabled(_ account: AccountID) -> Bool { lock.lock(); defer { lock.unlock() }; return !off.contains(account) }
    func setEnabled(_ on: Bool, for account: AccountID) {
        lock.lock(); defer { lock.unlock() }
        if on { off.remove(account) } else { off.insert(account) }
    }
}

// MARK: poller

/// What one account's poll produced, for the inbox screen.
struct AccountPoll {
    var snapshot: InboxSnapshot?
    var error: String?
}

/// Fetches every account's inbox, and for PAT accounts compares it with the last run and posts local alerts.
///
/// - GitHub App accounts get push from the relay, so they are fetched for the screen only: no state, no alerts.
/// - The first run for an account is a baseline: it stores the snapshot and already-ready PRs and alerts nothing.
/// - If a fetch fails, nothing is stored for that account, so a later success compares against the last good snapshot.
/// - Polls never overlap: a call made while one is running waits for it and returns its result, so a foreground
///   refresh racing a background run cannot alert twice. State is read from the store on every run, because iOS
///   background runs start in a fresh process.
actor InboxPoller {
    static let interval: TimeInterval = 900

    private let source: InboxSource
    private let store: PollStateStore
    private let toggles: AlertToggles
    private let sink: AlertSink
    private var running: Task<[AccountID: AccountPoll], Never>?

    init(source: InboxSource, store: PollStateStore, toggles: AlertToggles, sink: AlertSink) {
        self.source = source; self.store = store; self.toggles = toggles; self.sink = sink
    }

    func poll(accounts: [Account]) async -> [AccountID: AccountPoll] {
        if let running { return await running.value }
        let task = Task { await self.run(accounts) }
        running = task
        let result = await task.value
        running = nil
        return result
    }

    private func run(_ accounts: [Account]) async -> [AccountID: AccountPoll] {
        var out: [AccountID: AccountPoll] = [:]
        await withTaskGroup(of: (AccountID, AccountPoll).self) { group in
            for account in accounts {
                group.addTask { (account.id, await self.process(account)) }
            }
            for await (id, result) in group { out[id] = result }
        }
        return out
    }

    nonisolated private func process(_ account: Account) async -> AccountPoll {
        let current: InboxSnapshot
        do { current = try await source.inbox(for: account) }
        catch GitHubError.unauthorized { return AccountPoll(snapshot: nil, error: "Token stopped working") }
        catch { return AccountPoll(snapshot: nil, error: error.localizedDescription) }

        guard account.connection == .pat else { return AccountPoll(snapshot: current, error: nil) }

        let saved = store.load(account.id)
        var notified = saved?.notifiedReady ?? []
        var closed: [PRKey: ClosedOutcome] = [:]
        if let previous = saved?.snapshot {
            let now = Self.keys(current)
            for key in Self.keys(previous).subtracting(now) {
                // Gone from the inbox is not the same as closed: ask. If it is still open, or the call fails, say nothing.
                guard let status = try? await source.status(key, as: account.id), status.state != .open else { continue }
                closed[key] = ClosedOutcome(merged: status.state == .merged, by: nil)
            }
        }

        let events = ChangeDetector(selfLogin: account.login)
            .events(previous: saved?.snapshot, current: current, closed: closed, notifiedReady: &notified)
        if !closed.isEmpty {
            let gone = Set(closed.keys.map { "\($0.owner)/\($0.repo)#\($0.number)@" })
            notified = notified.filter { k in !gone.contains { k.hasPrefix($0) } }
        }
        store.save(PollState(snapshot: current, notifiedReady: notified), for: account.id)

        // The detector and the saved state run even with alerts off, so turning them on later doesn't replay history.
        if toggles.isEnabled(account.id), !events.isEmpty {
            await sink.post(events.map(LocalAlert.init(event:)))
        }
        return AccountPoll(snapshot: current, error: nil)
    }

    nonisolated static func keys(_ s: InboxSnapshot) -> Set<PRKey> {
        Set(s.sections.values.flatMap { $0 }.map(\.key))
    }
}
