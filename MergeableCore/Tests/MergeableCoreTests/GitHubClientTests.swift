import Testing
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MergeableCore

let acctP = Account(id: AccountID("p"), login: "AnthonyPluth", label: "P", color: .blue, connection: .githubApp)
let acctW = Account(id: AccountID("w"), login: "work", label: "W", color: .orange, connection: .pat)
let tokens = FixedTokens(map: ["p": "tok-p", "w": "tok-w"])
func client(_ t: MockTransport, unauthorized: @escaping @Sendable (AccountID) -> Void = { _ in }) -> GitHubClient {
    GitHubClient(transport: t, tokens: tokens, onUnauthorized: unauthorized)
}
func auth(_ r: URLRequest) -> String? { r.value(forHTTPHeaderField: "Authorization") }

@Suite struct GitHubClientTests {
    @Test func inboxRunsFiveSearchesAndDedupes() async throws {
        let t = MockTransport { _ in (200, json(#"{"data":{"search":{"nodes":[\#(prNode(id: "A", number: 1)),\#(prNode(id: "A", number: 1)),\#(prNode(id: "B", number: 2)),{}]}}}"#), [:]) }
        let snap = try await client(t).inbox(for: acctP)
        #expect(t.requests.count == 5)
        let queries = (0..<5).map { (t.bodyJSON($0)["variables"] as! [String: String])["q"]! }
        #expect(queries.contains("is:pr is:open archived:false user:AnthonyPluth"))
        #expect(queries.contains("is:pr is:open archived:false review-requested:@me"))
        #expect(snap.sections[.yours]?.map(\.nodeID) == ["A", "B"])   // two searches, same PRs, de-duplicated
        #expect(snap.sections[.needsReview]?.count == 2)
        let a = try #require(snap.sections[.needsReview]?.first)
        #expect(a.key == PRKey(owner: "o", repo: "r", number: 1))
        #expect(a.status.rollup == .success && a.commentCount == 2 && a.lastCommentAuthor == "bob" && a.lastReviewState == "APPROVED")
    }

    @Test func patAccountSearchesEachOrgWithItsOwnToken() async throws {
        let t = MockTransport { _ in (200, json(#"{"data":{"search":{"nodes":[]}}}"#), [:]) }
        let orgTokens = OwnerTokens()
        let multi = Account(id: AccountID("w"), login: "work", label: "W", color: .orange, connection: .pat, orgs: ["acme", "beta"])
        _ = try await GitHubClient(transport: t, tokens: orgTokens, onUnauthorized: { _ in }).inbox(for: multi)
        #expect(t.requests.count == 15)   // five searches for each of login, acme, beta
        #expect(Set(t.requests.map { auth($0)! }) == ["Bearer tok-work", "Bearer tok-acme", "Bearer tok-beta"])
        let queries = (0..<15).map { (t.bodyJSON($0)["variables"] as! [String: String])["q"]! }
        #expect(queries.contains("is:pr is:open archived:false org:acme"))
        #expect(queries.contains("is:pr is:open archived:false user:work"))
    }

    @Test func usesOnlyTheGivenAccountsToken() async throws {
        let t = MockTransport { _ in (200, json(#"{"data":{"search":{"nodes":[]}}}"#), [:]) }
        _ = try await client(t).inbox(for: acctW)
        #expect(t.requests.allSatisfy { auth($0) == "Bearer tok-w" })
        try await client(t).comment(prNodeID: "X", body: "hi", as: acctP.id)
        #expect(auth(t.requests.last!) == "Bearer tok-p")
    }

    @Test func unauthorizedNeverFallsBack() async throws {
        let t = MockTransport { _ in (401, json("{}"), [:]) }
        let seen = Box<[AccountID]>([])
        let c = client(t) { seen.append($0) }
        await #expect(throws: GitHubError.unauthorized(acctW.id)) { try await c.comment(prNodeID: "X", body: "b", as: acctW.id) }
        #expect(t.requests.count == 1)
        #expect(seen.value == [acctW.id])
    }

    @Test func mergeSendsExpectedHeadOid() async throws {
        let t = MockTransport { _ in (200, json(#"{"data":{"mergePullRequest":{"clientMutationId":null}}}"#), [:]) }
        try await client(t).merge(prNodeID: "N1", method: .squash, expectedHeadOid: "abc123", as: acctP.id)
        let vars = t.bodyJSON(0)["variables"] as! [String: String]
        #expect(vars == ["id": "N1", "method": "SQUASH", "oid": "abc123"])
        #expect((t.bodyJSON(0)["query"] as! String).contains("expectedHeadOid:$oid"))
    }

    @Test func staleHeadMapsToHeadChanged() async throws {
        let t = MockTransport { _ in (200, json(#"{"data":null,"errors":[{"message":"Head branch was modified. Review and try the merge again."}]}"#), [:]) }
        await #expect(throws: GitHubError.headChanged) { try await client(t).merge(prNodeID: "N", method: .merge, expectedHeadOid: "old", as: acctP.id) }
    }

    @Test func filesFollowsPagination() async throws {
        let t = MockTransport { req in
            if req.url!.absoluteString.contains("page=2") {
                return (200, json(#"[{"filename":"b.txt","status":"added","additions":1,"deletions":0,"patch":"@@"}]"#), [:])
            }
            return (200, json(#"[{"filename":"a.txt","status":"modified","additions":2,"deletions":1,"patch":"@@"}]"#),
                    ["Link": #"<https://api.github.com/repos/o/r/pulls/1/files?per_page=100&page=2>; rel="next", <https://api.github.com/x?page=2>; rel="last""#])
        }
        let files = try await client(t).files(PRKey(owner: "o", repo: "r", number: 1), as: acctP.id)
        #expect(files.map(\.path) == ["a.txt", "b.txt"])
        #expect(t.requests.count == 2)
    }

    @Test func fileWithoutPatchDecodes() async throws {
        let t = MockTransport { _ in (200, json(#"[{"filename":"img.png","status":"added","additions":0,"deletions":0}]"#), [:]) }
        let files = try await client(t).files(PRKey(owner: "o", repo: "r", number: 1), as: acctP.id)
        #expect(files.count == 1 && files[0].patch == nil)
    }

    @Test func statusMapsFixture() async throws {
        let t = MockTransport { _ in (200, json(#"{"data":{"repository":{"pullRequest":{"title":"T","url":"https://x/1","state":"OPEN","isDraft":false,"mergeable":"UNKNOWN","headRefOid":"abc","author":{"login":"a"},"commits":{"nodes":[{"commit":{"statusCheckRollup":null}}]}}}}}"#), [:]) }
        let s = try await client(t).status(PRKey(owner: "o", repo: "r", number: 1), as: acctP.id)
        #expect(s == PRStatus(state: .open, isDraft: false, mergeable: .unknown, rollup: nil, headOid: "abc"))
        #expect(isMergeReady(s))
    }
}

final class Box<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock(); private var v: T
    init(_ v: T) { self.v = v }
    var value: T { lock.lock(); defer { lock.unlock() }; return v }
    func append<E>(_ e: E) where T == [E] { lock.lock(); v.append(e); lock.unlock() }
}

struct OwnerTokens: TokenProvider {
    func token(for account: AccountID, owner: String) async throws -> String { "tok-\(owner)" }
}
