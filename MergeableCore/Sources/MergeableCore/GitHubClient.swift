import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: wire types

private struct Login: Decodable { var login: String }
private struct Nodes<T: Decodable>: Decodable { var nodes: [T]? }
private struct Count: Decodable { var totalCount: Int }
private struct Review: Decodable { var state: String; var author: Login?; var createdAt: Date?; var body: String? }
private struct CommentNode: Decodable { var author: Login?; var createdAt: Date?; var body: String? }
private struct Rollup: Decodable { var state: String?; var contexts: Nodes<Context>? }
private struct Context: Decodable {
    var typename: String; var name: String?; var conclusion: String?; var status: String?; var detailsUrl: String?
    var context: String?; var state: String?; var targetUrl: String?
    enum CodingKeys: String, CodingKey { case typename = "__typename", name, conclusion, status, detailsUrl, context, state, targetUrl }
}
private struct CommitNode: Decodable { struct C: Decodable { var statusCheckRollup: Rollup? }; var commit: C }
private struct Repo: Decodable { var name: String; var owner: Login }

private struct GQLPR: Decodable {
    var id: String?; var number: Int?; var title: String; var url: URL; var updatedAt: Date?
    var isDraft: Bool; var state: PRState; var mergeable: MergeableState; var headRefOid: String
    var baseRefName: String?; var reviewDecision: String?; var author: Login?; var repository: Repo?
    var commits: Nodes<CommitNode>?; var comments: Count?; var lastComment: Nodes<CommentNode>?
    var reviews: Count?; var lastReview: Nodes<Review>?
    var body: String?; var timelineComments: Nodes<CommentNode>?; var timelineReviews: Nodes<Review>?

    var rollupState: CheckRollup? { commits?.nodes?.first?.commit.statusCheckRollup?.state.flatMap(CheckRollup.init(rawValue:)) }
    var status: PRStatus { PRStatus(state: state, isDraft: isDraft, mergeable: mergeable, rollup: rollupState, headOid: headRefOid) }
}

/// Search results also contain non-PR nodes (`{}`); those decode to nil instead of failing the whole response.
private struct Lossy<T: Decodable>: Decodable {
    var value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

private struct Envelope<T: Decodable>: Decodable {
    struct E: Decodable { var message: String }
    var data: T?; var errors: [E]?
}

public final class GitHubClient: Sendable {
    private let transport: HTTPTransport
    private let tokens: TokenProvider
    private let onUnauthorized: @Sendable (AccountID) -> Void

    public init(transport: HTTPTransport, tokens: TokenProvider, onUnauthorized: @escaping @Sendable (AccountID) -> Void) {
        self.transport = transport; self.tokens = tokens; self.onUnauthorized = onUnauthorized
    }

    // MARK: plumbing

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func request(_ url: URL, method: String = "GET", body: Data? = nil, account: AccountID, owner: String) async throws -> (Data, HTTPURLResponse) {
        let token = try await tokens.token(for: account, owner: owner)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = body
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Mergeable", forHTTPHeaderField: "User-Agent")
        if body != nil { req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, resp) = try await transport.send(req)   // exactly one token, never retried with another
        switch resp.statusCode {
        case 401: onUnauthorized(account); throw GitHubError.unauthorized(account)
        case 404: throw GitHubError.notFound
        case 200..<300: return (data, resp)
        default: throw GitHubError.http(resp.statusCode)
        }
    }

    private func graphQL<T: Decodable>(_ query: String, _ variables: [String: Any], as: T.Type = T.self, account: AccountID, owner: String) async throws -> T {
        let body = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
        let (data, _) = try await request(URL(string: "https://api.github.com/graphql")!, method: "POST", body: body, account: account, owner: owner)
        let env = try Self.decoder.decode(Envelope<T>.self, from: data)
        if let first = env.errors?.first {
            if first.message.localizedCaseInsensitiveContains("Head branch was modified") || first.message.contains("expectedHeadOid") { throw GitHubError.headChanged }
            throw GitHubError.graphQL(first.message)
        }
        guard let d = env.data else { throw GitHubError.graphQL("empty response") }
        return d
    }

    private func summary(_ p: GQLPR) -> PullRequestSummary? {
        guard let id = p.id, let number = p.number, let repo = p.repository else { return nil }
        return PullRequestSummary(
            nodeID: id, key: PRKey(owner: repo.owner.login, repo: repo.name, number: number), title: p.title, url: p.url,
            author: p.author?.login, baseBranch: p.baseRefName ?? "", status: p.status, reviewDecision: p.reviewDecision,
            updatedAt: p.updatedAt ?? Date(timeIntervalSince1970: 0), commentCount: p.comments?.totalCount ?? 0,
            lastCommentAuthor: p.lastComment?.nodes?.first?.author?.login, reviewCount: p.reviews?.totalCount ?? 0,
            lastReviewAuthor: p.lastReview?.nodes?.first?.author?.login, lastReviewState: p.lastReview?.nodes?.first?.state)
    }

    // MARK: reads

    public func inbox(for account: Account) async throws -> InboxSnapshot {
        struct R: Decodable { struct S: Decodable { var nodes: [Lossy<GQLPR>] }; var search: S }
        var sections: [InboxSection: [PullRequestSummary]] = [:]
        // A GitHub App account has one token; a PAT account may have one per org, so each owner is searched with its own token.
        var owners: [(name: String, isOrg: Bool)] = [(account.login, false)]
        if account.connection == .pat {
            for org in account.orgs where org.lowercased() != account.login.lowercased() { owners.append((org, true)) }
        }
        for owner in owners {
            for (section, q) in Queries.searches(for: owner.name, isOrg: owner.isOrg) {
                let r: R = try await graphQL(Queries.search, ["q": q], account: account.id, owner: owner.name)
                var list = sections[section] ?? []
                for node in r.search.nodes.compactMap(\.value) {
                    guard let s = summary(node), !list.contains(where: { $0.nodeID == s.nodeID }) else { continue }
                    list.append(s)
                }
                sections[section] = list
            }
        }
        for s in InboxSection.allCases where sections[s] == nil { sections[s] = [] }
        return InboxSnapshot(sections: sections)
    }

    public func detail(_ key: PRKey, as account: AccountID) async throws -> PullRequestDetail {
        struct R: Decodable { struct Repo: Decodable { var pullRequest: GQLPR? }; var repository: Repo? }
        let r: R = try await graphQL(Queries.detail, ["owner": key.owner, "repo": key.repo, "number": key.number], account: account, owner: key.owner)
        guard let p = r.repository?.pullRequest else { throw GitHubError.notFound }
        var s = summary(p) ?? PullRequestSummary(nodeID: p.id ?? "", key: key, title: p.title, url: p.url, author: p.author?.login, baseBranch: p.baseRefName ?? "", status: p.status)
        s.key = key
        let epoch = Date(timeIntervalSince1970: 0)
        let items = (p.timelineComments?.nodes ?? []).map { TimelineItem(author: $0.author?.login, date: $0.createdAt ?? epoch, kind: .comment, reviewState: nil, body: $0.body ?? "") }
            + (p.timelineReviews?.nodes ?? []).map { TimelineItem(author: $0.author?.login, date: $0.createdAt ?? epoch, kind: .review, reviewState: $0.state, body: $0.body ?? "") }
        let checks = (p.commits?.nodes?.first?.commit.statusCheckRollup?.contexts?.nodes ?? []).map { c -> CheckContext in
            if c.typename == "CheckRun" { return CheckContext(name: c.name ?? "", state: c.conclusion ?? c.status ?? "", url: c.detailsUrl.flatMap(URL.init(string:))) }
            return CheckContext(name: c.context ?? "", state: c.state ?? "", url: c.targetUrl.flatMap(URL.init(string:)))
        }
        return PullRequestDetail(summary: s, body: p.body ?? "", timeline: items.sorted { $0.date < $1.date }, checks: checks)
    }

    public func files(_ key: PRKey, as account: AccountID) async throws -> [ChangedFile] {
        struct F: Decodable { var filename: String; var status: String; var additions: Int; var deletions: Int; var patch: String? }
        var out: [ChangedFile] = []
        var next: URL? = URL(string: "https://api.github.com/repos/\(key.owner)/\(key.repo)/pulls/\(key.number)/files?per_page=100")
        while let url = next {
            let (data, resp) = try await request(url, account: account, owner: key.owner)
            out += try Self.decoder.decode([F].self, from: data).map { ChangedFile(path: $0.filename, status: $0.status, additions: $0.additions, deletions: $0.deletions, patch: $0.patch) }
            next = Self.nextLink(resp.value(forHTTPHeaderField: "Link"))
        }
        return out
    }

    static func nextLink(_ header: String?) -> URL? {
        guard let header else { return nil }
        for part in header.split(separator: ",") where part.contains("rel=\"next\"") {
            if let a = part.firstIndex(of: "<"), let b = part.firstIndex(of: ">"), a < b { return URL(string: String(part[part.index(after: a)..<b])) }
        }
        return nil
    }

    public func status(_ key: PRKey, as account: AccountID) async throws -> PRStatus {
        struct R: Decodable { struct Repo: Decodable { var pullRequest: GQLPR? }; var repository: Repo? }
        let r: R = try await graphQL(Queries.prStatus, ["owner": key.owner, "repo": key.repo, "number": key.number], account: account, owner: key.owner)
        guard let p = r.repository?.pullRequest else { throw GitHubError.notFound }
        return p.status
    }

    // MARK: writes (each uses only the given account's token; `owner` picks the token for per-org PATs)

    private struct Ack: Decodable {}
    private func mutate(_ q: String, _ vars: [String: Any], account: AccountID, owner: String) async throws {
        let _: Ack = try await graphQL(q, vars, account: account, owner: owner)
    }

    public func comment(prNodeID: String, body: String, as account: AccountID, owner: String = "") async throws {
        try await mutate(Queries.comment, ["id": prNodeID, "body": body], account: account, owner: owner)
    }
    public func submitReview(prNodeID: String, event: ReviewEvent, body: String?, as account: AccountID, owner: String = "") async throws {
        var v: [String: Any] = ["id": prNodeID, "event": event.rawValue]
        if let body { v["body"] = body }
        try await mutate(Queries.review, v, account: account, owner: owner)
    }
    public func merge(prNodeID: String, method: MergeMethod, expectedHeadOid: String, as account: AccountID, owner: String = "") async throws {
        try await mutate(Queries.merge, ["id": prNodeID, "method": method.rawValue, "oid": expectedHeadOid], account: account, owner: owner)
    }
    public func markReady(prNodeID: String, as account: AccountID, owner: String = "") async throws {
        try await mutate(Queries.markReady, ["id": prNodeID], account: account, owner: owner)
    }
    public func close(prNodeID: String, as account: AccountID, owner: String = "") async throws {
        try await mutate(Queries.close, ["id": prNodeID], account: account, owner: owner)
    }
    public func reopen(prNodeID: String, as account: AccountID, owner: String = "") async throws {
        try await mutate(Queries.reopen, ["id": prNodeID], account: account, owner: owner)
    }
}
