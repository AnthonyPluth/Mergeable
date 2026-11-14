import XCTest
import MergeableCore
@testable import Mergeable

@MainActor
final class AccountStoreTests: XCTestCase {
    let personal = Account(id: AccountID("p"), login: "AnthonyPluth", label: "Personal", color: .blue, connection: .githubApp)
    let work = Account(id: AccountID("w"), login: "apluth-acme", label: "Work", color: .orange, connection: .pat, orgs: ["Acme"])

    func testAccountsAndChoicesSurviveReload() {
        let kv = MemoryKeyValueStore()
        let s1 = AccountStore(store: kv)
        s1.add(personal); s1.add(work)
        s1.assign(owner: "Acme", to: personal.id)
        s1.remember(PRKey(owner: "oss", repo: "lib", number: 4), account: work.id)
        let s2 = AccountStore(store: kv)
        XCTAssertEqual(s2.accounts.map(\.login), ["AnthonyPluth", "apluth-acme"])
        XCTAssertEqual(s2.router.route(PRKey(owner: "acme", repo: "x", number: 1), fetchedBy: []), .account(personal.id))
        XCTAssertEqual(s2.router.route(PRKey(owner: "oss", repo: "lib", number: 4), fetchedBy: [personal.id, work.id]), .account(work.id))
    }

    func testOwnerClaimedByTwoIsFlaggedUntilAssigned() {
        let s = AccountStore(store: MemoryKeyValueStore())
        var other = personal; other.id = AccountID("p2"); other.login = "someone"; other.orgs = ["acme"]
        s.add(work); s.add(other)
        XCTAssertEqual(s.ambiguousOwners.map(\.owner), ["acme"])
        s.assign(owner: "acme", to: work.id)
        XCTAssertTrue(s.ambiguousOwners.isEmpty)
    }

    func testRemovingAnAccountDropsItsAssignments() {
        let s = AccountStore(store: MemoryKeyValueStore())
        s.add(personal); s.assign(owner: "x", to: personal.id); s.markNeedsAttention(personal.id)
        s.remove(personal.id)
        XCTAssertTrue(s.accounts.isEmpty); XCTAssertTrue(s.manualOwners.isEmpty); XCTAssertTrue(s.needsAttention.isEmpty)
    }
}
