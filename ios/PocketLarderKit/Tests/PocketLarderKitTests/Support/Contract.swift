import Foundation
@testable import PocketLarderKit

/// The real server `factory/checks.sh` starts. `#expect` and `#require` print their operands, a client
/// included, so a token, invite code or invite URL never goes inside one.
enum Contract {
    /// Carries no value, so no secret can reach the test output through it.
    enum Failure: Error {
        case notConfigured, unreadableInvite
    }

    private static let adminSession = AdminSession()

    static var isConfigured: Bool {
        environment("POCKETLARDER_TEST_SERVER") != nil && environment("POCKETLARDER_TEST_INVITE") != nil
    }

    static func serverURL() throws -> URL {
        guard let text = environment("POCKETLARDER_TEST_SERVER"), let url = URL(string: text) else {
            throw Failure.notConfigured
        }
        return url
    }

    static func admin() async throws -> APIClient {
        try await adminSession.client().value
    }

    static func newMember(_ prefix: String) async throws -> (client: APIClient, memberId: String, name: String) {
        let name = "\(prefix) \(newID().prefix(4))"
        let created = try await admin().createInvite(newMemberName: name)
        return (try await signIn(created.url), created.memberId, name)
    }

    fileprivate static func redeemAdmin() async throws -> APIClient {
        guard let url = environment("POCKETLARDER_TEST_INVITE") else { throw Failure.notConfigured }
        return try await signIn(url)
    }

    private static func signIn(_ url: String) async throws -> APIClient {
        guard let parsed = parseInvite(url) else { throw Failure.unreadableInvite }
        let server = try serverURL()
        let redemption = try await APIClient(server: server, token: nil).redeem(code: parsed.code, deviceName: "Contract test")
        return APIClient(server: server, token: redemption.token)
    }

    private static func environment(_ name: String) -> String? {
        guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else { return nil }
        return value
    }
}

/// Holds the in-flight task, not the finished client: actor methods are reentrant across `await`, so
/// parallel tests would otherwise redeem the single-use invite twice.
private actor AdminSession {
    private var task: Task<APIClient, Error>?

    func client() -> Task<APIClient, Error> {
        if let task { return task }
        let created = Task { try await Contract.redeemAdmin() }
        task = created
        return created
    }
}
