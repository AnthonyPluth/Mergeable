import XCTest
import MergeableCore
@testable import Mergeable

final class InboxLogicTests: XCTestCase {
    let p = AccountID("p"), w = AccountID("w")
    let personal = Account(id: AccountID("p"), login: "AnthonyPluth", label: "Personal", color: .blue, connection: .githubApp)
    let work = Account(id: AccountID("w"), login: "apluth-acme", label: "Work", color: .orange, connection: .pat, orgs: ["Acme"])

    func pr(_ id: String, owner: String = "acme", n: Int = 1, updated: TimeInterval = 0) -> PullRequestSummary {
        PullRequestSummary(nodeID: id, key: PRKey(owner: owner, repo: "r", number: n), title: id, url: URL(string: "https://x")!, author: "a", baseBranch: "main",
                           status: PRStatus(state: .open, isDraft: false, mergeable: .mergeable, rollup: .success, headOid: "h"), updatedAt: Date(timeIntervalSince1970: updated))
    }

    func testMergeDedupesAcrossAccountsAndSortsNewestFirst() {
        let a = InboxSnapshot(sections: [.yours: [pr("A", updated: 1), pr("B", n: 2, updated: 5)]])
        let b = InboxSnapshot(sections: [.yours: [pr("A", updated: 1)]])
        let merged = InboxLogic.merge([p: a, w: b])
        XCTAssertEqual(merged[.yours]?.map(\.summary.nodeID), ["B", "A"])
        XCTAssertEqual(merged[.yours]?.last?.fetchedBy, [p, w])
        XCTAssertEqual(merged[.needsReview]?.count, 0)
    }

    func testAccountTabOnlyShowsWhatThatAccountReturned() {
        let merged = InboxLogic.merge([p: InboxSnapshot(sections: [.yours: [pr("A")]]), w: InboxSnapshot(sections: [.yours: [pr("B", n: 2)]])])
        XCTAssertEqual(InboxLogic.items(merged, in: .account(w), section: .yours).map(\.summary.nodeID), ["B"])
        XCTAssertEqual(InboxLogic.items(merged, in: .all, section: .yours).count, 2)
    }

    func testResolveActorFollowsTheRouterAndNeverGuesses() {
        let router = Router(accounts: [personal, work])
        let acme = PRKey(owner: "acme", repo: "r", number: 1)
        XCTAssertEqual(InboxLogic.resolveActor(key: acme, fetchedBy: [p, w], router: router, claims: []), .acting(w))
        let oss = PRKey(owner: "oss", repo: "lib", number: 1)
        XCTAssertEqual(InboxLogic.resolveActor(key: oss, fetchedBy: [p, w], router: router, claims: []), .choose([p, w]))
        XCTAssertEqual(InboxLogic.resolveActor(key: oss, fetchedBy: [w], router: router, claims: []), .acting(w))
        guard case .readOnly = InboxLogic.resolveActor(key: oss, fetchedBy: [], router: router, claims: []) else { return XCTFail("unowned must be read-only") }
    }

    func testOwnerClaimedByTwoIsReadOnlyUntilAssigned() {
        var other = personal; other.id = AccountID("p2"); other.login = "someone"; other.orgs = ["acme"]
        let router = Router(accounts: [work, other])
        let claims = [OwnerClaim(owner: "acme", claimedBy: [work.id, other.id], assigned: nil)]
        guard case .readOnly = InboxLogic.resolveActor(key: PRKey(owner: "acme", repo: "r", number: 1), fetchedBy: [w], router: router, claims: claims) else { return XCTFail() }
    }

    func testButtonTitlesNameTheAccount() {
        XCTAssertEqual(ActionTitle.comment("me"), "Comment as @me")
        XCTAssertEqual(ActionTitle.approve("me"), "Approve as @me")
        XCTAssertEqual(ActionTitle.requestChanges("me"), "Request changes as @me")
        XCTAssertEqual(ActionTitle.merge("me"), "Merge as @me")
        XCTAssertEqual(ActionTitle.markReady("me"), "Mark ready as @me")
    }

    func testStateColorsAndCheckVisuals() {
        XCTAssertEqual(InboxLogic.checkVisual("SUCCESS"), .success)
        XCTAssertEqual(InboxLogic.checkVisual("timed_out"), .failure)
        XCTAssertEqual(InboxLogic.checkVisual("IN_PROGRESS"), .pending)
        XCTAssertNil(InboxLogic.rollupVisual(nil))
        XCTAssertEqual(InboxLogic.rollupVisual(.error), .failure)
    }

    func testAgeAndLinearLink() {
        let now = Date(timeIntervalSince1970: 10_000_000)
        XCTAssertEqual(InboxLogic.age(from: now.addingTimeInterval(-30), now: now), "now")
        XCTAssertEqual(InboxLogic.age(from: now.addingTimeInterval(-300), now: now), "5m")
        XCTAssertEqual(InboxLogic.age(from: now.addingTimeInterval(-7200), now: now), "2h")
        XCTAssertEqual(InboxLogic.age(from: now.addingTimeInterval(-86_400 * 3), now: now), "3d")
        XCTAssertEqual(InboxLogic.linearURL(PRKey(owner: "Acme", repo: "API", number: 7))?.absoluteString, "https://linear.review/acme/api/pull/7")
    }

    func testMergeMethodIsRememberedPerRepo() {
        let d = UserDefaults(suiteName: "mergeable.tests.\(UUID().uuidString)")!
        let k = PRKey(owner: "acme", repo: "api", number: 1)
        XCTAssertEqual(MergeMethodStore.method(for: k, defaults: d), .squash)
        MergeMethodStore.remember(.rebase, for: k, defaults: d)
        XCTAssertEqual(MergeMethodStore.method(for: PRKey(owner: "ACME", repo: "api", number: 9), defaults: d), .rebase)
    }
}
