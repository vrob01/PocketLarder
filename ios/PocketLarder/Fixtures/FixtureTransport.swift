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

    private struct InviteAnswer: Encodable {
        let url: String
        let expiresAt: Date
        let memberId: String
    }

    private var snapshot: Snapshot

    init(_ snapshot: Snapshot) {
        self.snapshot = snapshot
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if request.httpMethod == "POST", request.url?.path == "/v1/invites" {
            // A dummy, so that no real invite shows in a screenshot.
            let invite = InviteAnswer(
                url: "pocketlarder://invite?server=https%3A%2F%2Ffixture.invalid&code=fixture-dummy-invite",
                expiresAt: .now.addingTimeInterval(24 * 60 * 60),
                memberId: snapshot.me.memberId
            )
            return (try JSON.encoder.encode(invite), response(to: request, status: 201))
        }
        if request.httpMethod == "POST", request.url?.path == "/v1/invites/revoke" {
            return (Data(#"{"revoked":1}"#.utf8), response(to: request, status: 200))
        }
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

/// The server behind `-fixture offline`, which can never be reached.
struct UnreachableTransport: Transport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw URLError(.cannotConnectToHost)
    }
}
#endif
