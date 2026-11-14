import Foundation

public enum CheckRollup: String, Codable, Sendable { case success = "SUCCESS", pending = "PENDING", failure = "FAILURE", error = "ERROR", expected = "EXPECTED" }
public enum PRState: String, Codable, Sendable { case open = "OPEN", closed = "CLOSED", merged = "MERGED" }
public enum MergeableState: String, Codable, Sendable { case mergeable = "MERGEABLE", conflicting = "CONFLICTING", unknown = "UNKNOWN" }

public struct PRStatus: Codable, Hashable, Sendable {
    public var state: PRState
    public var isDraft: Bool
    public var mergeable: MergeableState
    public var rollup: CheckRollup?
    public var headOid: String
    public init(state: PRState, isDraft: Bool, mergeable: MergeableState, rollup: CheckRollup?, headOid: String) {
        self.state = state; self.isDraft = isDraft; self.mergeable = mergeable; self.rollup = rollup; self.headOid = headOid
    }
}

/// Open, not a draft, checks green or absent, no merge conflict.
public func isMergeReady(_ s: PRStatus) -> Bool {
    s.state == .open && !s.isDraft && (s.rollup == nil || s.rollup == .success) && s.mergeable != .conflicting
}
