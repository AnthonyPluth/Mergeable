import Foundation
import Security
import MergeableCore

/// The Keychain calls KeychainStore needs, so tests can record them and CI doesn't need a signed app.
protocol KeychainBackend: Sendable {
    func write(_ data: Data, key: String, synchronizable: Bool) throws
    func read(key: String) throws -> Data?
    func delete(key: String) throws
}

struct KeychainError: Error, Equatable { var status: OSStatus }

struct SecItemBackend: KeychainBackend {
    var service = AppConfig.keychainService

    private func base(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key,
         kSecUseDataProtectionKeychain as String: true]
    }

    func write(_ data: Data, key: String, synchronizable: Bool) throws {
        try delete(key: key)   // the old copy may have the other sync setting
        var q = base(key)
        q[kSecValueData as String] = data
        q[kSecAttrSynchronizable as String] = synchronizable ? kCFBooleanTrue! : kCFBooleanFalse!
        q[kSecAttrAccessible as String] = synchronizable ? kSecAttrAccessibleAfterFirstUnlock : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let s = SecItemAdd(q as CFDictionary, nil)
        guard s == errSecSuccess else { throw KeychainError(status: s) }
    }

    func read(key: String) throws -> Data? {
        var q = base(key)
        q[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let s = SecItemCopyMatching(q as CFDictionary, &out)
        if s == errSecItemNotFound { return nil }
        guard s == errSecSuccess else { throw KeychainError(status: s) }
        return out as? Data
    }

    func delete(key: String) throws {
        var q = base(key)
        q[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        let s = SecItemDelete(q as CFDictionary)
        guard s == errSecSuccess || s == errSecItemNotFound else { throw KeychainError(status: s) }
    }
}

/// What is stored under one key: a pasted PAT, or a GitHub App's token pair, plus whether it syncs through iCloud.
struct StoredToken: Codable, Equatable {
    enum Kind: String, Codable { case pat, app }
    var kind: Kind
    var pat: String?
    var app: AppTokens?
    var synchronizable: Bool
}

enum TokenError: Error, Equatable { case missing(AccountID), refreshFailed(AccountID) }

/// Tokens live only here. Items are keyed `token.<accountID>.<owner or *>`. A token is only ever returned for the
/// account asked about; there is no fallback to another account.
actor KeychainStore: TokenProvider {
    static let refreshMargin: TimeInterval = 5 * 60

    private let backend: KeychainBackend
    private let flow: DeviceFlow?
    private let now: @Sendable () -> Date

    init(backend: KeychainBackend = SecItemBackend(), flow: DeviceFlow? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        self.backend = backend; self.flow = flow; self.now = now
    }

    static func key(_ account: AccountID, owner: String?) -> String {
        let o = (owner ?? "").lowercased()
        return "token.\(account.rawValue).\(o.isEmpty ? "*" : o)"
    }

    func savePAT(_ token: String, account: AccountID, owner: String? = nil, synchronizable: Bool) throws {
        try store(StoredToken(kind: .pat, pat: token, app: nil, synchronizable: synchronizable), key: Self.key(account, owner: owner))
    }

    func saveApp(_ tokens: AppTokens, account: AccountID, synchronizable: Bool) throws {
        try store(StoredToken(kind: .app, pat: nil, app: tokens, synchronizable: synchronizable), key: Self.key(account, owner: nil))
    }

    func remove(account: AccountID, owners: [String]) throws {
        for o in [nil] + owners.map({ Optional($0) }) { try backend.delete(key: Self.key(account, owner: o)) }
    }

    /// Re-saves an account's tokens with a different sync setting (the "This device only" switch).
    func setSynchronizable(_ sync: Bool, account: AccountID, owners: [String]) throws {
        for o in [nil] + owners.map({ Optional($0) }) {
            let k = Self.key(account, owner: o)
            guard var t = try load(k) else { continue }
            t.synchronizable = sync
            try store(t, key: k)
        }
    }

    func isSynchronizable(account: AccountID) throws -> Bool? { try load(Self.key(account, owner: nil))?.synchronizable }

    func token(for account: AccountID, owner: String) async throws -> String {
        let specific = Self.key(account, owner: owner)
        let key = try backend.read(key: specific) != nil ? specific : Self.key(account, owner: nil)
        guard var stored = try load(key) else { throw TokenError.missing(account) }
        switch stored.kind {
        case .pat:
            guard let p = stored.pat else { throw TokenError.missing(account) }
            return p
        case .app:
            guard var tokens = stored.app else { throw TokenError.missing(account) }
            if tokens.accessExpiry.timeIntervalSince(now()) < Self.refreshMargin {
                guard let flow, tokens.refreshExpiry > now() else { throw TokenError.refreshFailed(account) }
                do { tokens = try await flow.refresh(tokens.refreshToken) } catch { throw TokenError.refreshFailed(account) }
                stored.app = tokens
                try store(stored, key: key)
            }
            return tokens.accessToken
        }
    }

    private func store(_ t: StoredToken, key: String) throws {
        try backend.write(try JSONEncoder().encode(t), key: key, synchronizable: t.synchronizable)
    }
    private func load(_ key: String) throws -> StoredToken? {
        try backend.read(key: key).map { try JSONDecoder().decode(StoredToken.self, from: $0) }
    }
}
