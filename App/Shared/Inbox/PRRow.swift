import SwiftUI
import MergeableCore

struct CheckIcon: View {
    let visual: CheckVisual
    var size: CGFloat = 14
    var body: some View {
        switch visual {
        case .success: Octicon.checkCircleFill.resizable().frame(width: size, height: size).foregroundStyle(Primer.success)
        case .failure: Octicon.xCircleFill.resizable().frame(width: size, height: size).foregroundStyle(Primer.danger)
        case .pending: Octicon.dotFill.resizable().frame(width: size, height: size).foregroundStyle(Primer.attention)
        }
    }
}

struct PRRow: View {
    let item: InboxItem
    let account: Account?
    var now: Date = Date()

    private var pr: PullRequestSummary { item.summary }
    private var state: PRVisualState { InboxLogic.visualState(pr.status) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            state.icon.resizable().frame(width: 16, height: 16).foregroundStyle(state.color).padding(.top, 3)
            VStack(alignment: .leading, spacing: 3) {
                Text(pr.title).font(.body.weight(.semibold)).foregroundStyle(Primer.fg).lineLimit(1)
                Text("\(pr.key.owner)/\(pr.key.repo) #\(pr.key.number) · \(pr.author ?? "unknown") · \(InboxLogic.age(from: pr.updatedAt, now: now))")
                    .font(.caption).foregroundStyle(Primer.fgMuted).lineLimit(1)
                HStack(spacing: 8) {
                    if let v = InboxLogic.rollupVisual(pr.status.rollup) { CheckIcon(visual: v) }
                    reviewIcon
                    if item.section == .yours, isMergeReady(pr.status) { ReadyPill() }
                    if let account { AccountBadge(account: account) }
                    else { Text("Choose account").font(.caption2.weight(.semibold)).foregroundStyle(Primer.attention) }
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var reviewIcon: some View {
        switch pr.reviewDecision {
        case "APPROVED": Octicon.check.resizable().frame(width: 14, height: 14).foregroundStyle(Primer.success)
        case "CHANGES_REQUESTED": Octicon.xCircleFill.resizable().frame(width: 14, height: 14).foregroundStyle(Primer.danger)
        case "REVIEW_REQUIRED": Octicon.eye.resizable().frame(width: 14, height: 14).foregroundStyle(Primer.fgMuted)
        default: if item.section == .needsReview { Octicon.eye.resizable().frame(width: 14, height: 14).foregroundStyle(Primer.fgMuted) }
        }
    }
}

struct ReadyPill: View {
    var body: some View {
        Text("Ready to merge")
            .font(.caption2.weight(.semibold)).foregroundStyle(Primer.success)
            .padding(.horizontal, 7).padding(.vertical, 1)
            .overlay(Capsule().stroke(Primer.success, lineWidth: 1))
    }
}
