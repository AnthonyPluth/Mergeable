import Foundation
import SwiftUI
import MergeableCore

/// What the screens share: the Keychain-backed token provider and the one GitHub client.
@MainActor
final class AppEnvironment: ObservableObject {
    let keychain: KeychainStore
    let client: GitHubClient

    init(store: AccountStore) {
        let keychain = KeychainStore(flow: DeviceFlow(clientID: AppConfig.githubAppClientID, transport: URLSessionTransport()))
        self.keychain = keychain
        self.client = GitHubClient(transport: URLSessionTransport(), tokens: keychain, onUnauthorized: { [weak store] id in
            Task { @MainActor in store?.markNeedsAttention(id) }
        })
    }
}
