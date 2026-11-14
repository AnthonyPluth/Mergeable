import Foundation
import SwiftUI
import MergeableCore
@testable import Mergeable

/// The PRs, accounts and copy from tools/primer/mockups.mjs, as app data, so the real screens can be rendered
/// next to docs/mockups/*.png. No network, no Keychain, no iCloud.
@MainActor
struct MockupScene {
    let store: AccountStore
    let env: AppEnvironment
    let inbox: InboxModel
    /// "Cache org membership lookups" (acme/api #471), the PR the mockups open.
    let selected: InboxItem

    var inboxRoot: some View { root(RootView(inbox: inbox, selection: nil)) }
    var macRoot: some View { root(RootView(inbox: inbox, selection: selected)) }
    var detailRoot: some View { root(NavigationStack { PRDetailView(item: selected) }) }

    /// The merge sheet over the detail screen with a scrim, as in the mockup.
    var mergeSheetRoot: some View {
        root(ZStack(alignment: .bottom) {
            NavigationStack { PRDetailView(item: selected) }
            Color.black.opacity(0.47).ignoresSafeArea()
            MergeSheet(account: MockupFixtures.work, key: selected.summary.key, baseBranch: "main", headOid: MockupFixtures.headOid,
                       method: .squash, isBusy: false, onConfirm: { _ in }, onCancel: {})
                .background(Primer.bg, in: UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22))
        })
    }

    private func root<V: View>(_ v: V) -> some View {
        v.environmentObject(store).environmentObject(env).environmentObject(inbox).environmentObject(NotificationRouter()).preferredColorScheme(.dark).environment(\.colorScheme, .dark)
    }
}

enum MockupFixtures {
    static let personal = Account(id: AccountID("personal"), login: "AnthonyPluth", label: "Personal", color: .blue, connection: .githubApp)
    static let work = Account(id: AccountID("work"), login: "apluth-acme", label: "Work", color: .orange, connection: .pat, orgs: ["acme"])
    static let headOid = "3f9c1e2a7b4d5e6f8091a2b3c4d5e6f708192a3b"

    private static func pr(_ node: String, _ owner: String, _ repo: String, _ n: Int, _ title: String, by: String, ago: TimeInterval,
                           draft: Bool = false, rollup: CheckRollup?, decision: String? = nil, now: Date) -> PullRequestSummary {
        PullRequestSummary(nodeID: node, key: PRKey(owner: owner, repo: repo, number: n), title: title,
                           url: URL(string: "https://github.com/\(owner)/\(repo)/pull/\(n)")!, author: by, baseBranch: "main",
                           status: PRStatus(state: .open, isDraft: draft, mergeable: .mergeable, rollup: rollup, headOid: node == "PR_471" ? headOid : "0000000000"),
                           reviewDecision: decision, updatedAt: now.addingTimeInterval(-ago - 30))
    }

    @MainActor static func make(now: Date = Date()) -> MockupScene {
        let m: TimeInterval = 60, h: TimeInterval = 3600, d: TimeInterval = 86_400
        let store = AccountStore(store: MemoryKeyValueStore())
        store.add(personal)
        store.add(work)

        let pr471 = pr("PR_471", "acme", "api", 471, "Cache org membership lookups", by: "you", ago: d, rollup: .success, decision: "APPROVED", now: now)
        let snapshots: [AccountID: InboxSnapshot] = [
            work.id: InboxSnapshot(sections: [
                .needsReview: [
                    pr("PR_482", "acme", "billing", 482, "Add retry to webhook delivery", by: "dana", ago: 2 * h, rollup: .success, decision: "REVIEW_REQUIRED", now: now),
                    pr("PR_455", "acme", "api", 455, "WIP: migrate sessions to Redis", by: "marcus", ago: d, draft: true, rollup: .pending, now: now),
                ],
                .yours: [pr471],
                .assignedOrMentioned: [pr("PR_90", "acme", "handbook", 90, "Docs: explain the on-call rotation", by: "priya", ago: 3 * d, rollup: .success, now: now)],
            ]),
            personal.id: InboxSnapshot(sections: [
                .yours: [
                    pr("PR_31", "AnthonyPluth", "mergeable", 31, "Fix inbox sort when two PRs tie", by: "you", ago: 12 * m, rollup: .success, decision: "APPROVED", now: now),
                    pr("PR_208", "AnthonyPluth", "darkroom", 208, "Bump wrangler to 3.91", by: "dependabot", ago: 5 * h, rollup: .failure, now: now),
                ],
            ]),
        ]
        let inbox = InboxModel(fixture: snapshots)
        let selected = inbox.merged[.yours]!.first { $0.summary.nodeID == "PR_471" }!

        var detailSummary = pr471
        detailSummary.author = "apluth-acme"
        let detail = PullRequestDetail(
            summary: detailSummary,
            body: "Org membership was fetched on every request. This caches it for 60 seconds per user and clears the cache on the `membership` webhook.",
            timeline: [
                TimelineItem(author: "priya", date: now.addingTimeInterval(-h), kind: .review, reviewState: "APPROVED", body: "Looks good, thanks for the test."),
                TimelineItem(author: "dana", date: now.addingTimeInterval(-40 * m), kind: .comment, body: "Can we log cache hits?"),
            ],
            checks: [
                CheckContext(name: "build", state: "SUCCESS"),
                CheckContext(name: "test (unit)", state: "SUCCESS"),
                CheckContext(name: "lint", state: "SUCCESS"),
            ])
        // 4 files, +86 -12, as the mockup says.
        let files = [
            ChangedFile(path: "src/membership/cache.ts", status: "added", additions: 54, deletions: 0,
                        patch: "@@ -0,0 +1,3 @@\n+export const cache = new Map<string, number>()\n+export const TTL_MS = 60_000\n+export function clear(user: string) { cache.delete(user) }"),
            ChangedFile(path: "src/membership/lookup.ts", status: "modified", additions: 14, deletions: 9),
            ChangedFile(path: "src/webhooks/membership.ts", status: "modified", additions: 6, deletions: 2),
            ChangedFile(path: "test/membership.test.ts", status: "added", additions: 12, deletions: 1),
        ]
        let env = AppEnvironment(store: store)
        env.detailFixtures[pr471.nodeID] = PRDetailFixture(detail: detail, files: files)
        return MockupScene(store: store, env: env, inbox: inbox, selected: selected)
    }
}
