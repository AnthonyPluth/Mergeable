import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct Identity: Equatable, Sendable {
    public var login: String
    public var orgs: [String]
    public init(login: String, orgs: [String]) { self.login = login; self.orgs = orgs }
}

/// Reads `/user` and `/user/orgs` with the token being added, for the login and orgs of a new account.
public func fetchIdentity(token: String, transport: HTTPTransport) async throws -> Identity {
    func get(_ path: String) async throws -> Data {
        var req = URLRequest(url: URL(string: "https://api.github.com\(path)")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Mergeable", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await transport.send(req)
        guard (200..<300).contains(resp.statusCode) else { throw resp.statusCode == 401 ? GitHubError.unauthorized(AccountID("")) : GitHubError.http(resp.statusCode) }
        return data
    }
    struct U: Decodable { var login: String }
    let user = try JSONDecoder().decode(U.self, from: try await get("/user"))
    // A token that can't list orgs still works for the user's own repos, so org failures are not fatal.
    let orgs = ((try? JSONDecoder().decode([U].self, from: try await get("/user/orgs?per_page=100"))) ?? []).map(\.login)
    return Identity(login: user.login, orgs: orgs)
}
