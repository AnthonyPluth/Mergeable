import SwiftUI
import MergeableCore

@main
struct MergeableApp: App {
    @StateObject private var accounts: AccountStore
    @StateObject private var env: AppEnvironment

    init() {
        let store = AccountStore()
        _accounts = StateObject(wrappedValue: store)
        _env = StateObject(wrappedValue: AppEnvironment(store: store))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(accounts)
                .environmentObject(env)
                .preferredColorScheme(.dark)
        }
        #if os(macOS)
        .defaultSize(width: 1120, height: 700)
        #endif
    }
}

struct RootView: View {
    @EnvironmentObject var store: AccountStore
    @EnvironmentObject var env: AppEnvironment
    @StateObject private var inbox: InboxModel
    @State private var tab: InboxTab = .all
    @State private var showAccounts = false
    #if os(macOS)
    @State private var selection: InboxItem?
    #endif

    /// The defaults are what the app uses; the screenshot harness passes fixture data.
    @MainActor init(inbox: InboxModel? = nil, selection: InboxItem? = nil) {
        _inbox = StateObject(wrappedValue: inbox ?? InboxModel())
        #if os(macOS)
        _selection = State(initialValue: selection)
        #endif
    }

    var body: some View {
        #if os(macOS)
        NavigationSplitView {
            sidebar
        } content: {
            InboxView(model: inbox, tab: $tab, showTabPicker: false, selection: $selection)
                .navigationSplitViewColumnWidth(min: 320, ideal: 380)
        } detail: {
            if let selection {
                PRDetailView(item: selection).id(selection.id)
            } else {
                ContentUnavailableView("Select a pull request", systemImage: "arrow.triangle.pull")
            }
        }
        .sheet(isPresented: $showAccounts) { NavigationStack { AccountsView(keychain: env.keychain) }.frame(minWidth: 480, minHeight: 520) }
        #else
        NavigationStack {
            InboxView(model: inbox, tab: $tab)
                .navigationDestination(for: InboxItem.self) { PRDetailView(item: $0) }
                .toolbar { ToolbarItem(placement: .topBarLeading) { Button { showAccounts = true } label: { Label("Accounts", systemImage: "person.2") } } }
        }
        .sheet(isPresented: $showAccounts) { NavigationStack { AccountsView(keychain: env.keychain) } }
        #endif
    }

    #if os(macOS)
    private var sidebar: some View {
        List(selection: $tab) {
            Section("Accounts") {
                Label("All", systemImage: "tray.full").tag(InboxTab.all)
                ForEach(store.accounts) { a in
                    HStack { AccountBadge(account: a); Text(a.login).lineLimit(1) }.tag(InboxTab.account(a.id))
                }
            }
            Section {
                Button { showAccounts = true } label: { Label("Manage accounts", systemImage: "gearshape") }.buttonStyle(.plain)
            }
        }
        .navigationSplitViewColumnWidth(min: 190, ideal: 210)
    }
    #endif
}
