import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import PocketLarderKit

/// Records every request and answers from a script, one step per request.
actor FakeTransport: Transport {
    enum Step {
        case answer(status: Int, json: String)
        case error(any Error)
        /// Keeps the request open until `release` answers it.
        case hold
    }

    private var script: [Step]
    private(set) var requests: [URLRequest] = []
    private var held: CheckedContinuation<(status: Int, json: String), Never>?

    init(_ script: [Step]) {
        self.script = script
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        switch script.removeFirst() {
        case let .answer(status, json):
            return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        case let .error(error):
            throw error
        case .hold:
            let (status, json) = await withCheckedContinuation { held = $0 }
            return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }

    /// Call it once `requests` shows the request: by then a `.hold` step is waiting.
    func release(status: Int, json: String) {
        held?.resume(returning: (status, json))
        held = nil
    }
}
