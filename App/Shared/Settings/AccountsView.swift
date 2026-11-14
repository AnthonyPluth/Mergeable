import SwiftUI
import MergeableCore

struct AccountBadge: View {
    let account: Account
    var body: some View {
        Text(account.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 2)
            .foregroundStyle(account.color.color)
            .background(account.color.color.opacity(0.15), in: Capsule())
    }
}

struct AccountsView: View {
    let keychain: KeychainStore
    @EnvironmentObject var store: AccountStore
    @State private var adding = false

    var body: some View {
        List {
            Section("Accounts") {
                ForEach(store.accounts) { a in
                    NavigationLink {
                        AccountDetailView(account: a, keychain: keychain)
                    } label: {
                        HStack {
                            AccountBadge(account: a)
                            Text("@\(a.login)")
                            Spacer()
                            if store.needsAttention.contains(a.id) {
                                Label("Needs attention", systemImage: "exclamationmark.triangle.fill").labelStyle(.iconOnly).foregroundStyle(Primer.attention)
                            }
                        }
                    }
                }
                if store.accounts.isEmpty { Text("No accounts yet").foregroundStyle(.secondary) }
            }
            Section {
                NavigationLink("Notifications") { NotificationSettingsView() }
            }
            Section {
                NavigationLink {
                    OwnerMapView()
                } label: {
                    HStack {
                        Text("Owner map")
                        Spacer()
                        if !store.ambiguousOwners.isEmpty {
                            Text("\(store.ambiguousOwners.count) to assign").font(.caption).foregroundStyle(Primer.attention)
                        }
                    }
                }
            } footer: {
                Text("The repository owner decides which account acts on a pull request.")
            }
        }
        .navigationTitle("Accounts")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { adding = true } label: { Label("Add account", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $adding) {
            NavigationStack { AddAccountView(keychain: keychain) }
        }
    }
}
