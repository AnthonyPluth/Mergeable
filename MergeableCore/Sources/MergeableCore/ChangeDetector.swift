import Foundation

public struct ClosedOutcome: Sendable {
    public var merged: Bool
    public var by: String?
    public init(merged: Bool, by: String?) { self.merged = merged; self.by = by }
}

public struct ChangeDetector: Sendable {
    public let selfLogin: String
    public init(selfLogin: String) { self.selfLogin = selfLogin }

    private func isSelf(_ login: String?) -> Bool { login?.lowercased() == selfLogin.lowercased() }

    public static func readyKey(_ s: PullRequestSummary) -> String {
        "\(s.key.owner)/\(s.key.repo)#\(s.key.number)@\(s.status.headOid)"
    }

    /// `previous == nil` is the baseline after an install: no events, but PRs that are already merge-ready are
    /// recorded so they don't alert later. `notifiedReady` holds "<owner>/<repo>#<number>@<headOid>".
    public func events(previous: InboxSnapshot?, current: InboxSnapshot, closed: [PRKey: ClosedOutcome], notifiedReady: inout Set<String>) -> [InboxEvent] {
        let cur = Self.flatten(current)
        guard let previous else {
            for (_, pr) in cur where isMergeReady(pr.status) { notifiedReady.insert(Self.readyKey(pr)) }
            return []
        }
        let prev = Self.flatten(previous)
        var out: [InboxEvent] = []

        for (key, pr) in cur {
            let old = prev[key]
            let sections = Self.sections(of: key, in: current)
            let oldSections = Self.sections(of: key, in: previous)

            if sections.contains(.needsReview), !oldSections.contains(.needsReview) { out.append(.reviewRequested(key, title: pr.title)) }
            if sections.contains(.yours), !oldSections.contains(.yours), !isSelf(pr.author) { out.append(.opened(key, title: pr.title)) }

            if let old {
                if old.status.isDraft, !pr.status.isDraft, !isSelf(pr.author) { out.append(.readyForReview(key, title: pr.title)) }
                if pr.commentCount > old.commentCount, let by = pr.lastCommentAuthor, !isSelf(by) { out.append(.comment(key, title: pr.title, by: by)) }
                if pr.reviewCount > old.reviewCount, let by = pr.lastReviewAuthor, !isSelf(by) {
                    out.append(.reviewSubmitted(key, title: pr.title, by: by, state: pr.lastReviewState ?? ""))
                }
                let failing: (CheckRollup?) -> Bool = { $0 == .failure || $0 == .error }
                if failing(pr.status.rollup), !failing(old.status.rollup) { out.append(.checksFailed(key, title: pr.title)) }
            }

            if isMergeReady(pr.status), !notifiedReady.contains(Self.readyKey(pr)), isSelf(pr.author) || isSelf(key.owner) {
                notifiedReady.insert(Self.readyKey(pr))
                out.append(.mergeReady(key, title: pr.title))
            }
        }

        for (key, old) in prev where cur[key] == nil {
            guard let outcome = closed[key], !isSelf(outcome.by) else { continue }
            let by = outcome.by ?? "someone"
            out.append(outcome.merged ? .merged(key, title: old.title, by: by) : .closed(key, title: old.title, by: by))
        }
        return out
    }

    private static func sections(of key: PRKey, in snap: InboxSnapshot) -> Set<InboxSection> {
        Set(snap.sections.filter { $0.value.contains { $0.key == key } }.map(\.key))
    }

    /// First occurrence wins, in section order, so the result is the same for the same snapshot.
    private static func flatten(_ snap: InboxSnapshot) -> OrderedPRs {
        var out = OrderedPRs()
        for section in InboxSection.allCases { for pr in snap.sections[section] ?? [] where out[pr.key] == nil { out.append(pr) } }
        return out
    }
}

private struct OrderedPRs: Sequence {
    private var keys: [PRKey] = []
    private var map: [PRKey: PullRequestSummary] = [:]
    subscript(key: PRKey) -> PullRequestSummary? { map[key] }
    mutating func append(_ pr: PullRequestSummary) { keys.append(pr.key); map[pr.key] = pr }
    func makeIterator() -> AnyIterator<(PRKey, PullRequestSummary)> {
        var i = keys.startIndex
        return AnyIterator { guard i < keys.endIndex else { return nil }; defer { i += 1 }; return (keys[i], map[keys[i]]!) }
    }
}
