import SwiftUI

/// Primer functional colors (dark only: the app forces dark mode) and Octicons, generated into the asset catalog by tools/primer/build-assets.mjs.
enum PRVisualState {
    case open, draft, merged, closed

    /// open `fgColor.open`, draft `fgColor.muted`, merged `fgColor.done`, closed `fgColor.closed`.
    var color: Color {
        switch self {
        case .open: Color("fgColor.open")
        case .draft: Color("fgColor.muted")
        case .merged: Color("fgColor.done")
        case .closed: Color("fgColor.closed")
        }
    }

    var icon: Image {
        switch self {
        case .open: Octicon.pullRequest
        case .draft: Octicon.pullRequestDraft
        case .merged: Octicon.merge
        case .closed: Octicon.pullRequestClosed
        }
    }
}

enum Octicon {
    static func image(_ name: String) -> Image { Image("octicon-\(name)").renderingMode(.template) }
    static let pullRequest = image("git-pull-request")
    static let pullRequestDraft = image("git-pull-request-draft")
    static let merge = image("git-merge")
    static let pullRequestClosed = image("git-pull-request-closed")
    static let checkCircleFill = image("check-circle-fill")
    static let xCircleFill = image("x-circle-fill")
    static let dotFill = image("dot-fill")
    static let comment = image("comment")
    static let eye = image("eye")
    static let check = image("check")
    static let fileDiff = image("file-diff")
    static let bell = image("bell")
    static let person = image("person")
}

enum Primer {
    static let fg = Color("fgColor.default")
    static let fgMuted = Color("fgColor.muted")
    static let accent = Color("fgColor.accent")
    static let success = Color("fgColor.success")
    static let danger = Color("fgColor.danger")
    static let attention = Color("fgColor.attention")
    static let bg = Color("bgColor.default")
    static let bgMuted = Color("bgColor.muted")
    static let border = Color("borderColor.default")
}
