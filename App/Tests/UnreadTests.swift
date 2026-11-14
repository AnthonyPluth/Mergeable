import XCTest
import MergeableCore
@testable import Mergeable

final class UnreadTests: XCTestCase {
    private let acct = AccountID("w")
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func pr(_ n: Int, updated: TimeInterval) -> PullRequestSummary {
        PullRequestSummary(nodeID: "N\(n)", key: PRKey(owner: "acme", repo: "app", number: n), title: "T\(n)", url: URL(string: "https://github.com/acme/app/pull/\(n)")!,
                           author: "bob", baseBranch: "main",
                           status: PRStatus(state: .open, isDraft: false, mergeable: .mergeable, rollup: nil, headOid: "h"),
                           updatedAt: t0.addingTimeInterval(updated))
    }

    private func snap(_ prs: [PullRequestSummary], also: [PullRequestSummary] = []) -> InboxSnapshot {
        InboxSnapshot(sections: [.needsReview: prs, .yours: also, .assignedOrMentioned: []])
    }

    func testFirstSightingIsBaselineSoNothingIsUnread() {
        let u = UnreadTracker(store: MemoryKeyValueStore())
        u.ensureMarker(for: acct, now: t0)
        XCTAssertEqual(u.unreadCount(snap([pr(1, updated: -100), pr(2, updated: -5)]), account: acct), 0)
    }

    func testUnreadIsActivityAfterTheMarkerCountedOncePerPR() {
        let u = UnreadTracker(store: MemoryKeyValueStore())
        u.ensureMarker(for: acct, now: t0)
        let fresh = pr(1, updated: 60)
        XCTAssertEqual(u.unreadCount(snap([fresh, pr(2, updated: -5)], also: [fresh]), account: acct), 1)
    }

    func testOpeningMarksReadUntilItChangesAgain() {
        let u = UnreadTracker(store: MemoryKeyValueStore())
        u.ensureMarker(for: acct, now: t0)
        let v1 = pr(1, updated: 60)
        XCTAssertTrue(u.isUnread(v1, account: acct))
        u.markOpened(v1)
        XCTAssertFalse(u.isUnread(v1, account: acct))
        XCTAssertTrue(u.isUnread(pr(1, updated: 120), account: acct))
    }

    func testMarkAllReadMovesTheMarker() {
        let u = UnreadTracker(store: MemoryKeyValueStore())
        u.ensureMarker(for: acct, now: t0)
        u.markAllRead(account: acct, now: t0.addingTimeInterval(200))
        XCTAssertEqual(u.unreadCount(snap([pr(1, updated: 60), pr(2, updated: 150)]), account: acct), 0)
        XCTAssertEqual(u.unreadCount(snap([pr(3, updated: 250)]), account: acct), 1)
    }

    func testMarkersAreSyncedThroughTheStore() {
        let kv = MemoryKeyValueStore()
        let a = UnreadTracker(store: kv)
        a.ensureMarker(for: acct, now: t0)
        let p = pr(1, updated: 60)
        a.markOpened(p)
        let b = UnreadTracker(store: kv)   // another device reading the same iCloud store
        XCTAssertFalse(b.isUnread(p, account: acct))
        XCTAssertTrue(b.isUnread(pr(2, updated: 60), account: acct))
    }

    func testAccountsAreIndependent() {
        let u = UnreadTracker(store: MemoryKeyValueStore())
        u.ensureMarker(for: acct, now: t0)
        let other = AccountID("p")
        XCTAssertFalse(u.isUnread(pr(1, updated: 60), account: other))   // never seen: no baseline yet
        u.ensureMarker(for: other, now: t0.addingTimeInterval(500))
        XCTAssertTrue(u.isUnread(pr(1, updated: 60), account: acct))
        XCTAssertFalse(u.isUnread(pr(1, updated: 60), account: other))
    }
}
