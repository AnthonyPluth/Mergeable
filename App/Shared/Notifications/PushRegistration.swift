import Foundation
import SwiftUI
import MergeableCore
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Keeps this device's APNs token registered with the relay. The token arrives from the app delegate; the relay URL and
/// secret come from Settings. Registration is retried whenever either one changes.
@MainActor
final class PushRegistration: ObservableObject {
    enum Status: Equatable {
        case needsRelaySettings, waitingForToken, registered, failed(String)
        var text: String {
            switch self {
            case .needsRelaySettings: return "Enter the relay URL and registration secret to turn on push."
            case .waitingForToken: return "Waiting for Apple to issue a push token. Push needs the signed build with the Push capability."
            case .registered: return "Registered with the relay."
            case .failed(let m): return "Registration failed: \(m)"
            }
        }
    }

    @Published private(set) var status: Status = .needsRelaySettings
    @Published private(set) var token: String?

    private let settings: RelaySettings
    private let client: RelayClient

    init(settings: RelaySettings, client: RelayClient) {
        self.settings = settings; self.client = client
        status = settings.config == nil ? .needsRelaySettings : .waitingForToken
    }

    /// Called by the app delegate with the raw APNs token.
    func tokenReceived(_ raw: Data) {
        token = RelayClient.hex(raw)
        Task { await sync() }
    }

    func tokenFailed(_ error: Error) { status = .failed(error.localizedDescription) }

    func saveSettings(urlString: String, secret: String) throws {
        try settings.save(urlString: urlString, secret: secret)
        Task { await sync() }
    }

    /// Registers the current token if there is one and the relay is configured.
    func sync() async {
        guard let config = settings.config else { status = .needsRelaySettings; return }
        guard let token else { status = .waitingForToken; return }
        do {
            try await client.register(token: token, config: config)
            status = .registered
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Removes this device from the relay (DELETE /devices/<token>).
    func unregister() async {
        guard let config = settings.config, let token else { return }
        do {
            try await client.unregister(token: token, config: config)
            status = .waitingForToken
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Asks for permission, then for a token. Safe to call every launch.
    func requestAuthorizationAndRegister() async {
        guard await NotificationAuthorization.request() else { return }
        #if os(iOS)
        UIApplication.shared.registerForRemoteNotifications()
        #elseif os(macOS)
        NSApplication.shared.registerForRemoteNotifications()
        #endif
    }
}
