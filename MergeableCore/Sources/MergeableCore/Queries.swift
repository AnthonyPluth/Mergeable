import Foundation

enum Queries {
    /// Shared with the relay (relay/src/githubApp.ts).
    static let prStatus = "query($owner:String!,$repo:String!,$number:Int!){repository(owner:$owner,name:$repo){pullRequest(number:$number){title url state isDraft mergeable headRefOid author{login} commits(last:1){nodes{commit{statusCheckRollup{state}}}}}}}"

    static let summaryFields = """
    id number title url updatedAt isDraft state mergeable headRefOid baseRefName reviewDecision author{login} \
    repository{name owner{login}} commits(last:1){nodes{commit{statusCheckRollup{state}}}} \
    comments{totalCount} lastComment: comments(last:1){nodes{author{login}}} \
    reviews{totalCount} lastReview: reviews(last:1){nodes{state author{login}}}
    """

    static let search = "query($q:String!){search(query:$q,type:ISSUE,first:50){nodes{... on PullRequest{\(summaryFields)}}}}"

    static let detail = """
    query($owner:String!,$repo:String!,$number:Int!){repository(owner:$owner,name:$repo){pullRequest(number:$number){\(summaryFields) body \
    timelineComments: comments(last:50){nodes{author{login} createdAt body}} \
    timelineReviews: reviews(last:50){nodes{author{login} createdAt state body}} \
    commits(last:1){nodes{commit{statusCheckRollup{contexts(first:50){nodes{__typename ... on CheckRun{name conclusion status detailsUrl} ... on StatusContext{context state targetUrl}}}}}}}}}}
    """

    static let comment = "mutation($id:ID!,$body:String!){addComment(input:{subjectId:$id,body:$body}){clientMutationId}}"
    static let review = "mutation($id:ID!,$event:PullRequestReviewEvent!,$body:String){addPullRequestReview(input:{pullRequestId:$id,event:$event,body:$body}){clientMutationId}}"
    static let merge = "mutation($id:ID!,$method:PullRequestMergeMethod!,$oid:GitObjectID!){mergePullRequest(input:{pullRequestId:$id,mergeMethod:$method,expectedHeadOid:$oid}){clientMutationId}}"
    static let markReady = "mutation($id:ID!){markPullRequestReadyForReview(input:{pullRequestId:$id}){clientMutationId}}"
    static let close = "mutation($id:ID!){closePullRequest(input:{pullRequestId:$id}){clientMutationId}}"
    static let reopen = "mutation($id:ID!){reopenPullRequest(input:{pullRequestId:$id}){clientMutationId}}"

    static func searches(for login: String) -> [(InboxSection, String)] {
        let base = "is:pr is:open archived:false"
        return [
            (.needsReview, "\(base) review-requested:@me"),
            (.yours, "\(base) author:@me"),
            (.yours, "\(base) user:\(login)"),
            (.assignedOrMentioned, "\(base) assignee:@me"),
            (.assignedOrMentioned, "\(base) mentions:@me"),
        ]
    }
}
