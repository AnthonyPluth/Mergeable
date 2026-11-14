import Foundation
import SwiftUI
import MergeableCore

enum PRAction {
    case comment(String)
    case review(ReviewEvent, String?)
    case merge(MergeMethod)
    case markReady, close, reopen
}

@MainActor
final class PRDetailModel: ObservableObject {
    let item: InboxItem
    @Published private(set) var detail: PullRequestDetail?
    @Published private(set) var files: [ChangedFile] = []
    @Published private(set) var filesError: String?
    @Published private(set) var loadError: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isActing = false
    @Published var actionError: String?
    /// Set when the head moved after the user opened the PR: the merge was refused, never sent unseen code.
    @Published var changedSinceOpened = false

    /// The head commit the user was looking at when they opened the PR. A merge sends this as `expectedHeadOid`.
    private(set) var seenHeadOid: String?

    init(item: InboxItem) { self.item = item }

    var key: PRKey { item.summary.key }

    /// Screenshot harness only: show this PR without fetching.
    func useFixture(_ f: PRDetailFixture) {
        detail = f.detail; files = f.files; seenHeadOid = f.detail.summary.status.headOid
    }

    func load(store: AccountStore, client: GitHubClient) async {
        guard let reader = InboxLogic.readAccount(key: key, fetchedBy: item.fetchedBy, router: store.router) else {
            loadError = "No account can read this pull request."; return
        }
        isLoading = true; loadError = nil
        defer { isLoading = false }
        do {
            async let d = client.detail(key, as: reader)
            let loaded = try await d
            detail = loaded
            if seenHeadOid == nil { seenHeadOid = loaded.summary.status.headOid }
        } catch GitHubError.unauthorized { loadError = "This account's token stopped working. Update it in Accounts." }
        catch { loadError = error.localizedDescription }
        do { files = try await client.files(key, as: reader); filesError = nil }
        catch { filesError = error.localizedDescription }
    }

    /// Starts again from the PR as it is now (after "This PR changed since you opened it").
    func acceptChangedHead() { seenHeadOid = detail?.summary.status.headOid; changedSinceOpened = false }

    func perform(_ action: PRAction, as account: AccountID, store: AccountStore, client: GitHubClient) async -> Bool {
        guard let node = detail?.summary.nodeID ?? Optional(item.summary.nodeID) else { return false }
        isActing = true; actionError = nil
        defer { isActing = false }
        let owner = key.owner
        do {
            switch action {
            case .comment(let body): try await client.comment(prNodeID: node, body: body, as: account, owner: owner)
            case .review(let event, let body): try await client.submitReview(prNodeID: node, event: event, body: body, as: account, owner: owner)
            case .merge(let method):
                guard let oid = seenHeadOid else { actionError = "Reload the pull request first."; return false }
                try await client.merge(prNodeID: node, method: method, expectedHeadOid: oid, as: account, owner: owner)
            case .markReady: try await client.markReady(prNodeID: node, as: account, owner: owner)
            case .close: try await client.close(prNodeID: node, as: account, owner: owner)
            case .reopen: try await client.reopen(prNodeID: node, as: account, owner: owner)
            }
            await load(store: store, client: client)
            return true
        } catch GitHubError.headChanged {
            changedSinceOpened = true
            await load(store: store, client: client)
            return false
        } catch GitHubError.unauthorized {
            actionError = "That account's token stopped working. Nothing was sent with another account."
            return false
        } catch {
            actionError = error.localizedDescription
            return false
        }
    }
}
