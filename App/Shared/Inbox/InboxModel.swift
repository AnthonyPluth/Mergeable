import Foundation
import SwiftUI
import MergeableCore

@MainActor
final class InboxModel: ObservableObject {
    @Published private(set) var snapshots: [AccountID: InboxSnapshot] = [:]
    @Published private(set) var errors: [AccountID: String] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var lastRefreshed: Date?

    var merged: [InboxSection: [InboxItem]] { InboxLogic.merge(snapshots) }

    func refresh(accounts: [Account], client: GitHubClient) async {
        isLoading = true
        defer { isLoading = false }
        let ids = Set(accounts.map(\.id))
        snapshots = snapshots.filter { ids.contains($0.key) }
        errors = errors.filter { ids.contains($0.key) }
        await withTaskGroup(of: (AccountID, InboxSnapshot?, String?).self) { group in
            for account in accounts {
                group.addTask {
                    do { return (account.id, try await client.inbox(for: account), nil) }
                    catch GitHubError.unauthorized { return (account.id, nil, "Token stopped working") }
                    catch { return (account.id, nil, error.localizedDescription) }
                }
            }
            for await (id, snap, err) in group {
                if let snap { snapshots[id] = snap; errors[id] = nil } else { errors[id] = err }
            }
        }
        lastRefreshed = Date()
    }
}
