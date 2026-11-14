import Foundation
import MergeableCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum APNsEnvironment: String, Codable, Equatable, Sendable {
    case sandbox, production

    /// Debug builds are signed with the development push entitlement, so their tokens only work on Apple's sandbox
    /// host; Release builds use production (Review Focus 5). Tests pass the environment explicitly.
    static var current: APNsEnvironment {
        #if DEBUG
        return .sandbox
        #else
        return .production
        #endif
    }
}

enum DevicePlatform: String, Codable, Equatable, Sendable {
    case ios, macos

    static var current: DevicePlatform {
        #if os(macOS)
        return .macos
        #else
        return .ios
        #endif
    }
}

struct RelayConfig: Equatable, Sendable {
    static let defaultURL = "https://push.pluth.org"
    var baseURL: URL
    var secret: String
}

enum RelayError: Error, Equatable {
    case notConfigured
    case http(Int)
}

/// Registers this device's APNs token with the relay. Pure: the transport is injected, so tests never touch the network.
struct RelayClient: Sendable {
    let transport: HTTPTransport

    private struct Body: Encodable {
        var token: String
        var platform: String
        var environment: String
    }

    static func registerRequest(token: String, platform: DevicePlatform, environment: APNsEnvironment, config: RelayConfig) -> URLRequest {
        var r = URLRequest(url: config.baseURL.appendingPathComponent("devices"))
        r.httpMethod = "POST"
        r.setValue("Bearer \(config.secret)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONEncoder().encode(Body(token: token, platform: platform.rawValue, environment: environment.rawValue))
        return r
    }

    static func unregisterRequest(token: String, config: RelayConfig) -> URLRequest {
        var r = URLRequest(url: config.baseURL.appendingPathComponent("devices").appendingPathComponent(token))
        r.httpMethod = "DELETE"
        r.setValue("Bearer \(config.secret)", forHTTPHeaderField: "Authorization")
        return r
    }

    func register(token: String, platform: DevicePlatform = .current, environment: APNsEnvironment = .current, config: RelayConfig) async throws {
        try await send(Self.registerRequest(token: token, platform: platform, environment: environment, config: config))
    }

    func unregister(token: String, config: RelayConfig) async throws {
        try await send(Self.unregisterRequest(token: token, config: config))
    }

    private func send(_ request: URLRequest) async throws {
        let (_, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else { throw RelayError.http(response.statusCode) }
    }

    /// APNs hands over the token as raw bytes; the relay wants lowercase hex.
    static func hex(_ token: Data) -> String { token.map { String(format: "%02x", $0) }.joined() }
}
