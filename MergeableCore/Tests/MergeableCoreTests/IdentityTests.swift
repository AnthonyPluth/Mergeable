import Testing
import Foundation
@testable import MergeableCore

@Suite struct IdentityTests {
    @Test func readsLoginAndOrgs() async throws {
        let t = MockTransport { r in
            r.url!.path == "/user" ? (200, json(#"{"login":"apluth-acme"}"#), [:]) : (200, json(#"[{"login":"acme"},{"login":"beta"}]"#), [:])
        }
        let id = try await fetchIdentity(token: "tok", transport: t)
        #expect(id == Identity(login: "apluth-acme", orgs: ["acme", "beta"]))
        #expect(t.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer tok" })
    }
    @Test func orgFailureIsNotFatal() async throws {
        let t = MockTransport { r in r.url!.path == "/user" ? (200, json(#"{"login":"me"}"#), [:]) : (403, json("{}"), [:]) }
        #expect(try await fetchIdentity(token: "tok", transport: t) == Identity(login: "me", orgs: []))
    }
    @Test func badTokenThrows() async {
        let t = MockTransport { _ in (401, json("{}"), [:]) }
        await #expect(throws: (any Error).self) { try await fetchIdentity(token: "x", transport: t) }
    }
}
