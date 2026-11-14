import XCTest
import MergeableCore
@testable import Mergeable

private final class StubSource: InboxSource, @unchecked Sendable {
    private let lock = NSLock()
    private var _inboxes: [AccountID: InboxSnapshot] = [:]
    private var _statuses: [PRKey: PRStatus] = [:]
    private var _failing: Set<AccountID> = []
    private var _inboxCalls: [AccountID] = []
    private var _statusCalls: [PRKey] = []

    func set(_ s: InboxSnapshot, for a: AccountID) { lock.lock(); _inboxes[a] = s; lock.unlock() }
    func setStatus(_ s: PRStatus, for k: PRKey) { lock.lock(); _statuses[k] = s; lock.unlock() }
    func fail(_ a: AccountID, _ on: Bool) { lock.lock(); if on { _failing.insert(a) } else { _failing.remove(a) }; lock.unlock() }
    var inboxCalls: [AccountID] { lock.lock(); defer { lock.unlock() }; return _inboxCalls }
    var statusCalls: [PRKey] { lock.lock(); defer { lock.unlock() }; return _statusCalls }

    func inbox(for account: Account) async throws -> InboxSnapshot {
        let (failing, snap): (Bool, InboxSnapshot) = lock.withLock {
            _inboxCalls.append(account.id)
            return (_failing.contains(account.id), _inboxes[account.id] ?? InboxSnapshot())
        }
        if failing { throw GitHubError.http(500) }
        return snap
    }

    func status(_ key: PRKey, as account: AccountID) async throws -> PRStatus {
        let s: PRStatus? = lock.withLock { _statusCalls.append(key); return _statuses[key] }
        guard let s else { throw GitHubError.notFound }
        return s
    }
}

private final class RecordingSink: AlertSink, @unchecked Sendable {
    private let lock = NSLock()
    private var _alerts: [LocalAlert] = []
    var alerts: [LocalAlert] { lock.lock(); defer { lock.unlock() }; return _alerts }
    func post(_ alerts: [LocalAlert]) async { lock.withLock { _alerts += alerts } }
}

private let work = Account(id: AccountID("w"), login: "apluth-acme", label: "Work", color: .orange, connection: .pat, orgs: ["Acme"])
private let personal = Account(id: AccountID("p"), login: "AnthonyPluth", label: "Personal", color: .blue, connection: .githubApp)

private func pr(_ n: Int, author: String = "apluth-acme", head: String = "h1", rollup: CheckRollup? = .success, draft: Bool = false,
                state: PRState = .open) -> PullRequestSummary {
    PullRequestSummary(nodeID: "N\(n)", key: PRKey(owner: "acme", repo: "app", number: n), title: "Title \(n)", url: URL(string: "https://github.com/acme/app/pull/\(n)")!,
                       author: author, baseBranch: "main",
                       status: PRStatus(state: state, isDraft: draft, mergeable: .mergeable, rollup: rollup, headOid: head))
}

private func snap(yours: [PullRequestSummary] = [], needs: [PullRequestSummary] = []) -> InboxSnapshot {
    InboxSnapshot(sections: [.needsReview: needs, .yours: yours, .assignedOrMentioned: []])
}

final class InboxPollerTests: XCTestCase {
    private var source: StubSource!
    private var sink: RecordingSink!
    private var store: MemoryPollStateStore!
    private var toggles: MemoryAlertToggles!

    override func setUp() {
        source = StubSource(); sink = RecordingSink(); store = MemoryPollStateStore(); toggles = MemoryAlertToggles()
    }

    private func makePoller() -> InboxPoller { InboxPoller(source: source, store: store, toggles: toggles, sink: sink) }

    func testIntervalIsFifteenMinutes() { XCTAssertEqual(InboxPoller.interval, 900) }

    func testFirstRunIsABaselineAndSendsNothing() async {
        // A PR that is already merge-ready and one waiting for review: neither alerts after a fresh install.
        source.set(snap(yours: [pr(1)], needs: [pr(2, author: "bob", rollup: .pending)]), for: work.id)
        let result = await makePoller().poll(accounts: [work])
        XCTAssertTrue(sink.alerts.isEmpty)
        XCTAssertNotNil(result[work.id]?.snapshot)
        let saved = store.load(work.id)
        XCTAssertNotNil(saved?.snapshot)
        XCTAssertEqual(saved?.notifiedReady, ["acme/app#1@h1"])
    }

    func testSameReadyHeadAlertsOnceAcrossTwoPolls() async {
        source.set(snap(yours: [pr(1, rollup: .pending)]), for: work.id)
        _ = await makePoller().poll(accounts: [work])           // baseline
        source.set(snap(yours: [pr(1, rollup: .success)]), for: work.id)
        _ = await makePoller().poll(accounts: [work])           // checks went green: alert
        _ = await makePoller().poll(accounts: [work])           // same head again, new poller instance: nothing
        XCTAssertEqual(sink.alerts.map(\.title), ["Ready to merge"])
        XCTAssertEqual(sink.alerts.first?.subtitle, "acme/app #1")
        XCTAssertEqual(sink.alerts.first?.body, "Title 1")
        XCTAssertEqual(sink.alerts.first?.threadID, "acme/app#1")
        XCTAssertEqual(sink.alerts.first?.payload.kind, "mergeReady")
    }

    func testNewHeadAlertsAgain() async {
        source.set(snap(yours: [pr(1, rollup: .pending)]), for: work.id)
        let poller = makePoller()
        _ = await poller.poll(accounts: [work])
        source.set(snap(yours: [pr(1, head: "h1", rollup: .success)]), for: work.id)
        _ = await poller.poll(accounts: [work])
        source.set(snap(yours: [pr(1, head: "h2", rollup: .success)]), for: work.id)
        _ = await poller.poll(accounts: [work])
        XCTAssertEqual(sink.alerts.count, 2)
    }

    func testGitHubAppAccountsAreFetchedButNeverAlertedOrStored() async {
        source.set(snap(), for: personal.id)
        _ = await makePoller().poll(accounts: [personal])
        source.set(snap(needs: [pr(5, author: "bob")]), for: personal.id)
        let result = await makePoller().poll(accounts: [personal])
        XCTAssertEqual(source.inboxCalls, [personal.id, personal.id])
        XCTAssertNotNil(result[personal.id]?.snapshot)
        XCTAssertTrue(sink.alerts.isEmpty)
        XCTAssertNil(store.load(personal.id))
    }

    func testAlertsOffStillAdvancesStateSoTurningThemOnDoesNotReplay() async {
        toggles.setEnabled(false, for: work.id)
        source.set(snap(), for: work.id)
        _ = await makePoller().poll(accounts: [work])
        source.set(snap(needs: [pr(2, author: "bob")]), for: work.id)
        _ = await makePoller().poll(accounts: [work])
        XCTAssertTrue(sink.alerts.isEmpty)
        toggles.setEnabled(true, for: work.id)
        _ = await makePoller().poll(accounts: [work])
        XCTAssertTrue(sink.alerts.isEmpty)
    }

    func testFailedFetchKeepsLastSnapshotAndReportsError() async {
        source.set(snap(yours: [pr(1)]), for: work.id)
        let poller = makePoller()
        _ = await poller.poll(accounts: [work])
        source.fail(work.id, true)
        let result = await poller.poll(accounts: [work])
        XCTAssertNil(result[work.id]?.snapshot)
        XCTAssertNotNil(result[work.id]?.error)
        XCTAssertNotNil(store.load(work.id)?.snapshot)
        XCTAssertTrue(sink.alerts.isEmpty)
    }

    func testMergedPullRequestAsksForStatusAndAlertsWithMergedCopy() async {
        source.set(snap(needs: [pr(3, author: "bob", rollup: .pending)]), for: work.id)
        let poller = makePoller()
        _ = await poller.poll(accounts: [work])
        source.set(snap(), for: work.id)
        source.setStatus(PRStatus(state: .merged, isDraft: false, mergeable: .unknown, rollup: .success, headOid: "h1"), for: pr(3).key)
        _ = await poller.poll(accounts: [work])
        XCTAssertEqual(source.statusCalls, [pr(3).key])
        XCTAssertEqual(sink.alerts.map(\.title), ["Merged by someone"])
        XCTAssertEqual(sink.alerts.first?.payload.kind, "merged")
    }

    func testPullRequestThatLeftTheInboxButIsStillOpenSaysNothing() async {
        source.set(snap(needs: [pr(3, author: "bob", rollup: .pending)]), for: work.id)
        let poller = makePoller()
        _ = await poller.poll(accounts: [work])
        source.set(snap(), for: work.id)
        source.setStatus(PRStatus(state: .open, isDraft: false, mergeable: .mergeable, rollup: .pending, headOid: "h1"), for: pr(3).key)
        _ = await poller.poll(accounts: [work])
        XCTAssertTrue(sink.alerts.isEmpty)
    }

    func testFilePollStateStoreRoundTrips() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("poll-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let files = FilePollStateStore(directory: dir)
        XCTAssertNil(files.load(work.id))
        let state = PollState(snapshot: snap(yours: [pr(1)]), notifiedReady: ["acme/app#1@h1"])
        files.save(state, for: work.id)
        XCTAssertEqual(files.load(work.id), state)
        files.remove(work.id)
        XCTAssertNil(files.load(work.id))
    }
}
