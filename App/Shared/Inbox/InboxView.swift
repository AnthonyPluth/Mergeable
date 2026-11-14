import SwiftUI
import MergeableCore

struct InboxView: View {
    @EnvironmentObject var store: AccountStore
    @EnvironmentObject var env: AppEnvironment
    @ObservedObject var model: InboxModel
    @Binding var tab: InboxTab
    var showTabPicker = true
    #if os(macOS)
    @Binding var selection: InboxItem?
    #endif

    private var merged: [InboxSection: [InboxItem]] { model.merged }

    var body: some View {
        VStack(spacing: 0) {
            if showTabPicker && store.accounts.count > 0 { tabPicker }
            if store.accounts.isEmpty {
                ContentUnavailableView("No accounts yet", systemImage: "person.crop.circle.badge.plus", description: Text("Add a GitHub account in Accounts to see your pull requests."))
            } else {
                list
            }
        }
        .background(Primer.bg)
        .navigationTitle("Inbox")
        .task { await refresh() }
        .toolbar { toolbarContent }
    }

    private func refresh() async { await model.refresh(accounts: store.accounts, client: env.client) }

    private var tabPicker: some View {
        Picker("Account", selection: $tab) {
            Text("All").tag(InboxTab.all)
            ForEach(store.accounts) { Text($0.label).tag(InboxTab.account($0.id)) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    private var list: some View {
        let loaded = InboxSection.allCases.contains { !InboxLogic.items(merged, in: tab, section: $0).isEmpty }
        return Group {
            #if os(macOS)
            List(selection: $selection) { content }.listStyle(.inset)
            #else
            List { content }.listStyle(.plain).refreshable { await refresh() }
            #endif
        }
        .overlay {
            if !loaded && !model.isLoading && model.errors.isEmpty {
                ContentUnavailableView("Nothing here", systemImage: "tray", description: Text("No open pull requests need you right now."))
            } else if !loaded && model.isLoading {
                ProgressView()
            }
        }
    }

    @ViewBuilder private var content: some View {
        ForEach(Array(model.errors.sorted { $0.key.rawValue < $1.key.rawValue }), id: \.key) { id, message in
            if let a = store.account(id) {
                Label("@\(a.login): \(message)", systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(Primer.attention)
            }
        }
        ForEach(InboxSection.allCases, id: \.self) { section in
            let items = InboxLogic.items(merged, in: tab, section: section)
            if !items.isEmpty {
                Section {
                    ForEach(items) { item in row(item) }
                } header: {
                    HStack(spacing: 6) {
                        Text(title(section))
                        Text("\(items.count)").font(.caption2).padding(.horizontal, 6).background(Primer.border, in: Capsule())
                    }
                }
            }
        }
    }

    @ViewBuilder private func row(_ item: InboxItem) -> some View {
        let r = PRRow(item: item, account: routedAccount(item))
        #if os(macOS)
        r.tag(item)
        #else
        NavigationLink(value: item) { r }
        #endif
    }

    private func routedAccount(_ item: InboxItem) -> Account? {
        if case .account(let id) = store.router.route(item.summary.key, fetchedBy: item.fetchedBy) { return store.account(id) }
        return nil
    }

    private func title(_ s: InboxSection) -> String {
        switch s {
        case .needsReview: "Needs your review"
        case .yours: "Your PRs"
        case .assignedOrMentioned: "Assigned or mentioned"
        }
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { Task { await refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }.disabled(model.isLoading)
        }
    }
}
