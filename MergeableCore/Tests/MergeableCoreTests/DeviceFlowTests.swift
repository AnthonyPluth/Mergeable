import Testing
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MergeableCore

private let t0 = Date(timeIntervalSince1970: 1_000_000)
private func flow(_ t: MockTransport) -> DeviceFlow { DeviceFlow(clientID: "Iv1.abc", transport: t, now: { t0 }) }
private func form(_ r: URLRequest) -> String { String(decoding: r.httpBody ?? Data(), as: UTF8.self) }
private let dc = DeviceCode(deviceCode: "DC", userCode: "UC", verificationURL: URL(string: "https://github.com/login/device")!, interval: 5, expiresAt: t0 + 900)
private let tokenJSON = #"{"access_token":"at","expires_in":28800,"refresh_token":"rt","refresh_token_expires_in":15897600,"token_type":"bearer"}"#

@Suite struct DeviceFlowTests {
    @Test func noClientSecretEverSent() async throws {
        let t = MockTransport { r in
            r.url!.path == "/login/device/code"
                ? (200, json(#"{"device_code":"DC","user_code":"UC","verification_uri":"https://github.com/login/device","expires_in":900,"interval":5}"#), [:])
                : (200, json(tokenJSON), [:])
        }
        let f = flow(t)
        let code = try await f.start()
        #expect(code.userCode == "UC" && code.interval == 5 && code.expiresAt == t0 + 900)
        _ = try await f.poll(code, sleep: { _ in })
        _ = try await f.refresh("rt")
        #expect(t.requests.count == 3)
        for r in t.requests {
            #expect(!form(r).contains("secret"))
            #expect(form(r).contains("client_id=Iv1.abc"))
            #expect(r.value(forHTTPHeaderField: "Accept") == "application/json")
        }
    }

    @Test func pendingThenSuccess() async throws {
        let n = Box<[Int]>([])
        let t = MockTransport { _ in n.append(1); return (200, json(n.value.count < 3 ? #"{"error":"authorization_pending"}"# : tokenJSON), [:]) }
        let tokens = try await flow(t).poll(dc, sleep: { _ in })
        #expect(tokens.accessToken == "at" && t.requests.count == 3)
        #expect(form(t.requests[0]).contains("grant_type=urn:ietf:params:oauth:grant-type:device_code"))
    }

    @Test func slowDownAddsFiveSeconds() async throws {
        let n = Box<[Int]>([])
        let t = MockTransport { _ in n.append(1); return (200, json(n.value.count == 1 ? #"{"error":"slow_down"}"# : tokenJSON), [:]) }
        let sleeps = Box<[Int]>([])
        _ = try await flow(t).poll(dc, sleep: { sleeps.append($0) })
        #expect(sleeps.value == [5, 10])
    }

    @Test func expiredAndDeniedThrow() async throws {
        for (err, expected) in [("expired_token", DeviceFlowError.expired), ("access_denied", .denied)] {
            let t = MockTransport { _ in (200, json(#"{"error":"\#(err)"}"#), [:]) }
            await #expect(throws: expected) { try await flow(t).poll(dc, sleep: { _ in }) }
        }
    }

    @Test func refreshReturnsNewPair() async throws {
        let t = MockTransport { _ in (200, json(#"{"access_token":"at2","expires_in":28800,"refresh_token":"rt2","refresh_token_expires_in":100}"#), [:]) }
        let p = try await flow(t).refresh("rt")
        #expect(p.accessToken == "at2" && p.refreshToken == "rt2")
        #expect(form(t.requests[0]).contains("grant_type=refresh_token") && form(t.requests[0]).contains("refresh_token=rt"))
    }

    @Test func expiryDatesComeFromExpiresIn() async throws {
        let t = MockTransport { _ in (200, json(tokenJSON), [:]) }
        let p = try await flow(t).poll(dc, sleep: { _ in })
        #expect(p.accessExpiry == t0 + 28800 && p.refreshExpiry == t0 + 15897600)
    }
}
