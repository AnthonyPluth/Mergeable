import Testing
import Foundation
@testable import MergeableCore

private func pr(_ n: Int, owner: String = "acme", author: String = "alice", head: String = "h1", draft: Bool = false,
                rollup: CheckRollup? = .pending, comments: Int = 0, lastCommenter: String? = nil, reviews: Int = 0, reviewer: String? = nil, reviewState: String? = nil) -> PullRequestSummary {
    PullRequestSummary(nodeID: "N\(n)", key: PRKey(owner: owner, repo: "r", number: n), title: "T\(n)", url: URL(string: "https://x/\(n)")!, author: author, baseBranch: "main",
                       status: PRStatus(state: .open, isDraft: draft, mergeable: .mergeable, rollup: rollup, headOid: head),
                       commentCount: comments, lastCommentAuthor: lastCommenter, reviewCount: reviews, lastReviewAuthor: reviewer, lastReviewState: reviewState)
}
private func snap(needs: [PullRequestSummary] = [], yours: [PullRequestSummary] = [], other: [PullRequestSummary] = []) -> InboxSnapshot {
    InboxSnapshot(sections: [.needsReview: needs, .yours: yours, .assignedOrMentioned: other])
}
private let det = ChangeDetector(selfLogin: "AnthonyPluth")
private func run(_ p: InboxSnapshot?, _ c: InboxSnapshot, closed: [PRKey: ClosedOutcome] = [:], ready: inout Set<String>) -> [InboxEvent] {
    det.events(previous: p, current: c, closed: closed, notifiedReady: &ready)
}
private func run(_ p: InboxSnapshot?, _ c: InboxSnapshot, closed: [PRKey: ClosedOutcome] = [:]) -> [InboxEvent] {
    var r = Set<String>(); return run(p, c, closed: closed, ready: &r)
}
private let me = "anthonypluth"

@Suite struct ChangeDetectorTests {
    @Test func firstSnapshotIsBaseline() {
        var ready = Set<String>()
        let ev = run(nil, snap(needs: [pr(1)], yours: [pr(2, author: "AnthonyPluth", rollup: .success)]), ready: &ready)
        #expect(ev.isEmpty)
        #expect(ready == ["acme/r#2@h1"])   // already-ready PRs are recorded so they don't alert later
    }
    @Test func newInNeedsReviewIsReviewRequested() {
        #expect(run(snap(), snap(needs: [pr(1)])) == [.reviewRequested(pr(1).key, title: "T1")])
    }
    @Test func newInYoursOpenedUnlessSelf() {
        #expect(run(snap(), snap(yours: [pr(1)])) == [.opened(pr(1).key, title: "T1")])
        #expect(run(snap(), snap(yours: [pr(1, author: "AnthonyPluth")])).isEmpty)
    }
    @Test func readyForReviewUnlessSelf() {
        #expect(run(snap(yours: [pr(1, draft: true)]), snap(yours: [pr(1)])) == [.readyForReview(pr(1).key, title: "T1")])
        #expect(run(snap(yours: [pr(1, author: "AnthonyPluth", draft: true)]), snap(yours: [pr(1, author: "AnthonyPluth")])).isEmpty)
    }
    @Test func commentUnlessSelf() {
        #expect(run(snap(yours: [pr(1)]), snap(yours: [pr(1, comments: 1, lastCommenter: "bob")])) == [.comment(pr(1).key, title: "T1", by: "bob")])
        #expect(run(snap(yours: [pr(1)]), snap(yours: [pr(1, comments: 1, lastCommenter: "AnthonyPluth")])).isEmpty)
    }
    @Test func reviewUnlessSelf() {
        #expect(run(snap(yours: [pr(1)]), snap(yours: [pr(1, reviews: 1, reviewer: "carol", reviewState: "APPROVED")]))
                == [.reviewSubmitted(pr(1).key, title: "T1", by: "carol", state: "APPROVED")])
        #expect(run(snap(yours: [pr(1)]), snap(yours: [pr(1, reviews: 1, reviewer: "ANTHONYPLUTH", reviewState: "APPROVED")])).isEmpty)
    }
    @Test func checksFailed() {
        #expect(run(snap(yours: [pr(1, rollup: .pending)]), snap(yours: [pr(1, rollup: .failure)])) == [.checksFailed(pr(1).key, title: "T1")])
        #expect(run(snap(yours: [pr(1, rollup: .failure)]), snap(yours: [pr(1, rollup: .failure)])).isEmpty)   // already failing
    }
    @Test func mergeReadyForMyPRsAndMyRepos() {
        let mine = pr(1, author: "AnthonyPluth", rollup: .success)
        #expect(run(snap(yours: [pr(1, author: "AnthonyPluth", rollup: .pending)]), snap(yours: [mine])) == [.mergeReady(mine.key, title: "T1")])
        let myRepo = pr(2, owner: "AnthonyPluth", author: "dependabot", rollup: .success)
        #expect(run(snap(yours: [pr(2, owner: "AnthonyPluth", author: "dependabot")]), snap(yours: [myRepo])) == [.mergeReady(myRepo.key, title: "T2")])
        let notMine = pr(3, owner: "acme", author: "alice", rollup: .success)   // someone else's PR in someone else's repo
        #expect(run(snap(other: [pr(3)]), snap(other: [notMine])).isEmpty)
    }
    @Test func noChecksIsReady() {
        let p = pr(1, author: "AnthonyPluth", rollup: nil)
        #expect(run(snap(yours: [pr(1, author: "AnthonyPluth", draft: true, rollup: nil)]), snap(yours: [p])).contains(.mergeReady(p.key, title: "T1")))
    }
    @Test func sameHeadAlertsOnce() {
        var ready = Set<String>()
        let a = snap(yours: [pr(1, author: "AnthonyPluth", rollup: .pending)]), b = snap(yours: [pr(1, author: "AnthonyPluth", rollup: .success)])
        #expect(run(a, b, ready: &ready).count == 1)
        #expect(run(a, b, ready: &ready).isEmpty)
    }
    @Test func newHeadAlertsAgain() {
        var ready = Set<String>()
        let a = snap(yours: [pr(1, author: "AnthonyPluth", head: "h1", rollup: .success)]), b = snap(yours: [pr(1, author: "AnthonyPluth", head: "h2", rollup: .success)])
        _ = run(nil, a, ready: &ready)
        #expect(run(a, b, ready: &ready) == [.mergeReady(pr(1).key, title: "T1")])
    }
    @Test func mergedAndClosedUnlessSelf() {
        let k = pr(1).key
        let p = snap(yours: [pr(1)])
        #expect(run(p, snap(), closed: [k: ClosedOutcome(merged: true, by: "bob")]) == [.merged(k, title: "T1", by: "bob")])
        #expect(run(p, snap(), closed: [k: ClosedOutcome(merged: false, by: "bob")]) == [.closed(k, title: "T1", by: "bob")])
        #expect(run(p, snap(), closed: [k: ClosedOutcome(merged: true, by: "AnthonyPluth")]).isEmpty)
    }
    @Test func copyMatchesRelayTable() {
        let k = PRKey(owner: "o", repo: "r", number: 7)
        func c(_ e: InboxEvent) -> String { NotificationCopy.render(e).title }
        #expect(NotificationCopy.render(.mergeReady(k, title: "T")) == (title: "Ready to merge", subtitle: "o/r #7", body: "T"))
        #expect(c(.opened(k, title: "T")) == "New pull request")
        #expect(c(.readyForReview(k, title: "T")) == "Ready for review")
        #expect(c(.reviewRequested(k, title: "T")) == "Review requested")
        #expect(c(.reviewSubmitted(k, title: "T", by: "bob", state: "APPROVED")) == "bob approved")
        #expect(c(.reviewSubmitted(k, title: "T", by: "bob", state: "CHANGES_REQUESTED")) == "bob requested changes")
        #expect(c(.reviewSubmitted(k, title: "T", by: "bob", state: "COMMENTED")) == "bob reviewed")
        #expect(c(.comment(k, title: "T", by: "bob")) == "bob commented")
        #expect(c(.checksFailed(k, title: "T")) == "Checks failed")
        #expect(c(.merged(k, title: "T", by: "bob")) == "Merged by bob")
        #expect(c(.closed(k, title: "T", by: "bob")) == "Closed by bob")
    }
}
