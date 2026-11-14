import Foundation
import MergeableCore

extension InboxEvent {
    /// Same strings the relay sends in `mergeable.kind` (relay/src/events.ts).
    var kindName: String {
        switch self {
        case .mergeReady: return "mergeReady"
        case .opened: return "opened"
        case .readyForReview: return "readyForReview"
        case .reviewRequested: return "reviewRequested"
        case .reviewSubmitted: return "reviewSubmitted"
        case .comment: return "comment"
        case .checksFailed: return "checksFailed"
        case .merged: return "merged"
        case .closed: return "closed"
        }
    }
}

/// The `mergeable` object in a push payload: `{v:1, kind, owner, repo, number, url}`. Local alerts carry the same shape,
/// so tapping either opens the PR through one code path.
struct NotificationPayload: Equatable, Sendable {
    static let version = 1
    static let userInfoKey = "mergeable"

    var kind: String
    var owner: String
    var repo: String
    var number: Int
    var url: URL?

    var key: PRKey { PRKey(owner: owner, repo: repo, number: number) }
    /// Groups alerts for one PR in Notification Center.
    var threadID: String { "\(owner)/\(repo)#\(number)" }

    init(kind: String, owner: String, repo: String, number: Int, url: URL?) {
        self.kind = kind; self.owner = owner; self.repo = repo; self.number = number; self.url = url
    }

    init(event: InboxEvent) {
        let k = event.key
        self.init(kind: event.kindName, owner: k.owner, repo: k.repo, number: k.number,
                  url: URL(string: "https://github.com/\(k.owner)/\(k.repo)/pull/\(k.number)"))
    }

    /// Returns nil unless the payload has a `mergeable` object of a version we understand with owner, repo and number.
    init?(userInfo: [AnyHashable: Any]) {
        guard let m = userInfo[Self.userInfoKey] as? [String: Any] else { return nil }
        func int(_ v: Any?) -> Int? {
            if let i = v as? Int { return i }
            if let d = v as? Double { return Int(d) }
            if let s = v as? String { return Int(s) }
            return nil
        }
        guard let v = int(m["v"]), v == Self.version,
              let owner = m["owner"] as? String, !owner.isEmpty,
              let repo = m["repo"] as? String, !repo.isEmpty,
              let number = int(m["number"]) else { return nil }
        self.init(kind: (m["kind"] as? String) ?? "", owner: owner, repo: repo, number: number,
                  url: (m["url"] as? String).flatMap { URL(string: $0) })
    }

    var userInfo: [String: Any] {
        var m: [String: Any] = ["v": Self.version, "kind": kind, "owner": owner, "repo": repo, "number": number]
        if let url { m["url"] = url.absoluteString }
        return [Self.userInfoKey: m]
    }

    /// The inbox row for this PR, if the inbox has it.
    func match(in merged: [InboxSection: [InboxItem]]) -> InboxItem? {
        for section in InboxSection.allCases {
            if let item = merged[section]?.first(where: { $0.summary.key == key }) { return item }
        }
        return nil
    }
}

/// What gets posted: copy from `NotificationCopy.render` plus the payload. No UserNotifications types, so it is testable.
struct LocalAlert: Equatable, Sendable {
    var title: String
    var subtitle: String
    var body: String
    var payload: NotificationPayload
    var threadID: String { payload.threadID }
    var userInfo: [String: Any] { payload.userInfo }

    init(event: InboxEvent) {
        let c = NotificationCopy.render(event)
        title = c.title; subtitle = c.subtitle; body = c.body
        payload = NotificationPayload(event: event)
    }
}
