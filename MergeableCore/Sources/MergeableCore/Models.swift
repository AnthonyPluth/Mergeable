import Foundation

public enum InboxSection: String, CaseIterable, Codable, Sendable { case needsReview, yours, assignedOrMentioned }

public struct PullRequestSummary: Codable, Hashable, Sendable {
    public var nodeID: String
    public var key: PRKey
    public var title: String
    public var url: URL
    public var author: String?
    public var baseBranch: String
    public var status: PRStatus
    public var reviewDecision: String?
    public var updatedAt: Date
    public var commentCount: Int
    public var lastCommentAuthor: String?
    public var reviewCount: Int
    public var lastReviewAuthor: String?
    public var lastReviewState: String?

    public init(nodeID: String, key: PRKey, title: String, url: URL, author: String?, baseBranch: String, status: PRStatus,
                reviewDecision: String? = nil, updatedAt: Date = Date(timeIntervalSince1970: 0), commentCount: Int = 0,
                lastCommentAuthor: String? = nil, reviewCount: Int = 0, lastReviewAuthor: String? = nil, lastReviewState: String? = nil) {
        self.nodeID = nodeID; self.key = key; self.title = title; self.url = url; self.author = author; self.baseBranch = baseBranch
        self.status = status; self.reviewDecision = reviewDecision; self.updatedAt = updatedAt; self.commentCount = commentCount
        self.lastCommentAuthor = lastCommentAuthor; self.reviewCount = reviewCount
        self.lastReviewAuthor = lastReviewAuthor; self.lastReviewState = lastReviewState
    }
}

public struct InboxSnapshot: Codable, Sendable {
    public var sections: [InboxSection: [PullRequestSummary]]
    public init(sections: [InboxSection: [PullRequestSummary]] = [:]) { self.sections = sections }
}

public struct TimelineItem: Sendable, Hashable {
    public enum Kind: String, Sendable { case comment, review }
    public var author: String?
    public var date: Date
    public var kind: Kind
    public var reviewState: String?
    public var body: String
}

public struct CheckContext: Sendable, Hashable {
    public var name: String
    public var state: String
    public var url: URL?
}

public struct PullRequestDetail: Sendable {
    public var summary: PullRequestSummary
    public var body: String
    public var timeline: [TimelineItem]
    public var checks: [CheckContext]
}

public struct ChangedFile: Codable, Sendable, Hashable {
    public var path: String
    public var status: String
    public var additions: Int
    public var deletions: Int
    public var patch: String?
}

public enum ReviewEvent: String, Sendable { case approve = "APPROVE", requestChanges = "REQUEST_CHANGES", comment = "COMMENT" }
public enum MergeMethod: String, Codable, Sendable { case merge = "MERGE", squash = "SQUASH", rebase = "REBASE" }
