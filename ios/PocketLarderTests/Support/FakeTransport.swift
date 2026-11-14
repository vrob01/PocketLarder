import Foundation
import PocketLarderKit
import Synchronization

/// Records every request and the host trusted when it was sent, and answers from a script, one step per request. A copy
/// of the kit's, plus the trusted host.
actor FakeTransport: Transport {
    enum Step {
        case answer(status: Int, json: String)
        case error(any Error)
        /// Keeps the request open until `release` answers it.
        case hold
    }

    private var script: [Step]
    private(set) var requests: [URLRequest] = []
    /// What `trustedHost` was when each request in `requests` was sent.
    private(set) var trustedHosts: [String?] = []
    private let trusted = Mutex<String?>(nil)
    private var held: CheckedContinuation<(status: Int, json: String), Never>?

    init(_ script: [Step]) {
        self.script = script
    }

    /// Nonisolated, as `AppModel` sets it from the main actor without waiting.
    nonisolated var trustedHost: String? {
        trusted.withLock { $0 }
    }

    nonisolated func trust(host: String?) {
        trusted.withLock { $0 = host }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        trustedHosts.append(trustedHost)
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
