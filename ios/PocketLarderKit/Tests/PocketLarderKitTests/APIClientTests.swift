import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import PocketLarderKit

private let server = "https://lists.example.test"
private let redemption = #"{"token":"t","member_id":"m","device_id":"d"}"#
private let synced = #"{"rejected":[],"snapshot":{"me":{"member_id":"m","device_id":"d","is_admin":false},"members":[],"lists":[],"stores":[],"categories":[],"items":[],"placements":[],"entries":[]}}"#
private let created = #"{"id":"i","url":"pocketlarder://invite?server=https%3A%2F%2Flists.example.test&code=c","expires_at":"2026-10-28T09:00:00Z","member_id":"m"}"#

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
    try await expectRequest("GET", "/v1/version", authorized: false, answer: (200, #"{"version":"0.1.0"}"#)) {
        _ = await $0.serverVersion()
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
    try await expectRequest("GET", "/v1/invites", answer: (200, #"{"invites":[]}"#)) {
        _ = try await $0.invites()
    }
    try await expectRequest("GET", "/v1/invites?member_id=m", answer: (200, #"{"invites":[]}"#)) {
        _ = try await $0.invites(memberId: "m")
    }
    try await expectRequest("DELETE", "/v1/invites/i") {
        try await $0.cancelInvite("i")
    }
    try await expectRequest("POST", "/v1/invites/clear", body: "{}", answer: (200, #"{"cleared":2}"#)) {
        _ = try await $0.clearInvites()
    }
    try await expectRequest("POST", "/v1/invites/clear", body: #"{"member_id":"m"}"#, answer: (200, #"{"cleared":2}"#)) {
        _ = try await $0.clearInvites(memberId: "m")
    }
}

@Test func createdInviteDecodes() async throws {
    let (client, _) = fakeClient(.answer(status: 201, json: created))
    let invite = try await client.createInvite()
    #expect(invite.id == "i")
    #expect(invite.memberId == "m")
    #expect(invite.expiresAt == Date(timeIntervalSince1970: 1_793_178_000))
}

@Test func listedInvitesDecode() async throws {
    let json = #"""
    {"invites":[
      {"id":"a","state":"open","expires_at":"2027-01-15T09:00:00Z"},
      {"id":"b","state":"redeemed","expires_at":"2027-01-15T08:00:00Z"},
      {"id":"c","state":"expired","expires_at":"2027-01-15T07:00:00Z"}
    ]}
    """#
    let (client, _) = fakeClient(.answer(status: 200, json: json))
    let invites = try await client.invites()
    #expect(invites == [
        ListedInvite(id: "a", state: .open, expiresAt: Date(timeIntervalSince1970: 1_800_003_600)),
        ListedInvite(id: "b", state: .redeemed, expiresAt: Date(timeIntervalSince1970: 1_800_000_000)),
        ListedInvite(id: "c", state: .expired, expiresAt: Date(timeIntervalSince1970: 1_799_996_400)),
    ])
    let (cleared, _) = fakeClient(.answer(status: 200, json: #"{"cleared":2}"#))
    #expect(try await cleared.clearInvites() == 2)
}

@Test func errorsMapToCodes() async {
    let cases: [(FakeTransport.Step, APIError)] = [
        (.answer(status: 401, json: #"{"error":"unauthorized"}"#), .server(code: "unauthorized")),
        (.answer(status: 403, json: #"{"error":"unauthorized"}"#), .unexpected(status: 403)),
        (.answer(status: 500, json: #"{"error":"unauthorized"}"#), .unexpected(status: 500)),
        (.answer(status: 401, json: #"{"error":"missing_token"}"#), .server(code: "missing_token")),
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

/// The trusted host's refusal keeps its reason. Any other transport error, including an untrusted host's certificate
/// error, is still offline.
@Test func refusedCertificateKeepsItsReason() async {
    let reason = "Certificate 0 “lists.example.test” has errors: SSL hostname does not match name(s) in certificate;"
    let refused = FakeTransport.Step.error(CertificateRefused(host: "lists.example.test", reason: reason))
    let (client, _) = fakeClient(refused)
    await #expect(throws: APIError.certificateRefused(reason: reason)) {
        _ = try await client.sync([])
    }
    let (checking, _) = fakeClient(refused)
    #expect(await checking.serverVersion() == .couldNotCheck(.certificateRefused(reason: reason)))
    let (untrusted, _) = fakeClient(.error(URLError(.serverCertificateUntrusted)))
    await #expect(throws: APIError.offline) {
        _ = try await untrusted.sync([])
    }
}

/// Its own minimum and major, so that raising the app's setting changes nothing here.
@Test func serverVersionOutcomes() async {
    let cases: [(FakeTransport.Step, ServerCompatibility)] = [
        (.answer(status: 200, json: #"{"version":"1.2.0"}"#), .compatible(Version(1, 2, 0))),
        (.answer(status: 200, json: #"{"version":"1.10.3"}"#), .compatible(Version(1, 10, 3))),
        (.answer(status: 200, json: #"{"version":"1.1.9"}"#), .incompatible(.serverTooOld(Version(1, 1, 9)))),
        (.answer(status: 200, json: #"{"version":"0.9.0"}"#), .incompatible(.serverTooOld(Version(0, 9, 0)))),
        (.answer(status: 404, json: "404 page not found\n"), .incompatible(.serverTooOld(nil))),
        (.answer(status: 404, json: #"{"error":"not_found"}"#), .incompatible(.serverTooOld(nil))),
        (.answer(status: 200, json: #"{"version":"2.0.0"}"#), .incompatible(.appTooOld(Version(2, 0, 0)))),
        (.error(URLError(.notConnectedToInternet)), .couldNotCheck(.offline)),
        (.error(URLError(.timedOut)), .couldNotCheck(.offline)),
        (.answer(status: 500, json: #"{"error":"internal"}"#), .couldNotCheck(.server(code: "internal"))),
        (.answer(status: 502, json: "Bad Gateway"), .couldNotCheck(.unexpected(status: 502))),
        (.answer(status: 301, json: ""), .couldNotCheck(.unexpected(status: 301))),
        (.answer(status: 200, json: "{}"), .couldNotCheck(nil)),
        (.answer(status: 200, json: "0.1.0"), .couldNotCheck(nil)),
        (.answer(status: 200, json: #"{"version":"0.1"}"#), .couldNotCheck(nil)),
    ]
    for (step, expected) in cases {
        let (client, _) = fakeClient(step)
        #expect(await client.serverVersion(minimum: Version(1, 2, 0), supportedMajor: 1) == expected)
    }
}

/// Also while a host is trusted, and after a change of it, because each change moves the transport to a new session.
@Test(arguments: [[], ["127.0.0.1"], ["localhost", "127.0.0.1"]])
func redirectsAreNotFollowed(trusting hosts: [String]) async throws {
    let transport = URLSessionTransport()
    for host in hosts {
        transport.trust(host: host)
    }
    let target = try LoopbackServer(answer: "200 OK\r\n")
    let targetURL = "http://localhost:\(target.port)/v1/sync"
    let (_, control) = try await transport.send(URLRequest(url: URL(string: targetURL)!))
    #expect(control.statusCode == 200)
    #expect(target.requests.count == 1)

    for status in [301, 302, 303, 307, 308] {
        let origin = try LoopbackServer(answer: "\(status) Redirect\r\nLocation: \(targetURL)\r\n")
        let client = APIClient(server: URL(string: "http://127.0.0.1:\(origin.port)")!, token: "t", transport: transport)
        await #expect(throws: APIError.unexpected(status: status)) {
            _ = try await client.sync([])
        }
        #expect(origin.requests.count == 1)
        #expect(origin.requests.first?.localizedCaseInsensitiveContains("Authorization: Bearer t") == true)
    }

    #expect(target.requests.count == 1)
    #expect(!target.requests.contains { $0.localizedCaseInsensitiveContains("Authorization:") })
}

@Test func onlyTheTrustedHostIsTrusted() {
    let delegate = SessionDelegate(trustedHost: "lists.example.test")
    #expect(delegate.trusts("lists.example.test"))
    #expect(delegate.trusts("Lists.EXAMPLE.test"))
    for other in ["other.example.test", "example.test", "www.lists.example.test", "evil-lists.example.test", "lists.example.test.evil", "lists.example.testx", ""] {
        #expect(!delegate.trusts(other), "\(other) is trusted")
    }
    #expect(!SessionDelegate(trustedHost: nil).trusts("lists.example.test"))
}

@Test func newTransportTrustsNothing() throws {
    let delegate = try #require(URLSessionTransport().session.delegate as? SessionDelegate)
    #expect(delegate.trustedHost == nil)
}

/// So that no connection accepted under the old setting serves a later request.
@Test func trustChangeMovesToNewSession() throws {
    let transport = URLSessionTransport()
    let untrusting = transport.session
    transport.trust(host: "lists.example.test")
    let trusting = transport.session
    #expect(trusting !== untrusting)
    #expect(try #require(trusting.delegate as? SessionDelegate).trustedHost == "lists.example.test")

    transport.trust(host: "lists.example.test")
    #expect(transport.session === trusting)

    transport.trust(host: nil)
    #expect(transport.session !== trusting)
    #expect(try #require(transport.session.delegate as? SessionDelegate).trustedHost == nil)
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
