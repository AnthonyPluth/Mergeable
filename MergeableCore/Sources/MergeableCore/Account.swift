import Foundation

public struct AccountID: Hashable, Codable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(rawValue: String) { self.rawValue = rawValue }
}

public enum Connection: String, Codable, Sendable { case githubApp, pat }

public enum AccountColor: String, Codable, CaseIterable, Sendable { case blue, orange, green, purple, red, gray }

public struct Account: Codable, Hashable, Sendable, Identifiable {
    public var id: AccountID
    public var login: String
    public var label: String
    public var color: AccountColor
    public var connection: Connection
    public var orgs: [String]
    public var opensInLinear: Bool

    public init(id: AccountID, login: String, label: String, color: AccountColor, connection: Connection, orgs: [String] = [], opensInLinear: Bool = false) {
        self.id = id; self.login = login; self.label = label; self.color = color
        self.connection = connection; self.orgs = orgs; self.opensInLinear = opensInLinear
    }
}

public struct PRKey: Hashable, Codable, Sendable {
    public let owner: String
    public let repo: String
    public let number: Int
    public init(owner: String, repo: String, number: Int) {
        self.owner = owner.lowercased(); self.repo = repo.lowercased(); self.number = number
    }
}
