import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import PocketLarderKit

private let server = "https://lists.example.test"
private let redemption = #"{"token":"t","member_id":"m","device_id":"d"}"#
private let synced = #"{"rejected":[],"snapshot":{"me":{"member_id":"m","device_id":"d","is_admin":false},"members":[],"lists":[],"stores":[],"categories":[],"items":[],"placements":[],"entries":[]}}"#
private let created = #"{"url":"pocketlarder://invite?server=https%3A%2F%2Flists.example.test&code=c","expires_at":"2026-10-28T09:00:00Z","member_id":"m"}"#

private func fakeClient(_ step: FakeTransport.Step) -> (APIClient, FakeTransport) {
    let transport = FakeTransport([step])
    return (APIClient(server: URL(string: server)!, token: "t", transport: transport), transport)
}

/// Runs one call against a fake answer and checks everything about the request it sent.
private func expectRequest(
    _ method: String,
    _ path: String,
    body: String? = nil,
    authorized: Bool = true,
    answer: (status: Int, json: String) = (204, ""),
    sourceLocation: SourceLocation = #_sourceLocation,
    _ call: (APIClient) async throws -> Void
) async throws {
    let (client, transport) = fakeClient(.answer(status: answer.status, json: answer.json))
    try await call(client)
    let requests = await transport.requests
    let request = try #require(requests.first, sourceLocation: sourceLocation)
    #expect(request.httpMethod == method, sourceLocation: sourceLocation)
    #expect(request.url?.absoluteString == server + path, sourceLocation: sourceLocation)
    #expect(request.httpBody.map { String(decoding: $0, as: UTF8.self) } == body, sourceLocation: sourceLocation)
    #expect(request.value(forHTTPHeaderField: "Content-Type") == (body == nil ? nil : "application/json"), sourceLocation: sourceLocation)
    #expect(request.value(forHTTPHeaderField: "Authorization") == (authorized ? "Bearer t" : nil), sourceLocation: sourceLocation)
}

@Test func requestShapes() async throws {
    try await expectRequest("POST", "/v1/invites/redeem", body: #"{"code":"c","device_name":"Phone"}"#, authorized: false, answer: (200, redemption)) {
        _ = try await $0.redeem(code: "c", deviceName: "Phone")
    }
    try await expectRequest("POST", "/v1/sync", body: #"{"ops":[]}"#, answer: (200, synced)) {
        _ = try await $0.sync([])
    }
    try await expectRequest("POST", "/v1/signout") {
        try await $0.signOut()
    }
    try await expectRequest("PATCH", "/v1/admin/members/m", body: #"{"is_admin":true}"#) {
        try await $0.setAdmin("m", true)
    }
    try await expectRequest("DELETE", "/v1/admin/devices/d") {
        try await $0.removeDevice("d")
    }
    try await expectRequest("DELETE", "/v1/admin/members/m") {
        try await $0.removeMember("m")
    }
    try await expectRequest("GET", "/v1/admin/members", answer: (200, #"{"members":[]}"#)) {
        _ = try await $0.members()
    }
    try await expectRequest("POST", "/v1/invites", body: "{}", answer: (201, created)) {
        _ = try await $0.createInvite()
    }
    try await expectRequest("POST", "/v1/invites/revoke", body: "{}", answer: (200, #"{"revoked":1}"#)) {
        _ = try await $0.revokeInvites()
    }
    try await expectRequest("POST", "/v1/invites", body: #"{"new_member_name":"Sam"}"#, answer: (201, created)) {
        _ = try await $0.createInvite(newMemberName: "Sam")
    }
}

@Test func errorsMapToCodes() async {
    let cases: [(FakeTransport.Step, APIError)] = [
        (.answer(status: 401, json: #"{"error":"unauthorized"}"#), .server(code: "unauthorized")),
        (.answer(status: 429, json: #"{"error":"rate_limited"}"#), .server(code: "rate_limited")),
        (.answer(status: 500, json: #"{"error":"internal"}"#), .server(code: "internal")),
        (.answer(status: 404, json: "404 page not found\n"), .unexpected(status: 404)),
        (.error(URLError(.notConnectedToInternet)), .offline),
        (.answer(status: 200, json: "not the snapshot"), .unexpected(status: 200)),
    ]
    for (step, expected) in cases {
        let (client, _) = fakeClient(step)
        await #expect(throws: expected) {
            _ = try await client.sync([])
        }
    }
}
