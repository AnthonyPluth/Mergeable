import Foundation
import SwiftUI
import MergeableCore

/// Where the non-secret account data lives. `NSUbiquitousKeyValueStore` syncs it between devices.
protocol KeyValueStore: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
}

final class UbiquitousKeyValueStore: KeyValueStore {
    private let store = NSUbiquitousKeyValueStore.default
    func data(forKey key: String) -> Data? { store.data(forKey: key) }
    func set(_ data: Data?, forKey key: String) { store.set(data, forKey: key); store.synchronize() }
}

final class MemoryKeyValueStore: KeyValueStore {
    private var d: [String: Data] = [:]
    func data(forKey key: String) -> Data? { d[key] }
    func set(_ data: Data?, forKey key: String) { d[key] = data }
}

struct OwnerClaim: Equatable, Identifiable {
    var owner: String
    var claimedBy: [AccountID]
    var assigned: AccountID?
    var id: String { owner }
    /// Claimed by two or more accounts and not yet assigned by hand: writes there are refused.
    var isAmbiguous: Bool { claimedBy.count > 1 && assigned == nil }
}

@MainActor
final class AccountStore: ObservableObject {
    private struct Saved: Codable {
        var accounts: [Account] = []
        var manualOwners: [String: AccountID] = [:]
        var remembered: [String: AccountID] = [:]   // "owner/repo#n" -> account
    }

    @Published private(set) var accounts: [Account] = []
    @Published private(set) var manualOwners: [String: AccountID] = [:]
    @Published private(set) var remembered: [PRKey: AccountID] = [:]
    @Published private(set) var needsAttention: Set<AccountID> = []

    private let kv: KeyValueStore
    private static let storageKey = "accounts.v1"
    private var observer: NSObjectProtocol?

    init(store: KeyValueStore = UbiquitousKeyValueStore()) {
        kv = store
        load()
        if store is UbiquitousKeyValueStore {
            observer = NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.load() }
            }
        }
    }

    var router: Router { Router(accounts: accounts, manualOwners: manualOwners, remembered: remembered) }

    func account(_ id: AccountID) -> Account? { accounts.first { $0.id == id } }

    func add(_ a: Account) { accounts.removeAll { $0.id == a.id }; accounts.append(a); save() }
    func update(_ a: Account) { if let i = accounts.firstIndex(where: { $0.id == a.id }) { accounts[i] = a; save() } }
    func remove(_ id: AccountID) {
        accounts.removeAll { $0.id == id }
        manualOwners = manualOwners.filter { $0.value != id }
        remembered = remembered.filter { $0.value != id }
        needsAttention.remove(id)
        save()
    }

    func markNeedsAttention(_ id: AccountID) { needsAttention.insert(id) }
    func clearAttention(_ id: AccountID) { needsAttention.remove(id) }

    func assign(owner: String, to id: AccountID?) {
        let o = owner.lowercased()
        if let id { manualOwners[o] = id } else { manualOwners.removeValue(forKey: o) }
        save()
    }

    func remember(_ pr: PRKey, account: AccountID) { remembered[pr] = account; save() }

    /// Every owner an account claims (its login and orgs) or that was assigned by hand.
    var ownerClaims: [OwnerClaim] {
        var claims: [String: [AccountID]] = [:]
        for a in accounts { for o in [a.login] + a.orgs { claims[o.lowercased(), default: []].append(a.id) } }
        for o in manualOwners.keys where claims[o] == nil { claims[o] = [] }
        return claims.map { OwnerClaim(owner: $0.key, claimedBy: $0.value, assigned: manualOwners[$0.key]) }.sorted { $0.owner < $1.owner }
    }

    var ambiguousOwners: [OwnerClaim] { ownerClaims.filter(\.isAmbiguous) }

    private func load() {
        guard let d = kv.data(forKey: Self.storageKey), let s = try? JSONDecoder().decode(Saved.self, from: d) else { return }
        accounts = s.accounts
        manualOwners = s.manualOwners
        remembered = Dictionary(uniqueKeysWithValues: s.remembered.compactMap { k, v in Self.parse(k).map { ($0, v) } })
    }

    private func save() {
        let s = Saved(accounts: accounts, manualOwners: manualOwners, remembered: Dictionary(uniqueKeysWithValues: remembered.map { (Self.encode($0.key), $0.value) }))
        kv.set(try? JSONEncoder().encode(s), forKey: Self.storageKey)
    }

    static func encode(_ k: PRKey) -> String { "\(k.owner)/\(k.repo)#\(k.number)" }
    static func parse(_ s: String) -> PRKey? {
        let hash = s.split(separator: "#"); guard hash.count == 2, let n = Int(hash[1]) else { return nil }
        let parts = hash[0].split(separator: "/"); guard parts.count == 2 else { return nil }
        return PRKey(owner: String(parts[0]), repo: String(parts[1]), number: n)
    }
}

extension AccountColor {
    var color: Color {
        switch self {
        case .blue: .blue
        case .orange: .orange
        case .green: .green
        case .purple: .purple
        case .red: .red
        case .gray: .gray
        }
    }
}
