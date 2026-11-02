#if DEBUG
import Foundation
import PocketLarderKit

/// The fake server behind `-fixture household`. Each instance works on its own copy of the snapshot.
actor FixtureTransport: Transport {
    private struct SyncBody: Decodable {
        let ops: [Op]
    }

    private struct SyncAnswer: Encodable {
        let rejected: [Rejection]
        let snapshot: Snapshot
    }

    private var snapshot: Snapshot

    init(_ snapshot: Snapshot) {
        self.snapshot = snapshot
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard request.httpMethod == "POST", request.url?.path == "/v1/sync", let body = request.httpBody else {
            return (Data(#"{"error":"not_found"}"#.utf8), response(to: request, status: 404))
        }
        let ops = try JSON.decoder.decode(SyncBody.self, from: body).ops
        snapshot = applying(ops.map { PendingOp(op: $0, at: .now) }, to: snapshot)
        return (try JSON.encoder.encode(SyncAnswer(rejected: [], snapshot: snapshot)), response(to: request, status: 200))
    }

    private func response(to request: URLRequest, status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
    }
}
#endif
