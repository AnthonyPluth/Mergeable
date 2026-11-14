import Foundation

/// The relay URL (not secret) and the registration secret (Keychain, through the same backend as account tokens).
final class RelaySettings: @unchecked Sendable {
    static let secretKey = "relay.registration-secret"
    static let urlKey = "relay.url"

    private let backend: KeychainBackend
    private let defaults: KeyValueStore

    init(backend: KeychainBackend = SecItemBackend(), defaults: KeyValueStore) {
        self.backend = backend; self.defaults = defaults
    }

    var urlString: String {
        defaults.data(forKey: Self.urlKey).flatMap { String(data: $0, encoding: .utf8) } ?? RelayConfig.defaultURL
    }

    var secret: String? {
        (try? backend.read(key: Self.secretKey)).flatMap { String(data: $0, encoding: .utf8) }
    }

    func save(urlString: String, secret: String) throws {
        defaults.set(urlString.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8), forKey: Self.urlKey)
        let s = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { try backend.delete(key: Self.secretKey) }
        else { try backend.write(Data(s.utf8), key: Self.secretKey, synchronizable: true) }
    }

    /// nil until both a valid https URL and a secret are saved.
    var config: RelayConfig? {
        guard let secret, !secret.isEmpty, let url = URL(string: urlString), url.scheme == "https", url.host != nil else { return nil }
        return RelayConfig(baseURL: url, secret: secret)
    }
}
