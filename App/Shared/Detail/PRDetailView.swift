import SwiftUI
import MergeableCore

struct PRDetailView: View {
    @EnvironmentObject var store: AccountStore
    @EnvironmentObject var env: AppEnvironment
    @StateObject private var model: PRDetailModel
    @Environment(\.openURL) private var openURL

    private enum Sheet: Identifiable { case comment, requestChanges, merge
        var id: Int { switch self { case .comment: 0; case .requestChanges: 1; case .merge: 2 } } }
    private enum Pending { case comment, approve, requestChanges, merge, markReady, close, reopen }

    @State private var sheet: Sheet?
    @State private var actor: Account?
    @State private var choosing: Pending?
    @State private var choices: [Account] = []
    @State private var showFiles = false

    init(item: InboxItem) { _model = StateObject(wrappedValue: PRDetailModel(item: item)) }

    private var summary: PullRequestSummary { model.detail?.summary ?? model.item.summary }
    private var resolution: ActorResolution {
        InboxLogic.resolveActor(key: model.key, fetchedBy: model.item.fetchedBy, router: store.router, claims: store.ownerClaims)
    }
    private var actingAccount: Account? {
        if case .acting(let id) = resolution { return store.account(id) }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                banners
                if let detail = model.detail {
                    checksCard(detail.checks)
                    card("Description") { Text(markdown(detail.body.isEmpty ? "No description provided." : detail.body)).font(.callout).padding(12).frame(maxWidth: .infinity, alignment: .leading) }
                    conversation(detail.timeline)
                    filesCard
                    if let a = actingAccount, a.opensInLinear, let url = InboxLogic.linearURL(model.key) {
                        Button { openURL(url) } label: { Label("Open in Linear", systemImage: "arrow.up.right.square") }
                    }
                } else if model.isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(40)
                }
            }
            .padding(16)
        }
        .background(Primer.bg)
        .navigationTitle("#\(model.key.number)")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .safeAreaInset(edge: .bottom, spacing: 0) { actions }
        .task {
            if let f = env.detailFixtures[model.item.summary.nodeID] { model.useFixture(f) }
            else { await model.load(store: store, client: env.client) }
        }
        .sheet(item: $sheet) { which in sheetContent(which) }
        .confirmationDialog("Which account should act?", isPresented: Binding(get: { choosing != nil }, set: { if !$0 { choosing = nil } }), titleVisibility: .visible) {
            ForEach(choices) { a in
                Button("\(a.label) (@\(a.login))") { if let p = choosing { store.remember(model.key, account: a.id); start(p, with: a) }; choosing = nil }
            }
        } message: { Text("Both accounts can see this pull request. Your choice is remembered for it.") }
    }

    // MARK: header and cards

    private var header: some View {
        let state = InboxLogic.visualState(summary.status)
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(summary.title) \(Text("#\(model.key.number)").foregroundStyle(Primer.fgMuted).fontWeight(.light))").font(.title2.weight(.semibold)).foregroundStyle(Primer.fg)
            HStack(spacing: 8) {
                HStack(spacing: 5) { state.icon.resizable().frame(width: 14, height: 14); Text(stateName(summary.status)) }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 11).padding(.vertical, 3).background(state.color, in: Capsule())
                Text("\(summary.author.map { "@\($0)" } ?? "Someone") wants to merge into \(summary.baseBranch)").font(.footnote).foregroundStyle(Primer.fgMuted)
                if let a = actingAccount { AccountBadge(account: a) }
            }
        }
    }

    @ViewBuilder private var banners: some View {
        if case .readOnly(let reason) = resolution { banner(reason, systemImage: "lock.fill") }
        if model.changedSinceOpened {
            banner("This PR changed since you opened it. Review the new commits, then merge again.", systemImage: "exclamationmark.triangle.fill", action: ("Got it", { model.acceptChangedHead() }))
        }
        if let e = model.loadError { banner(e, systemImage: "exclamationmark.triangle.fill") }
        if let e = model.actionError { banner(e, systemImage: "xmark.octagon.fill") }
    }

    private func banner(_ text: String, systemImage: String, action: (String, () -> Void)? = nil) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage).foregroundStyle(Primer.attention)
            Text(text).font(.footnote).foregroundStyle(Primer.fg)
            Spacer(minLength: 0)
            if let action { Button(action.0, action: action.1).font(.footnote) }
        }
        .padding(10).background(Primer.bgMuted, in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(Primer.border))
    }

    private func card<C: View>(_ title: String, trailing: String? = nil, @ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 0) {
            HStack { Text(title).font(.footnote.weight(.semibold)); Spacer(); if let trailing { Text(trailing).font(.footnote).foregroundStyle(Primer.fgMuted) } }
                .padding(.horizontal, 12).padding(.vertical, 8).background(Primer.bgMuted)
            Divider().overlay(Primer.border)
            content()
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Primer.border))
    }

    private func checksCard(_ checks: [CheckContext]) -> some View {
        let passed = checks.filter { InboxLogic.checkVisual($0.state) == .success }.count
        return card("Checks", trailing: checks.isEmpty ? "None" : "\(passed) of \(checks.count) passed") {
            ForEach(Array(checks.enumerated()), id: \.offset) { _, c in
                HStack(spacing: 8) {
                    CheckIcon(visual: InboxLogic.checkVisual(c.state), size: 16)
                    Text(c.name).font(.footnote)
                    Spacer()
                    if let url = c.url { Link(destination: url) { Image(systemName: "arrow.up.right") }.font(.caption) }
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                Divider().overlay(Primer.border)
            }
        }
    }

    private func conversation(_ items: [TimelineItem]) -> some View {
        card("Conversation") {
            if items.isEmpty { Text("No comments yet").font(.footnote).foregroundStyle(Primer.fgMuted).padding(12) }
            ForEach(Array(items.enumerated()), id: \.offset) { _, t in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(t.author ?? "ghost").fontWeight(.semibold)
                        Text(verb(t)).foregroundStyle(Primer.fgMuted)
                        Text("· \(InboxLogic.age(from: t.date))").foregroundStyle(Primer.fgMuted)
                    }.font(.footnote)
                    if !t.body.isEmpty { Text(markdown(t.body)).font(.footnote) }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                Divider().overlay(Primer.border)
            }
        }
    }

    private var filesCard: some View {
        let adds = model.files.reduce(0) { $0 + $1.additions }, dels = model.files.reduce(0) { $0 + $1.deletions }
        return VStack(spacing: 0) {
            Button { withAnimation { showFiles.toggle() } } label: {
                HStack(spacing: 8) {
                    Octicon.fileDiff.resizable().frame(width: 16, height: 16).foregroundStyle(Primer.fgMuted)
                    Text("Files changed").font(.footnote.weight(.semibold))
                    Spacer()
                    Text("\(model.files.count) files · +\(adds) −\(dels)").font(.footnote).foregroundStyle(Primer.fgMuted)
                    Image(systemName: showFiles ? "chevron.up" : "chevron.down").font(.caption).foregroundStyle(Primer.fgMuted)
                }
                .padding(12).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showFiles { Divider().overlay(Primer.border); DiffView(files: model.files, key: model.key, error: model.filesError) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Primer.border))
    }

    // MARK: actions

    @ViewBuilder private var actions: some View {
        if case .readOnly = resolution { EmptyView() }
        else {
            ActionBar(account: actingAccount, status: summary.status, isBusy: model.isActing,
                      onComment: { begin(.comment) }, onApprove: { begin(.approve) }, onRequestChanges: { begin(.requestChanges) },
                      onMerge: { begin(.merge) }, onMarkReady: { begin(.markReady) }, onClose: { begin(.close) }, onReopen: { begin(.reopen) })
        }
    }

    /// Resolves who acts at the moment of the tap, then continues with that account.
    private func begin(_ p: Pending) {
        switch InboxLogic.resolveActor(key: model.key, fetchedBy: model.item.fetchedBy, router: store.router, claims: store.ownerClaims) {
        case .acting(let id): if let a = store.account(id) { start(p, with: a) }
        case .choose(let ids): choices = ids.compactMap(store.account); choosing = p
        case .readOnly: break
        }
    }

    private func start(_ p: Pending, with account: Account) {
        actor = account
        switch p {
        case .comment: sheet = .comment
        case .requestChanges: sheet = .requestChanges
        case .merge: sheet = .merge
        case .approve: send(.review(.approve, nil), account)
        case .markReady: send(.markReady, account)
        case .close: send(.close, account)
        case .reopen: send(.reopen, account)
        }
    }

    private func send(_ action: PRAction, _ account: Account) {
        Task {
            let ok = await model.perform(action, as: account.id, store: store, client: env.client)
            if ok || model.changedSinceOpened { sheet = nil }
        }
    }

    @ViewBuilder private func sheetContent(_ which: Sheet) -> some View {
        if let account = actor {
            switch which {
            case .comment:
                ComposeSheet(title: "Comment", buttonTitle: ActionTitle.comment(account.login), bodyRequired: true, isBusy: model.isActing, error: model.actionError,
                             onSend: { send(.comment($0), account) }, onCancel: { sheet = nil })
            case .requestChanges:
                ComposeSheet(title: "Request changes", buttonTitle: ActionTitle.requestChanges(account.login), bodyRequired: true, isBusy: model.isActing, error: model.actionError,
                             onSend: { send(.review(.requestChanges, $0), account) }, onCancel: { sheet = nil })
            case .merge:
                MergeSheet(account: account, key: model.key, baseBranch: summary.baseBranch, headOid: model.seenHeadOid ?? summary.status.headOid,
                           method: MergeMethodStore.method(for: model.key), isBusy: model.isActing, error: model.actionError,
                           onConfirm: { send(.merge($0), account) }, onCancel: { sheet = nil })
            }
        }
    }

    // MARK: text

    private func stateName(_ s: PRStatus) -> String {
        switch s.state { case .merged: "Merged"; case .closed: "Closed"; case .open: s.isDraft ? "Draft" : "Open" }
    }
    private func verb(_ t: TimelineItem) -> String {
        guard t.kind == .review else { return "commented" }
        switch t.reviewState?.uppercased() { case "APPROVED": return "approved"; case "CHANGES_REQUESTED": return "requested changes"; default: return "reviewed" }
    }
    private func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}
