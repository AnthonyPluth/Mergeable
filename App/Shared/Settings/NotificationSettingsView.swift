import SwiftUI
import MergeableCore

/// Settings, Notifications: relay URL and registration secret, per-account alerts, launch at login (Mac), Diagnostics.
struct NotificationSettingsView: View {
    @EnvironmentObject var store: AccountStore
    @EnvironmentObject var services: AppServices
    @State private var relayURL = ""
    @State private var secret = ""
    @State private var message: String?
    @State private var launchAtLogin = false

    var body: some View {
        Form {
            Section {
                TextField("Relay URL", text: $relayURL)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                SecureField("Registration secret", text: $secret)
                Button("Save and register") { save() }.disabled(relayURL.isEmpty)
                PushStatusRow(push: services.push)
                if let message { Text(message).font(.footnote).foregroundStyle(Primer.danger) }
            } header: { Text("Push for GitHub App accounts") } footer: {
                Text("The secret is kept in your Keychain. The relay only sends alerts for accounts connected with the GitHub App.")
            }

            Section {
                ForEach(store.accounts) { a in
                    if a.connection == .pat {
                        Toggle("@\(a.login)", isOn: Binding(get: { services.alertsEnabled(a.id) }, set: { services.setAlerts($0, for: a.id) }))
                    } else {
                        LabeledContent("@\(a.login)", value: "Push from relay")
                    }
                }
                if store.accounts.isEmpty { Text("No accounts yet").foregroundStyle(.secondary) }
            } header: { Text("Alerts on this device") } footer: {
                Text(AppConfig.pollingNote)
            }

            #if os(macOS)
            Section {
                Toggle("Start at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do { try LaunchAtLogin.set(on); message = nil }
                        catch { message = "Couldn't change start at login: \(error.localizedDescription)"; launchAtLogin = LaunchAtLogin.isEnabled }
                    }
            } header: { Text("Mac") } footer: { Text("Keeps the menu bar item and the 15-minute check running.") }
            #endif

            Section {
                if services.refreshEntries.isEmpty { Text("No refreshes yet").foregroundStyle(.secondary) }
                ForEach(services.refreshEntries.prefix(20)) { e in
                    LabeledContent(e.date.formatted(date: .abbreviated, time: .standard), value: e.source.rawValue)
                }
            } header: { Text("Diagnostics") } footer: {
                Text("Each refresh and what started it. Background means iOS ran the scheduled refresh.")
            }
        }
        .navigationTitle("Notifications")
        .onAppear {
            relayURL = services.relaySettings.urlString
            secret = services.relaySettings.secret ?? ""
            #if os(macOS)
            launchAtLogin = LaunchAtLogin.isEnabled
            #endif
        }
    }

    private func save() {
        do {
            try services.push.saveSettings(urlString: relayURL, secret: secret)
            message = nil
        } catch {
            message = "Couldn't save: \(error.localizedDescription)"
        }
    }
}

private struct PushStatusRow: View {
    @ObservedObject var push: PushRegistration
    var body: some View {
        Text(push.status.text).font(.footnote).foregroundStyle(.secondary)
    }
}
