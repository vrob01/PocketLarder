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
    }

    private var script: [Step]
    private(set) var requests: [URLRequest] = []

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
        }
    }
}
