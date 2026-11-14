import SwiftUI
import MergeableCore

/// The buttons, each naming the account that will act. The account is resolved when a button is tapped.
struct ActionBar: View {
    let account: Account?
    let status: PRStatus
    var isBusy: Bool
    var onComment: () -> Void
    var onApprove: () -> Void
    var onRequestChanges: () -> Void
    var onMerge: () -> Void
    var onMarkReady: () -> Void
    var onClose: () -> Void
    var onReopen: () -> Void

    var body: some View {
        let login = account?.login ?? "…"
        VStack(spacing: 8) {
            if status.state == .open {
                if status.isDraft { bar(ActionTitle.markReady(login), Octicon.check, onMarkReady) }
                bar(ActionTitle.comment(login), Octicon.comment, onComment)
                HStack(spacing: 8) {
                    bar(ActionTitle.approve(login), Octicon.check, onApprove)
                    bar(ActionTitle.requestChanges(login), Octicon.xCircleFill, onRequestChanges)
                }
                if !status.isDraft {
                    bar(ActionTitle.merge(login), Octicon.merge, onMerge, prominent: true, disabled: status.mergeable == .conflicting)
                }
                bar(ActionTitle.close(login), Octicon.pullRequestClosed, onClose)
            } else if status.state == .closed {
                bar(ActionTitle.reopen(login), Octicon.pullRequest, onReopen)
            }
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 12)
        .background(Primer.bg)
        .overlay(alignment: .top) { Divider().overlay(Primer.border) }
        .disabled(isBusy)
    }

    private func bar(_ title: String, _ icon: Image, _ action: @escaping () -> Void, prominent: Bool = false, disabled: Bool = false) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                icon.resizable().frame(width: 14, height: 14)
                Text(title).lineLimit(1).minimumScaleFactor(0.8)
            }
            .font(.callout.weight(.semibold))
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            .foregroundStyle(prominent ? Color.white : Primer.fg)
            .background(prominent ? Color(red: 0.12, green: 0.53, blue: 0.24) : Primer.bgMuted, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(prominent ? .clear : Primer.border))
            .opacity(disabled ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}
