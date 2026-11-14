import SwiftUI
import MergeableCore

@main
struct MergeableApp: App {
    @StateObject private var accounts = AccountStore()
    private let keychain = KeychainStore(flow: DeviceFlow(clientID: AppConfig.githubAppClientID, transport: URLSessionTransport()))

    var body: some Scene {
        WindowGroup {
            RootView(keychain: keychain).environmentObject(accounts)
        }
        #if os(macOS)
        .defaultSize(width: 1120, height: 700)
        #endif
    }
}

/// Placeholder shell until the inbox lands (Task 13): the accounts screens are reachable from here.
struct RootView: View {
    let keychain: KeychainStore
    @EnvironmentObject var accounts: AccountStore

    var body: some View {
        NavigationStack {
            AccountsView(keychain: keychain)
        }
    }
}
