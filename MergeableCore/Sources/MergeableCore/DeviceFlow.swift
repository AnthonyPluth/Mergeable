import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct DeviceCode: Sendable {
    public var deviceCode: String
    public var userCode: String
    public var verificationURL: URL
    public var interval: Int
    public var expiresAt: Date
}

public struct AppTokens: Codable, Sendable, Equatable {
    public var accessToken: String
    public var accessExpiry: Date
    public var refreshToken: String
    public var refreshExpiry: Date
}

public enum DeviceFlowError: Error, Equatable { case expired, denied, unexpected(String) }

/// GitHub App device flow. A GitHub App's device flow needs no client secret, and none is ever sent.
public struct DeviceFlow: Sendable {
    public let clientID: String
    public let transport: HTTPTransport
    public var now: @Sendable () -> Date

    public init(clientID: String, transport: HTTPTransport, now: @escaping @Sendable () -> Date = { Date() }) {
        self.clientID = clientID; self.transport = transport; self.now = now
    }

    private func post(_ url: String, _ form: [String: String]) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: url)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("Mergeable", forHTTPHeaderField: "User-Agent")
        var c = URLComponents(); c.queryItems = form.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        req.httpBody = Data((c.percentEncodedQuery ?? "").utf8)
        let (data, resp) = try await transport.send(req)
        guard (200..<300).contains(resp.statusCode) else { throw GitHubError.http(resp.statusCode) }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    public func start() async throws -> DeviceCode {
        let j = try await post("https://github.com/login/device/code", ["client_id": clientID])
        guard let dc = j["device_code"] as? String, let uc = j["user_code"] as? String,
              let uri = (j["verification_uri"] as? String).flatMap(URL.init(string:)) else {
            throw DeviceFlowError.unexpected(j["error"] as? String ?? "bad device code response")
        }
        return DeviceCode(deviceCode: dc, userCode: uc, verificationURL: uri, interval: j["interval"] as? Int ?? 5,
                          expiresAt: now().addingTimeInterval(TimeInterval(j["expires_in"] as? Int ?? 900)))
    }

    public func poll(_ code: DeviceCode, sleep: @Sendable (Int) async -> Void) async throws -> AppTokens {
        var interval = code.interval
        while true {
            await sleep(interval)
            let j = try await post("https://github.com/login/oauth/access_token", [
                "client_id": clientID, "device_code": code.deviceCode, "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            ])
            switch j["error"] as? String {
            case nil: return try tokens(from: j)
            case "authorization_pending": continue
            case "slow_down": interval += 5
            case "expired_token": throw DeviceFlowError.expired
            case "access_denied": throw DeviceFlowError.denied
            case let other?: throw DeviceFlowError.unexpected(other)
            }
        }
    }

    public func refresh(_ refreshToken: String) async throws -> AppTokens {
        let j = try await post("https://github.com/login/oauth/access_token", [
            "client_id": clientID, "grant_type": "refresh_token", "refresh_token": refreshToken,
        ])
        if let e = j["error"] as? String { throw DeviceFlowError.unexpected(e) }
        return try tokens(from: j)
    }

    private func tokens(from j: [String: Any]) throws -> AppTokens {
        guard let at = j["access_token"] as? String, let rt = j["refresh_token"] as? String else {
            throw DeviceFlowError.unexpected("missing tokens")
        }
        let t = now()
        return AppTokens(accessToken: at, accessExpiry: t.addingTimeInterval(TimeInterval(j["expires_in"] as? Int ?? 28800)),
                         refreshToken: rt, refreshExpiry: t.addingTimeInterval(TimeInterval(j["refresh_token_expires_in"] as? Int ?? 15897600)))
    }
}
