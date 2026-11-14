import XCTest
import Security
import MergeableCore
@testable import Mergeable

final class RecordingBackend: KeychainBackend, @unchecked Sendable {
    struct Write { var key: String; var synchronizable: Bool }
    private let lock = NSLock()
    private var items: [String: Data] = [:]
    private var _writes: [Write] = []
    var writes: [Write] { lock.lock(); defer { lock.unlock() }; return _writes }
    func write(_ data: Data, key: String, synchronizable: Bool) throws { lock.lock(); items[key] = data; _writes.append(Write(key: key, synchronizable: synchronizable)); lock.unlock() }
    func read(key: String) throws -> Data? { lock.lock(); defer { lock.unlock() }; return items[key] }
    func delete(key: String) throws { lock.lock(); items[key] = nil; lock.unlock() }
}

final class KeychainStoreTests: XCTestCase {
    let a = AccountID("acct-a"), b = AccountID("acct-b")

    func testKeychainRoundTripRespectsSyncFlag() async throws {
        let backend = RecordingBackend()
        let store = KeychainStore(backend: backend)
        try await store.savePAT("tok-sync", account: a, synchronizable: true)
        try await store.savePAT("tok-local", account: b, synchronizable: false)
        let ta = try await store.token(for: a, owner: "anyone")
        let tb = try await store.token(for: b, owner: "anyone")
        XCTAssertEqual(ta, "tok-sync")
        XCTAssertEqual(tb, "tok-local")
        XCTAssertEqual(backend.writes.first { $0.key == "token.acct-a.*" }?.synchronizable, true)
        XCTAssertEqual(backend.writes.first { $0.key == "token.acct-b.*" }?.synchronizable, false)
    }

    func testPerOwnerTokenWinsAndNeverCrossesAccounts() async throws {
        let store = KeychainStore(backend: RecordingBackend())
        try await store.savePAT("default", account: a, synchronizable: false)
        try await store.savePAT("acme-token", account: a, owner: "Acme", synchronizable: false)
        let acme = try await store.token(for: a, owner: "acme")
        let other = try await store.token(for: a, owner: "other")
        XCTAssertEqual(acme, "acme-token")
        XCTAssertEqual(other, "default")
        do { _ = try await store.token(for: b, owner: "acme"); XCTFail("must not fall back to another account") }
        catch { XCTAssertEqual(error as? TokenError, .missing(b)) }
    }

    func testSyncSwitchRewritesTheItem() async throws {
        let backend = RecordingBackend()
        let store = KeychainStore(backend: backend)
        try await store.savePAT("t", account: a, synchronizable: true)
        try await store.setSynchronizable(false, account: a, owners: [])
        let sync = try await store.isSynchronizable(account: a)
        XCTAssertEqual(sync, false)
        XCTAssertEqual(backend.writes.last?.synchronizable, false)
    }

    func testRemoveDeletesEveryOwnerItem() async throws {
        let store = KeychainStore(backend: RecordingBackend())
        try await store.savePAT("d", account: a, synchronizable: false)
        try await store.savePAT("x", account: a, owner: "acme", synchronizable: false)
        try await store.remove(account: a, owners: ["acme"])
        do { _ = try await store.token(for: a, owner: "acme"); XCTFail("token should be gone") } catch {}
    }

    func testAppTokenNearExpiryIsRefreshed() async throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let transport = StubTransport { _ in #"{"access_token":"new-at","expires_in":28800,"refresh_token":"new-rt","refresh_token_expires_in":15897600}"# }
        let backend = RecordingBackend()
        let store = KeychainStore(backend: backend, flow: DeviceFlow(clientID: "id", transport: transport, now: { now }), now: { now })
        try await store.saveApp(AppTokens(accessToken: "old", accessExpiry: now.addingTimeInterval(120), refreshToken: "rt", refreshExpiry: now.addingTimeInterval(1000)), account: a, synchronizable: true)
        let tok = try await store.token(for: a, owner: "x")
        XCTAssertEqual(tok, "new-at")
        XCTAssertEqual(backend.writes.last?.synchronizable, true)   // refreshed pair keeps the sync setting
    }

    func testRealKeychainRoundTripWhenAvailable() throws {
        let backend = SecItemBackend(service: "com.pluth.mergeable.tests.\(UUID().uuidString)")
        do { try backend.write(Data("x".utf8), key: "k", synchronizable: false) }
        catch let e as KeychainError where e.status == errSecMissingEntitlement || e.status == -34018 { throw XCTSkip("unsigned test host has no Keychain entitlement") }
        XCTAssertEqual(try backend.read(key: "k"), Data("x".utf8))
        try backend.delete(key: "k")
        XCTAssertNil(try backend.read(key: "k"))
    }
}

struct StubTransport: HTTPTransport {
    var body: @Sendable (URLRequest) -> String
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        (Data(body(request).utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
