import SwiftUI
import MergeableCore

/// Merge always goes through this sheet: it names the account, the method and the target branch.
struct MergeSheet: View {
    let account: Account
    let key: PRKey
    let baseBranch: String
    let headOid: String
    @State var method: MergeMethod
    var isBusy: Bool
    var onConfirm: (MergeMethod) -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Merge pull request").font(.title3.weight(.semibold))
            row("Account") { AccountBadge(account: account); Text("@\(account.login)").fontWeight(.semibold) }
            row("Method") {
                Picker("Method", selection: $method) {
                    Text("Merge commit").tag(MergeMethod.merge)
                    Text("Squash and merge").tag(MergeMethod.squash)
                    Text("Rebase and merge").tag(MergeMethod.rebase)
                }
                .labelsHidden()
            }
            row("Into") { Text(baseBranch).font(.callout.monospaced()) }
            row("Head") { Text(String(headOid.prefix(7))).font(.callout.monospaced()) }
            Button {
                MergeMethodStore.remember(method, for: key)
                onConfirm(method)
            } label: {
                HStack { Octicon.merge.resizable().frame(width: 16, height: 16); Text("Confirm merge as @\(account.login)") }
                    .font(.body.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent).tint(.green).disabled(isBusy)
            Button("Cancel", action: onCancel).frame(maxWidth: .infinity)
        }
        .padding(20)
        .frame(minWidth: 320)
        .presentationDetents([.medium])
        .background(Primer.bg)
    }

    private func row<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack { Text(title).foregroundStyle(Primer.fgMuted); Spacer(); content() }
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) { Divider().overlay(Primer.border) }
    }
}

/// Text entry for a comment, or a review that needs a body.
struct ComposeSheet: View {
    let title: String
    let buttonTitle: String
    let bodyRequired: Bool
    var isBusy: Bool
    var onSend: (String) -> Void
    var onCancel: () -> Void
    @State private var text = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                TextEditor(text: $text)
                    .frame(minHeight: 160)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Primer.border))
                Button(buttonTitle) { onSend(text) }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy || (bodyRequired && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
            .padding(16)
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) } }
        }
        .frame(minWidth: 360, minHeight: 300)
    }
}
