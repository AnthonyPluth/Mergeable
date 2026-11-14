import SwiftUI
import MergeableCore

@main
struct MergeableApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #elseif os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif
    @StateObject private var accounts: AccountStore
    @StateObject private var env: AppEnvironment
    @StateObject private var services: AppServices
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let shared = AppServices.shared
        _accounts = StateObject(wrappedValue: shared.accounts)
        _env = StateObject(wrappedValue: shared.env)
        _services = StateObject(wrappedValue: shared)
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environmentObject(accounts)
                .environmentObject(env)
                .environmentObject(services)
                .environmentObject(services.inbox)
                .environmentObject(services.router)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: Task { await services.refresh(.foreground) }
            #if os(iOS)
            case .background: BackgroundRefresh.schedule()
            #endif
            default: break
            }
        }
        #if os(macOS)
        .defaultSize(width: 1120, height: 700)
        #endif

        #if os(macOS)
        MenuBarExtra {
            MenuBarContent(services: services, accounts: accounts)
        } label: {
            MenuBarLabel(services: services)
        }
        #endif
    }
}

struct RootView: View {
    @EnvironmentObject var store: AccountStore
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var sharedInbox: InboxModel
    @EnvironmentObject var router: NotificationRouter
    @Environment(\.openURL) private var openURL
    /// The screenshot harness passes fixture data; the app uses the shared inbox from the environment.
    private let fixtureInbox: InboxModel?
    private var inbox: InboxModel { fixtureInbox ?? sharedInbox }
    @State private var tab: InboxTab = .all
    @State private var showAccounts = false
    #if os(macOS)
    @State private var selection: InboxItem?
    #else
    @State private var path: [InboxItem] = []
    #endif

    /// The defaults are what the app uses; the screenshot harness passes fixture data.
    @MainActor init(inbox: InboxModel? = nil, selection: InboxItem? = nil) {
        fixtureInbox = inbox
        #if os(macOS)
        _selection = State(initialValue: selection)
        #endif
    }

    var body: some View {
        content
            .onChange(of: router.pending) { _, payload in
                if let payload { Task { await open(payload) } }
            }
            .task { if let payload = router.pending { await open(payload) } }
    }

    /// A tapped notification: show the PR if the inbox has it (loading the inbox first on a cold launch), else open it on github.com.
    private func open(_ payload: NotificationPayload) async {
        router.pending = nil
        if inbox.lastRefreshed == nil { await AppServices.shared.refresh(.foreground) }
        if let item = payload.match(in: inbox.merged) {
            #if os(macOS)
            selection = item
            #else
            path = [item]
            #endif
        } else if let url = payload.url {
            openURL(url)
        }
    }

    @ViewBuilder private var content: some View {
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
        NavigationStack(path: $path) {
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
