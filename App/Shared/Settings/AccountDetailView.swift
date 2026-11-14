import SwiftUI
import MergeableCore

struct AccountDetailView: View {
    @State var account: Account
    let keychain: KeychainStore
    @EnvironmentObject var store: AccountStore
    @Environment(\.dismiss) private var dismiss
    @State private var deviceOnly = false
    @State private var confirmRemove = false
    @State private var newToken = ""
    @State private var error: String?

    var body: some View {
        Form {
            if store.needsAttention.contains(account.id) {
                Section {
                    Label("This account's token stopped working. Nothing falls back to another account.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Primer.attention)
                    if account.connection == .pat {
                        SecureField("New personal access token", text: $newToken)
                        Button("Replace token") { replaceToken() }.disabled(newToken.isEmpty)
                    }
                } header: { Text("Needs attention") }
            }
            Section("Account") {
                LabeledContent("Login", value: "@\(account.login)")
                LabeledContent("Connection", value: account.connection == .githubApp ? "GitHub App" : "Token (PAT)")
                if !account.orgs.isEmpty { LabeledContent("Organizations", value: account.orgs.joined(separator: ", ")) }
                TextField("Label", text: $account.label)
                Picker("Color", selection: $account.color) {
                    ForEach(AccountColor.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
            }
            Section {
                Toggle("Open in Linear", isOn: $account.opensInLinear)
                Toggle("This device only", isOn: $deviceOnly)
                    .onChange(of: deviceOnly) { _, on in setSync(!on) }
            } footer: {
                if account.connection == .pat { Text(AppConfig.pollingNote) }
            }
            if let error { Section { Text(error).foregroundStyle(Primer.danger) } }
            Section { Button("Remove account", role: .destructive) { confirmRemove = true } }
        }
        .navigationTitle("@\(account.login)")
        .onChange(of: account) { _, a in store.update(a) }
        .task { deviceOnly = ((try? await keychain.isSynchronizable(account: account.id)) ?? true) == false }
        .confirmationDialog("Remove @\(account.login)?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                Task {
                    try? await keychain.remove(account: account.id, owners: [account.login] + account.orgs)
                    store.remove(account.id)
                    dismiss()
                }
            }
        } message: { Text("Its token is deleted from this device and from iCloud Keychain.") }
    }

    private func setSync(_ sync: Bool) {
        Task { do { try await keychain.setSynchronizable(sync, account: account.id, owners: [account.login] + account.orgs) } catch { self.error = "Couldn't change sync: \(error.localizedDescription)" } }
    }

    private func replaceToken() {
        let t = newToken.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                _ = try await fetchIdentity(token: t, transport: URLSessionTransport())
                try await keychain.savePAT(t, account: account.id, synchronizable: !deviceOnly)
                store.clearAttention(account.id); newToken = ""
            } catch { self.error = "That token didn't work: \(error.localizedDescription)" }
        }
    }
}
