import Foundation

public enum InboxEvent: Equatable, Sendable {
    case mergeReady(PRKey, title: String)
    case opened(PRKey, title: String)
    case readyForReview(PRKey, title: String)
    case reviewRequested(PRKey, title: String)
    case reviewSubmitted(PRKey, title: String, by: String, state: String)
    case comment(PRKey, title: String, by: String)
    case checksFailed(PRKey, title: String)
    case merged(PRKey, title: String, by: String)
    case closed(PRKey, title: String, by: String)

    public var key: PRKey {
        switch self {
        case .mergeReady(let k, _), .opened(let k, _), .readyForReview(let k, _), .reviewRequested(let k, _),
             .reviewSubmitted(let k, _, _, _), .comment(let k, _, _), .checksFailed(let k, _), .merged(let k, _, _), .closed(let k, _, _):
            return k
        }
    }
}

/// Same strings as the relay (relay/src/copy.ts). Subtitle is `{owner}/{repo} #{number}`; body is the PR title.
public enum NotificationCopy {
    public static func render(_ e: InboxEvent) -> (title: String, subtitle: String, body: String) {
        let t: String, title: String
        switch e {
        case .mergeReady(_, let x): t = "Ready to merge"; title = x
        case .opened(_, let x): t = "New pull request"; title = x
        case .readyForReview(_, let x): t = "Ready for review"; title = x
        case .reviewRequested(_, let x): t = "Review requested"; title = x
        case .reviewSubmitted(_, let x, let by, let state):
            switch state.uppercased() {
            case "APPROVED": t = "\(by) approved"
            case "CHANGES_REQUESTED": t = "\(by) requested changes"
            default: t = "\(by) reviewed"
            }
            title = x
        case .comment(_, let x, let by): t = "\(by) commented"; title = x
        case .checksFailed(_, let x): t = "Checks failed"; title = x
        case .merged(_, let x, let by): t = "Merged by \(by)"; title = x
        case .closed(_, let x, let by): t = "Closed by \(by)"; title = x
        }
        return (t, "\(e.key.owner)/\(e.key.repo) #\(e.key.number)", title)
    }
}
