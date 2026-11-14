import Testing
@testable import MergeableCore

let personal = Account(id: AccountID("p"), login: "AnthonyPluth", label: "Personal", color: .blue, connection: .githubApp)
let work = Account(id: AccountID("w"), login: "apluth-work", label: "Work", color: .orange, connection: .pat, orgs: ["Acme"])
func key(_ o: String) -> PRKey { PRKey(owner: o, repo: "x", number: 1) }

@Suite struct RoutingTests {
    @Test func ownerMapWins() {
        let r = Router(accounts: [personal, work])
        #expect(r.route(key("acme"), fetchedBy: []) == .account(work.id))
        #expect(r.route(key("AnthonyPluth"), fetchedBy: []) == .account(personal.id))
    }
    @Test func manualOverridesOrgClaim() {
        let r = Router(accounts: [personal, work], manualOwners: ["acme": personal.id])
        #expect(r.route(key("Acme"), fetchedBy: []) == .account(personal.id))
    }
    @Test func ownerClaimedByTwoIsAmbiguous() {
        var other = personal; other.id = AccountID("p2"); other.login = "other"; other.orgs = ["Acme"]
        let r = Router(accounts: [work, other])
        #expect(r.route(key("acme"), fetchedBy: []) == .ambiguous([other.id, work.id].sorted { $0.rawValue < $1.rawValue }))
    }
    @Test func unmappedUsesFetchingAccount() {
        let r = Router(accounts: [personal, work])
        #expect(r.route(key("someorg"), fetchedBy: [work.id]) == .account(work.id))
    }
    @Test func fetchedByBothUsesRememberedChoice() {
        let k = key("someorg")
        let r = Router(accounts: [personal, work], remembered: [k: personal.id])
        #expect(r.route(k, fetchedBy: [personal.id, work.id]) == .account(personal.id))
    }
    @Test func fetchedByBothWithoutChoiceIsAmbiguous() {
        let r = Router(accounts: [personal, work])
        #expect(r.route(key("someorg"), fetchedBy: [personal.id, work.id]) == .ambiguous([personal.id, work.id]))
    }
    @Test func noOwnerIsUnowned() {
        #expect(Router(accounts: [personal, work]).route(key("someorg"), fetchedBy: []) == .unowned)
    }
    @Test func ownerIsCaseInsensitive() {
        let router = Router(accounts: [personal, work])
        #expect(router.route(PRKey(owner: "anthonypluth", repo: "x", number: 1), fetchedBy: []) == .account(personal.id))
    }
}
