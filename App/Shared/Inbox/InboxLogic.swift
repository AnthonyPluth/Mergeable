import Foundation
import MergeableCore

/// One PR in the inbox, with every account whose queries returned it (the router needs that to pick who acts).
struct InboxItem: Identifiable, Hashable {
    var summary: PullRequestSummary
    var section: InboxSection
    var fetchedBy: Set<AccountID>
    var id: String { "\(section.rawValue):\(summary.nodeID)" }
}

enum InboxTab: Hashable { case all, account(AccountID) }

enum ActorResolution: Equatable {
    case acting(AccountID)
    case choose([AccountID])
    case readOnly(String)
}

enum CheckVisual: Equatable { case success, failure, pending }

enum InboxLogic {
    /// All accounts' snapshots merged per section: a PR several accounts returned appears once, newest first.
    static func merge(_ snapshots: [AccountID: InboxSnapshot]) -> [InboxSection: [InboxItem]] {
        var out: [InboxSection: [InboxItem]] = [:]
        for section in InboxSection.allCases {
            var byNode: [String: InboxItem] = [:]
            for (account, snap) in snapshots {
                for pr in snap.sections[section] ?? [] {
                    if var existing = byNode[pr.nodeID] { existing.fetchedBy.insert(account); byNode[pr.nodeID] = existing }
                    else { byNode[pr.nodeID] = InboxItem(summary: pr, section: section, fetchedBy: [account]) }
                }
            }
            out[section] = byNode.values.sorted { $0.summary.updatedAt != $1.summary.updatedAt ? $0.summary.updatedAt > $1.summary.updatedAt : $0.summary.nodeID < $1.summary.nodeID }
        }
        return out
    }

    static func items(_ merged: [InboxSection: [InboxItem]], in tab: InboxTab, section: InboxSection) -> [InboxItem] {
        let all = merged[section] ?? []
        switch tab {
        case .all: return all
        case .account(let id): return all.filter { $0.fetchedBy.contains(id) }
        }
    }

    /// Who acts on this PR, decided at the moment of the tap. Never guesses: an owner claimed by two accounts and
    /// not assigned by hand is refused, and an owner nobody has is read-only.
    static func resolveActor(key: PRKey, fetchedBy: Set<AccountID>, router: Router, claims: [OwnerClaim]) -> ActorResolution {
        switch router.route(key, fetchedBy: fetchedBy) {
        case .account(let id): return .acting(id)
        case .ambiguous(let ids):
            if claims.first(where: { $0.owner == key.owner })?.isAmbiguous == true {
                return .readOnly("Two accounts claim \(key.owner). Assign it in Accounts, Owner map before acting here.")
            }
            return .choose(ids)
        case .unowned:
            return .readOnly("None of your accounts owns \(key.owner), so this pull request is read-only.")
        }
    }

    /// The account used to read a PR: the routed one, else any account that returned it.
    static func readAccount(key: PRKey, fetchedBy: Set<AccountID>, router: Router) -> AccountID? {
        if case .account(let id) = router.route(key, fetchedBy: fetchedBy) { return id }
        return fetchedBy.sorted { $0.rawValue < $1.rawValue }.first
    }

    static func visualState(_ s: PRStatus) -> PRVisualState {
        switch s.state {
        case .merged: .merged
        case .closed: .closed
        case .open: s.isDraft ? .draft : .open
        }
    }

    static func checkVisual(_ state: String) -> CheckVisual {
        switch state.uppercased() {
        case "SUCCESS", "NEUTRAL", "SKIPPED": .success
        case "FAILURE", "ERROR", "TIMED_OUT", "CANCELLED", "STARTUP_FAILURE", "ACTION_REQUIRED": .failure
        default: .pending
        }
    }

    static func rollupVisual(_ r: CheckRollup?) -> CheckVisual? {
        switch r {
        case nil: nil
        case .success: .success
        case .failure, .error: .failure
        default: .pending
        }
    }

    /// Short relative age: now, 5m, 3h, 2d, 4w, 1y.
    static func age(from date: Date, now: Date = Date()) -> String {
        let s = max(0, Int(now.timeIntervalSince(date)))
        switch s {
        case ..<60: return "now"
        case ..<3600: return "\(s / 60)m"
        case ..<86_400: return "\(s / 3600)h"
        case ..<604_800: return "\(s / 86_400)d"
        case ..<31_536_000: return "\(s / 604_800)w"
        default: return "\(s / 31_536_000)y"
        }
    }

    /// `https://linear.review/<owner>/<repo>/pull/<number>`: the PR link with github.com swapped for linear.review.
    static func linearURL(_ key: PRKey) -> URL? { URL(string: "https://linear.review/\(key.owner)/\(key.repo)/pull/\(key.number)") }
    static func githubFilesURL(_ key: PRKey) -> URL? { URL(string: "https://github.com/\(key.owner)/\(key.repo)/pull/\(key.number)/files") }
}

/// Button titles name the acting account, as the Global Constraints require.
enum ActionTitle {
    static func comment(_ login: String) -> String { "Comment as @\(login)" }
    static func approve(_ login: String) -> String { "Approve as @\(login)" }
    static func requestChanges(_ login: String) -> String { "Request changes as @\(login)" }
    static func merge(_ login: String) -> String { "Merge as @\(login)" }
    static func markReady(_ login: String) -> String { "Mark ready as @\(login)" }
    static func close(_ login: String) -> String { "Close as @\(login)" }
    static func reopen(_ login: String) -> String { "Reopen as @\(login)" }
}

/// The merge method last used per repository.
enum MergeMethodStore {
    static func key(_ k: PRKey) -> String { "mergeMethod.\(k.owner)/\(k.repo)" }
    static func method(for k: PRKey, defaults: UserDefaults = .standard) -> MergeMethod {
        defaults.string(forKey: key(k)).flatMap(MergeMethod.init(rawValue:)) ?? .squash
    }
    static func remember(_ m: MergeMethod, for k: PRKey, defaults: UserDefaults = .standard) { defaults.set(m.rawValue, forKey: key(k)) }
}
