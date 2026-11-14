import Foundation

public enum Route: Equatable, Sendable { case account(AccountID), ambiguous([AccountID]), unowned }

public struct Router: Sendable {
    public var accounts: [Account]
    public var manualOwners: [String: AccountID]
    public var remembered: [PRKey: AccountID]

    public init(accounts: [Account], manualOwners: [String: AccountID] = [:], remembered: [PRKey: AccountID] = [:]) {
        self.accounts = accounts
        self.manualOwners = Dictionary(manualOwners.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
        self.remembered = remembered
    }

    /// manualOwners, then the one account that claims the owner (login or org), then several claimers = ambiguous,
    /// then unclaimed: the fetching account(s), `remembered`, or nothing. All owner comparisons ignore case.
    public func route(_ pr: PRKey, fetchedBy: Set<AccountID>) -> Route {
        let owner = pr.owner.lowercased()
        if let id = manualOwners[owner] { return .account(id) }
        let claimers = accounts.filter { $0.login.lowercased() == owner || $0.orgs.contains { $0.lowercased() == owner } }.map(\.id)
        if claimers.count == 1 { return .account(claimers[0]) }
        if claimers.count > 1 { return .ambiguous(claimers.sorted { $0.rawValue < $1.rawValue }) }
        if fetchedBy.count == 1, let only = fetchedBy.first { return .account(only) }
        if fetchedBy.count > 1 {
            if let r = remembered[pr], fetchedBy.contains(r) { return .account(r) }
            return .ambiguous(fetchedBy.sorted { $0.rawValue < $1.rawValue })
        }
        return .unowned
    }
}
