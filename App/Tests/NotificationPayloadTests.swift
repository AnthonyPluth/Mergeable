import XCTest
import MergeableCore
@testable import Mergeable

final class NotificationPayloadTests: XCTestCase {
    /// What relay/src/handle.ts puts under `mergeable`, after APNs hands it to the app.
    private let relayPush: [AnyHashable: Any] = [
        "aps": ["alert": ["title": "Ready to merge", "subtitle": "acme/app #7", "body": "Fix it"], "thread-id": "acme/app#7"],
        "mergeable": ["v": 1, "kind": "mergeReady", "owner": "acme", "repo": "app", "number": 7, "url": "https://github.com/acme/app/pull/7"],
    ]

    func testParsesRelayPayload() throws {
        let p = try XCTUnwrap(NotificationPayload(userInfo: relayPush))
        XCTAssertEqual(p, NotificationPayload(kind: "mergeReady", owner: "acme", repo: "app", number: 7, url: URL(string: "https://github.com/acme/app/pull/7")))
        XCTAssertEqual(p.key, PRKey(owner: "acme", repo: "app", number: 7))
        XCTAssertEqual(p.threadID, "acme/app#7")
    }

    func testRejectsMissingWrongVersionOrIncompletePayloads() {
        XCTAssertNil(NotificationPayload(userInfo: ["aps": [:]]))
        XCTAssertNil(NotificationPayload(userInfo: ["mergeable": ["v": 2, "kind": "x", "owner": "a", "repo": "b", "number": 1]]))
        XCTAssertNil(NotificationPayload(userInfo: ["mergeable": ["v": 1, "kind": "x", "owner": "a", "repo": "b"]]))
        XCTAssertNil(NotificationPayload(userInfo: ["mergeable": ["v": 1, "kind": "x", "owner": "", "repo": "b", "number": 1]]))
        XCTAssertNil(NotificationPayload(userInfo: ["mergeable": "nope"]))
    }

    func testLocalAlertCarriesTheSamePayloadShapeAsThePush() throws {
        let event = InboxEvent.comment(PRKey(owner: "Acme", repo: "App", number: 7), title: "Fix it", by: "bob")
        let alert = LocalAlert(event: event)
        XCTAssertEqual(alert.title, "bob commented")
        XCTAssertEqual(alert.subtitle, "acme/app #7")
        XCTAssertEqual(alert.body, "Fix it")
        XCTAssertEqual(alert.threadID, "acme/app#7")
        let m = try XCTUnwrap(alert.userInfo["mergeable"] as? [String: Any])
        XCTAssertEqual(Set(m.keys), ["v", "kind", "owner", "repo", "number", "url"])
        XCTAssertEqual(m["v"] as? Int, 1)
        XCTAssertEqual(m["kind"] as? String, "comment")
        XCTAssertEqual(m["url"] as? String, "https://github.com/acme/app/pull/7")
        // and it round-trips through the same parser a tap uses
        XCTAssertEqual(NotificationPayload(userInfo: alert.userInfo), alert.payload)
    }

    func testEveryEventKindUsesTheRelayKindString() {
        let k = PRKey(owner: "o", repo: "r", number: 1)
        let events: [InboxEvent] = [
            .mergeReady(k, title: ""), .opened(k, title: ""), .readyForReview(k, title: ""), .reviewRequested(k, title: ""),
            .reviewSubmitted(k, title: "", by: "", state: ""), .comment(k, title: "", by: ""), .checksFailed(k, title: ""),
            .merged(k, title: "", by: ""), .closed(k, title: "", by: ""),
        ]
        XCTAssertEqual(events.map(\.kindName), ["mergeReady", "opened", "readyForReview", "reviewRequested", "reviewSubmitted",
                                                "comment", "checksFailed", "merged", "closed"])
    }

    func testMatchFindsTheInboxRowIgnoringCase() {
        let s = PullRequestSummary(nodeID: "N7", key: PRKey(owner: "acme", repo: "app", number: 7), title: "T", url: URL(string: "https://github.com/acme/app/pull/7")!,
                                   author: "bob", baseBranch: "main", status: PRStatus(state: .open, isDraft: false, mergeable: .mergeable, rollup: nil, headOid: "h"))
        let merged = InboxLogic.merge([AccountID("w"): InboxSnapshot(sections: [.yours: [s]])])
        let p = NotificationPayload(kind: "comment", owner: "ACME", repo: "App", number: 7, url: nil)
        XCTAssertEqual(p.match(in: merged)?.summary.nodeID, "N7")
        XCTAssertNil(NotificationPayload(kind: "comment", owner: "acme", repo: "app", number: 8, url: nil).match(in: merged))
    }
}
