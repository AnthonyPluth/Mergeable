import XCTest
import MergeableCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import Mergeable

private final class RecordingTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    var status = 204
    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return _requests }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { _requests.append(request) }
        return (Data(), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

final class RelayClientTests: XCTestCase {
    private let config = RelayConfig(baseURL: URL(string: "https://push.pluth.org")!, secret: "s3cret")

    private func body(_ r: URLRequest) throws -> [String: String] {
        try JSONDecoder().decode([String: String].self, from: XCTUnwrap(r.httpBody))
    }

    func testRegisterRequestShape() throws {
        let t = RecordingTransport()
        let client = RelayClient(transport: t)
        let exp = expectation(description: "done")
        Task { try await client.register(token: "abcd01", platform: .ios, environment: .sandbox, config: config); exp.fulfill() }
        wait(for: [exp], timeout: 5)
        let r = try XCTUnwrap(t.requests.first)
        XCTAssertEqual(r.url?.absoluteString, "https://push.pluth.org/devices")
        XCTAssertEqual(r.httpMethod, "POST")
        XCTAssertEqual(r.value(forHTTPHeaderField: "Authorization"), "Bearer s3cret")
        XCTAssertEqual(r.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(try body(r), ["token": "abcd01", "platform": "ios", "environment": "sandbox"])
    }

    func testMacProductionBody() throws {
        let r = RelayClient.registerRequest(token: "ff", platform: .macos, environment: .production, config: config)
        XCTAssertEqual(try body(r), ["token": "ff", "platform": "macos", "environment": "production"])
    }

    func testDebugBuildsUseSandboxAndReleaseBuildsUseProduction() {
        #if DEBUG
        XCTAssertEqual(APNsEnvironment.current, .sandbox)
        #else
        XCTAssertEqual(APNsEnvironment.current, .production)
        #endif
    }

    func testTrailingSlashInRelayURLStillHitsDevices() {
        let c = RelayConfig(baseURL: URL(string: "https://push.pluth.org/")!, secret: "x")
        XCTAssertEqual(RelayClient.registerRequest(token: "a", platform: .ios, environment: .production, config: c).url?.absoluteString,
                       "https://push.pluth.org/devices")
    }

    func testUnregisterRequestShape() {
        let r = RelayClient.unregisterRequest(token: "abcd01", config: config)
        XCTAssertEqual(r.url?.absoluteString, "https://push.pluth.org/devices/abcd01")
        XCTAssertEqual(r.httpMethod, "DELETE")
        XCTAssertEqual(r.value(forHTTPHeaderField: "Authorization"), "Bearer s3cret")
        XCTAssertNil(r.httpBody)
    }

    func testNon2xxThrows() async {
        let t = RecordingTransport(); t.status = 401
        do {
            try await RelayClient(transport: t).register(token: "a", platform: .ios, environment: .production, config: config)
            XCTFail("expected an error")
        } catch { XCTAssertEqual(error as? RelayError, .http(401)) }
    }

    func testHexEncodesLowercaseWithLeadingZeros() {
        XCTAssertEqual(RelayClient.hex(Data([0x00, 0x0a, 0xff, 0x10])), "000aff10")
    }
}
