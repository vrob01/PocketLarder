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

@Test func redirectsAreNotFollowed() async throws {
    let target = try LoopbackServer(answer: "200 OK\r\n")
    let targetURL = "http://localhost:\(target.port)/v1/sync"
    let (_, control) = try await URLSessionTransport().send(URLRequest(url: URL(string: targetURL)!))
    #expect(control.statusCode == 200)
    #expect(target.requests.count == 1)

    for status in [301, 302, 303, 307, 308] {
        let origin = try LoopbackServer(answer: "\(status) Redirect\r\nLocation: \(targetURL)\r\n")
        let client = APIClient(server: URL(string: "http://127.0.0.1:\(origin.port)")!, token: "t")
        await #expect(throws: APIError.unexpected(status: status)) {
            _ = try await client.sync([])
        }
        #expect(origin.requests.count == 1)
        #expect(origin.requests.first?.localizedCaseInsensitiveContains("Authorization: Bearer t") == true)
    }

    #expect(target.requests.count == 1)
    #expect(!target.requests.contains { $0.localizedCaseInsensitiveContains("Authorization:") })
}

#if canImport(Glibc)
private let streamSocket = Int32(SOCK_STREAM.rawValue)
#else
private let streamSocket = SOCK_STREAM
#endif

/// A real HTTP server on `127.0.0.1` that records each raw request and gives every one the same empty answer.
private final class LoopbackServer: @unchecked Sendable {
    let port: Int
    private let answer: String
    private let lock = NSLock()
    private var recorded: [String] = []

    var requests: [String] {
        lock.withLock { recorded }
    }

    /// `answer` is the status line and any headers, without the leading `HTTP/1.1 `.
    init(answer: String) throws {
        self.answer = answer
        let listener = socket(AF_INET, streamSocket, 0)
        try #require(listener >= 0)
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listener, $0, length) == 0 && getsockname(listener, $0, &length) == 0
            }
        }
        try #require(bound && listen(listener, 16) == 0)
        port = Int(UInt16(bigEndian: address.sin_port))
        // shortcut: the listener and its thread live until the test process exits, fine for one test's few servers.
        Thread { [self] in serve(listener) }.start()
    }

    private func serve(_ listener: Int32) {
        while true {
            let connection = accept(listener, nil, nil)
            guard connection >= 0 else { return }
            let request = readRequest(connection)
            // A connection that closes without sending anything is not a request.
            if !request.isEmpty {
                lock.withLock { recorded.append(String(decoding: request, as: UTF8.self)) }
            }
            let reply = Data("HTTP/1.1 \(answer)Content-Length: 0\r\nConnection: close\r\n\r\n".utf8)
            _ = reply.withUnsafeBytes { write(connection, $0.baseAddress, $0.count) }
            close(connection)
        }
    }

    /// Reads the headers and their `Content-Length` bytes. Closing with unread bytes could reset the connection.
    private func readRequest(_ connection: Int32) -> Data {
        var request = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while !isComplete(request) {
            let count = read(connection, &chunk, chunk.count)
            guard count > 0 else { break }
            request.append(contentsOf: chunk[..<count])
        }
        return request
    }

    private func isComplete(_ request: Data) -> Bool {
        guard let end = request.range(of: Data("\r\n\r\n".utf8)) else { return false }
        let name = "content-length:"
        let contentLength = String(decoding: request[..<end.lowerBound], as: UTF8.self).lowercased()
            .components(separatedBy: "\r\n")
            .first { $0.hasPrefix(name) }
            .flatMap { Int($0.dropFirst(name.count).drop { $0 == " " }) } ?? 0
        return request.count - end.upperBound >= contentLength
    }
}
