import Foundation
import PocketLarderKit
import Testing
@testable import PocketLarder

private let server = "https://lists.example.test"

private func client(_ transport: FakeTransport) -> APIClient {
    APIClient(server: URL(string: server)!, token: "t", transport: transport)
}

private func bodies(_ requests: [URLRequest]) -> [String?] {
    requests.map { $0.httpBody.map { String(decoding: $0, as: UTF8.self) } }
}

@Test func signingOutThisDeviceRevokesFirst() async throws {
    let transport = FakeTransport([.answer(status: 200, json: #"{"revoked":1}"#), .answer(status: 204, json: "")])
    try await signOutThisDevice("d", client: client(transport))
    let requests = await transport.requests
    #expect(requests.map(\.httpMethod) == ["POST", "DELETE"])
    #expect(requests.map(\.url?.absoluteString) == [server + "/v1/invites/revoke", server + "/v1/admin/devices/d"])
    #expect(bodies(requests) == ["{}", nil])
}

@Test func failedRevokeSendsNoSignOut() async {
    let transport = FakeTransport([.error(URLError(.notConnectedToInternet)), .answer(status: 204, json: "")])
    await #expect(throws: ThisDeviceSignOutFailure.revoke(.offline)) {
        try await signOutThisDevice("d", client: client(transport))
    }
    let requests = await transport.requests
    #expect(requests.map(\.httpMethod) == ["POST"])
    #expect(requests.map(\.url?.absoluteString) == [server + "/v1/invites/revoke"])
}

@Test func failedSignOutAfterRevoke() async {
    let transport = FakeTransport([.answer(status: 200, json: #"{"revoked":1}"#), .answer(status: 500, json: "")])
    await #expect(throws: ThisDeviceSignOutFailure.signOut(.unexpected(status: 500))) {
        try await signOutThisDevice("d", client: client(transport))
    }
    let requests = await transport.requests
    #expect(requests.map(\.httpMethod) == ["POST", "DELETE"])
    #expect(requests.map(\.url?.absoluteString) == [server + "/v1/invites/revoke", server + "/v1/admin/devices/d"])
}
