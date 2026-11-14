import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MergeableCore

final class MockTransport: HTTPTransport, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) -> (Int, Data, [String: String])
    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    private let handler: Handler
    init(_ handler: @escaping Handler) { self.handler = handler }
    private func record(_ r: URLRequest) { lock.lock(); _requests.append(r); lock.unlock() }
    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return _requests }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        record(request)
        let (status, data, headers) = handler(request)
        let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
        return (data, resp)
    }
    func bodyJSON(_ i: Int) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: requests[i].httpBody ?? Data())) as? [String: Any] ?? [:]
    }
}

struct FixedTokens: TokenProvider {
    var map: [String: String]
    func token(for account: AccountID, owner: String) async throws -> String { map[account.rawValue] ?? "none" }
}

func json(_ s: String) -> Data { Data(s.utf8) }

func prNode(id: String, number: Int, headOid: String = "h1") -> String {
    """
    {"id":"\(id)","number":\(number),"title":"T\(number)","url":"https://github.com/o/r/pull/\(number)","updatedAt":"2026-01-01T00:00:00Z",
    "isDraft":false,"state":"OPEN","mergeable":"MERGEABLE","headRefOid":"\(headOid)","baseRefName":"main","reviewDecision":null,
    "author":{"login":"alice"},"repository":{"name":"r","owner":{"login":"o"}},
    "commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"SUCCESS"}}}]},
    "comments":{"totalCount":2},"lastComment":{"nodes":[{"author":{"login":"bob"}}]},
    "reviews":{"totalCount":1},"lastReview":{"nodes":[{"state":"APPROVED","author":{"login":"carol"}}]}}
    """
}
