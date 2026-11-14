import SwiftUI
import MergeableCore

struct DiffView: View {
    let files: [ChangedFile]
    let key: PRKey
    var error: String?

    private static let maxLines = 1500

    var body: some View {
        VStack(spacing: 0) {
            if let error { Text(error).font(.footnote).foregroundStyle(Primer.danger).padding(12) }
            ForEach(files, id: \.path) { file in
                DisclosureGroup {
                    patch(file)
                } label: {
                    HStack(spacing: 8) {
                        Text(file.path).font(.footnote.monospaced()).lineLimit(1).truncationMode(.head)
                        Spacer(minLength: 4)
                        Text("+\(file.additions)").font(.caption.monospaced()).foregroundStyle(Primer.success)
                        Text("−\(file.deletions)").font(.caption.monospaced()).foregroundStyle(Primer.danger)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                Divider().overlay(Primer.border)
            }
        }
    }

    @ViewBuilder private func patch(_ file: ChangedFile) -> some View {
        if let p = file.patch, !p.isEmpty {
            let lines = p.split(separator: "\n", omittingEmptySubsequences: false)
            ScrollView(.horizontal) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.prefix(Self.maxLines).enumerated()), id: \.offset) { _, line in
                        Text(verbatim: String(line))
                            .font(.system(size: 12, design: .monospaced))
                            .padding(.horizontal, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(background(for: line))
                    }
                    if lines.count > Self.maxLines {
                        Text("Showing the first \(Self.maxLines) lines.").font(.caption).foregroundStyle(Primer.fgMuted).padding(6)
                    }
                }
                .frame(minWidth: 320, alignment: .leading)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Too large to show here").font(.footnote).foregroundStyle(Primer.fgMuted)
                if let url = InboxLogic.githubFilesURL(key) { Link("View on github.com", destination: url).font(.footnote) }
            }
            .padding(.vertical, 6)
        }
    }

    private func background(for line: Substring) -> Color {
        if line.hasPrefix("+") { return Primer.success.opacity(0.15) }
        if line.hasPrefix("-") { return Primer.danger.opacity(0.15) }
        if line.hasPrefix("@@") { return Primer.accent.opacity(0.12) }
        return .clear
    }
}
