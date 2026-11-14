import Testing
@testable import MergeableCore

@Suite struct MergeReadinessTests {
    let ok = PRStatus(state: .open, isDraft: false, mergeable: .mergeable, rollup: .success, headOid: "h")
    @Test func table() {
        #expect(isMergeReady(ok))
        var s = ok; s.isDraft = true; #expect(!isMergeReady(s))
        s = ok; s.state = .closed; #expect(!isMergeReady(s))
        s = ok; s.state = .merged; #expect(!isMergeReady(s))
        s = ok; s.rollup = .pending; #expect(!isMergeReady(s))
        s = ok; s.rollup = .failure; #expect(!isMergeReady(s))
        s = ok; s.mergeable = .conflicting; #expect(!isMergeReady(s))
        s = ok; s.mergeable = .unknown; #expect(isMergeReady(s))
        s = ok; s.rollup = nil; #expect(isMergeReady(s))
    }
}
