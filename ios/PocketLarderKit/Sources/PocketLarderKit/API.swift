import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol Transport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: Transport {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        // shortcut: the session holds its delegate until invalidated and this struct never does that, so each transport leaks both; upgrade if the app ever makes more than a few.
        session = URLSession(configuration: configuration, delegate: RedirectRefuser(), delegateQueue: nil)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let response = response as? HTTPURLResponse {
                    continuation.resume(returning: (data ?? Data(), response))
                } else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                }
            }.resume()
        }
    }
}

/// Keeps the bearer token from following a redirect to another host. `send` returns the 3xx as an ordinary response.
private final class RedirectRefuser: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

public enum APIError: Error, Equatable, Sendable {
    case offline
    case server(code: String)
    case unexpected(status: Int)
}

public struct Redemption: Decodable, Equatable, Sendable {
    public var token, memberId, deviceId: String
}

public struct Rejection: Codable, Equatable, Sendable {
    public var opId, reason: String
}

public struct SyncResponse: Decodable, Equatable, Sendable {
    public var rejected: [Rejection]
    public var snapshot: Snapshot
}

public struct CreatedInvite: Decodable, Equatable, Sendable {
    public var id: String
    public var url: String
    public var expiresAt: Date
    public var memberId: String
}

public struct AdminMember: Decodable, Equatable, Sendable {
    public var id, name: String
    public var isAdmin: Bool
    public var privacy: Privacy
    public var pendingInvites: Int
    public var devices: [AdminDevice]
}

public struct AdminDevice: Decodable, Equatable, Sendable {
    public var id, name: String
    public var createdAt, lastSeenAt: Date
}

/// The server decides it when it lists the invite, so the phone's clock never does.
public enum InviteState: String, Decodable, Equatable, Sendable {
    case open, redeemed, expired
}

public struct ListedInvite: Decodable, Equatable, Sendable {
    public var id: String
    public var state: InviteState
    public var expiresAt: Date
}

/// Every request body. Nil fields stay out of the JSON, so `Body()` is the `{}` the API asks for.
private struct Body: Encodable {
    var code, deviceName, memberId, newMemberName: String?
    var isAdmin: Bool?
    var ops: [Op]?
}

private struct ErrorBody: Decodable {
    let error: String
}

private struct Revoked: Decodable {
    let revoked: Int
}

private struct Members: Decodable {
    let members: [AdminMember]
}

private struct Invites: Decodable {
    let invites: [ListedInvite]
}

private struct Cleared: Decodable {
    let cleared: Int
}

private struct ServerVersion: Decodable {
    let version: String
}

public struct APIClient: Sendable {
    private let server: URL
    private let token: String?
    private let transport: any Transport

    public init(server: URL, token: String?, transport: any Transport = URLSessionTransport()) {
        self.server = server
        self.token = token
        self.transport = transport
    }

    /// Never sends the token, so it works before signing in. `minimum` and `supportedMajor` are for tests.
    public func serverVersion(
        minimum: Version = minimumServerVersion, supportedMajor: Int = supportedServerMajor
    ) async -> ServerCompatibility {
        let answer: (data: Data, status: Int)
        do {
            answer = try await send("GET", "/v1/version", authorized: false, passing: 404)
        } catch {
            return .couldNotCheck(error)
        }
        // Any 404, because a proxy's JSON `not_found` means the route is missing just as Go's plain text does.
        if answer.status == 404 { return .incompatible(.serverTooOld(nil)) }
        guard let body = try? JSON.decoder.decode(ServerVersion.self, from: answer.data), let version = Version(body.version) else {
            return .couldNotCheck(nil)
        }
        if version.major > supportedMajor { return .incompatible(.appTooOld(version)) }
        if version < minimum { return .incompatible(.serverTooOld(version)) }
        return .compatible(version)
    }

    public func redeem(code: String, deviceName: String) async throws(APIError) -> Redemption {
        try await fetch("POST", "/v1/invites/redeem", body: Body(code: code, deviceName: deviceName), authorized: false)
    }

    public func sync(_ ops: [Op]) async throws(APIError) -> SyncResponse {
        try await fetch("POST", "/v1/sync", body: Body(ops: ops))
    }

    public func createInvite(memberId: String? = nil, newMemberName: String? = nil) async throws(APIError) -> CreatedInvite {
        try await fetch("POST", "/v1/invites", body: Body(memberId: memberId, newMemberName: newMemberName))
    }

    public func revokeInvites(memberId: String? = nil) async throws(APIError) -> Int {
        let response: Revoked = try await fetch("POST", "/v1/invites/revoke", body: Body(memberId: memberId))
        return response.revoked
    }

    public func invites(memberId: String? = nil) async throws(APIError) -> [ListedInvite] {
        let response: Invites = try await fetch("GET", "/v1/invites", query: memberId.map { [URLQueryItem(name: "member_id", value: $0)] })
        return response.invites
    }

    public func cancelInvite(_ inviteId: String) async throws(APIError) {
        try await send("DELETE", "/v1/invites/\(inviteId)")
    }

    public func clearInvites(memberId: String? = nil) async throws(APIError) -> Int {
        let response: Cleared = try await fetch("POST", "/v1/invites/clear", body: Body(memberId: memberId))
        return response.cleared
    }

    public func signOut() async throws(APIError) {
        try await send("POST", "/v1/signout")
    }

    public func members() async throws(APIError) -> [AdminMember] {
        let response: Members = try await fetch("GET", "/v1/admin/members")
        return response.members
    }

    public func setAdmin(_ memberId: String, _ isAdmin: Bool) async throws(APIError) {
        try await send("PATCH", "/v1/admin/members/\(memberId)", body: Body(isAdmin: isAdmin))
    }

    public func removeMember(_ memberId: String) async throws(APIError) {
        try await send("DELETE", "/v1/admin/members/\(memberId)")
    }

    public func removeDevice(_ deviceId: String) async throws(APIError) {
        try await send("DELETE", "/v1/admin/devices/\(deviceId)")
    }

    private func fetch<Response: Decodable>(
        _ method: String, _ path: String, query: [URLQueryItem]? = nil, body: Body? = nil, authorized: Bool = true
    ) async throws(APIError) -> Response {
        let (data, status) = try await send(method, path, query: query, body: body, authorized: authorized)
        guard let response = try? JSON.decoder.decode(Response.self, from: data) else {
            throw .unexpected(status: status)
        }
        return response
    }

    /// `passing` is a status returned like a 2xx instead of thrown.
    @discardableResult
    private func send(
        _ method: String, _ path: String, query: [URLQueryItem]? = nil, body: Body? = nil, authorized: Bool = true, passing: Int? = nil
    ) async throws(APIError) -> (data: Data, status: Int) {
        var url = server.appending(path: path)
        if let query {
            url.append(queryItems: query)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if authorized, let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            guard let data = try? JSON.encoder.encode(body) else { throw .unexpected(status: 0) }
            request.httpBody = data
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        guard let (data, response) = try? await transport.send(request) else { throw .offline }
        guard (200..<300).contains(response.statusCode) || response.statusCode == passing else {
            // `unauthorized` wipes the phone, so a gateway's 403 or 500 with that body must not count as one.
            if let failure = try? JSON.decoder.decode(ErrorBody.self, from: data),
               failure.error != "unauthorized" || response.statusCode == 401 {
                throw .server(code: failure.error)
            }
            throw .unexpected(status: response.statusCode)
        }
        return (data, response.statusCode)
    }
}
