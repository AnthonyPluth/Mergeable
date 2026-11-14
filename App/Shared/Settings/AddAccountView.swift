import SwiftUI
import MergeableCore

struct AddAccountView: View {
    enum Kind: String, CaseIterable, Identifiable { case githubApp = "GitHub App", pat = "Token (PAT)"; var id: String { rawValue } }

    let keychain: KeychainStore
    @EnvironmentObject var store: AccountStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var kind: Kind = .githubApp
    @State private var label = ""
    @State private var color: AccountColor = .blue
    @State private var opensInLinear = false
    @State private var deviceOnly = false
    @State private var pat = ""
    @State private var code: DeviceCode?
    @State private var busy = false
    @State private var error: String?
    @State private var flowTask: Task<Void, Never>?

    var body: some View {
        Form {
            Picker("Connect with", selection: $kind) {
                ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            Section("Appearance") {
                TextField("Label (for example Personal)", text: $label)
                Picker("Color", selection: $color) {
                    ForEach(AccountColor.allCases, id: \.self) { c in Text(c.rawValue.capitalized).tag(c) }
                }
            }

            switch kind {
            case .githubApp:
                Section {
                    if let code {
                        LabeledContent("Your code") { Text(code.userCode).font(.title3.monospaced().weight(.semibold)).textSelection(.enabled) }
                        Button("Open \(code.verificationURL.host() ?? "github.com")") { openURL(code.verificationURL) }
                        HStack { ProgressView(); Text("Waiting for you to approve on GitHub…").foregroundStyle(.secondary) }
                    } else {
                        Button("Sign in with GitHub") { startDeviceFlow() }.disabled(busy)
                    }
                } footer: { Text("Personal accounts use the Mergeable GitHub App, so alerts arrive as pushes.") }
            case .pat:
                Section {
                    SecureField("Personal access token", text: $pat)
                    ForEach(AppConfig.patPermissions, id: \.self) { Label($0, systemImage: "checkmark").font(.footnote) }
                } header: { Text("Token") } footer: { Text(AppConfig.pollingNote) }
                Section { Button("Add account") { addPAT() }.disabled(pat.isEmpty || busy) }
            }

            Section {
                Toggle("Open in Linear", isOn: $opensInLinear)
                Toggle("This device only", isOn: $deviceOnly)
            } footer: { Text("Tokens sync between your devices through iCloud Keychain unless this device only is on.") }

            if let error { Section { Text(error).foregroundStyle(Primer.danger) } }
        }
        .navigationTitle("Add account")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { flowTask?.cancel(); dismiss() } } }
        .onDisappear { flowTask?.cancel() }
    }

    private var finalLabel: String { label.isEmpty ? (kind == .githubApp ? "Personal" : "Work") : label }

    private func finish(login: String, orgs: [String], connection: Connection) -> AccountID {
        let id = AccountID(UUID().uuidString.lowercased())
        store.add(Account(id: id, login: login, label: finalLabel, color: color, connection: connection, orgs: orgs, opensInLinear: opensInLinear))
        return id
    }

    private func startDeviceFlow() {
        busy = true; error = nil
        let flow = DeviceFlow(clientID: AppConfig.githubAppClientID, transport: URLSessionTransport())
        flowTask = Task {
            do {
                let c = try await flow.start()
                code = c
                openURL(c.verificationURL)
                let tokens = try await flow.poll(c, sleep: { try? await Task.sleep(for: .seconds($0)) })
                let who = try await fetchIdentity(token: tokens.accessToken, transport: URLSessionTransport())
                let id = finish(login: who.login, orgs: who.orgs, connection: .githubApp)
                try await keychain.saveApp(tokens, account: id, synchronizable: !deviceOnly)
                dismiss()
            } catch is CancellationError {
            } catch DeviceFlowError.denied { error = "Access was denied on GitHub." }
            catch DeviceFlowError.expired { error = "The code expired. Try again."; code = nil }
            catch { self.error = "Couldn't sign in: \(error.localizedDescription)"; code = nil }
            busy = false
        }
    }

    private func addPAT() {
        busy = true; error = nil
        let token = pat.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let who = try await fetchIdentity(token: token, transport: URLSessionTransport())
                let id = finish(login: who.login, orgs: who.orgs, connection: .pat)
                try await keychain.savePAT(token, account: id, synchronizable: !deviceOnly)
                dismiss()
            } catch { self.error = "That token didn't work: \(error.localizedDescription)" }
            busy = false
        }
    }
}
