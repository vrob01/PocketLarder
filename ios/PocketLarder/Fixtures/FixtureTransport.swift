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

    private struct MembersAnswer: Encodable {
        let members: [MemberAnswer]
    }

    private struct MemberAnswer: Encodable {
        let id, name: String
        var isAdmin: Bool
        let privacy: Privacy
        var pendingInvites: Int
        var devices: [DeviceAnswer]
    }

    private struct DeviceAnswer: Encodable {
        let id, name: String
        let createdAt: Date
        var lastSeenAt: Date
    }

    /// Every admin request body.
    private struct AdminBody: Decodable {
        let isAdmin: Bool?
        let memberId, newMemberName: String?
    }

    private var snapshot: Snapshot
    /// What `GET /v1/admin/members` lists. Changes to it don't reach the snapshot.
    private var members: [MemberAnswer]

    init(_ snapshot: Snapshot) {
        self.snapshot = snapshot
        let launch = Date.now
        members = snapshot.members.map { member in
            let mine = member.id == snapshot.me.memberId
            let device = DeviceAnswer(
                id: mine ? snapshot.me.deviceId : newID(),
                name: "iPhone",
                createdAt: launch.addingTimeInterval(-7 * 24 * 60 * 60),
                lastSeenAt: mine ? launch : launch.addingTimeInterval(-2 * 60 * 60)
            )
            return MemberAnswer(id: member.id, name: member.name, isAdmin: member.isAdmin, privacy: member.privacy, pendingInvites: 0, devices: [device])
        }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let path = request.url?.path ?? ""
        let id = request.url?.lastPathComponent ?? ""
        let body = request.httpBody ?? Data()
        switch (request.httpMethod ?? "", path) {
        case ("POST", "/v1/sync"):
            let ops = try JSON.decoder.decode(SyncBody.self, from: body).ops
            snapshot = applying(ops.map { PendingOp(op: $0, at: .now) }, to: snapshot)
            return (try JSON.encoder.encode(SyncAnswer(rejected: [], snapshot: snapshot)), response(to: request, status: 200))
        case ("POST", "/v1/invites"):
            return try invite(request, JSON.decoder.decode(AdminBody.self, from: body))
        case ("POST", "/v1/invites/revoke"):
            let memberId = try JSON.decoder.decode(AdminBody.self, from: body).memberId ?? snapshot.me.memberId
            guard let index = members.firstIndex(where: { $0.id == memberId }) else { return refusal(request, 404, "not_found") }
            let revoked = members[index].pendingInvites
            members[index].pendingInvites = 0
            return (Data(#"{"revoked":\#(revoked)}"#.utf8), response(to: request, status: 200))
        case ("GET", "/v1/admin/members"):
            // The server records each request as its device's last sighting.
            if let index = members.firstIndex(where: { $0.id == snapshot.me.memberId }),
               let device = members[index].devices.firstIndex(where: { $0.id == snapshot.me.deviceId }) {
                members[index].devices[device].lastSeenAt = .now
            }
            return (try JSON.encoder.encode(MembersAnswer(members: members.sorted { $0.id < $1.id })), response(to: request, status: 200))
        case ("PATCH", "/v1/admin/members/\(id)"):
            guard let index = members.firstIndex(where: { $0.id == id }) else { return refusal(request, 404, "not_found") }
            guard let isAdmin = try JSON.decoder.decode(AdminBody.self, from: body).isAdmin else { return refusal(request, 400, "invalid") }
            guard isAdmin || members.contains(where: { $0.isAdmin && $0.id != id }) else { return refusal(request, 409, "last_admin") }
            members[index].isAdmin = isAdmin
            return (Data(), response(to: request, status: 204))
        case ("DELETE", "/v1/admin/members/\(id)"):
            guard let index = members.firstIndex(where: { $0.id == id }) else { return refusal(request, 404, "not_found") }
            guard !members[index].isAdmin || members.contains(where: { $0.isAdmin && $0.id != id }) else {
                return refusal(request, 409, "last_admin")
            }
            members.remove(at: index)
            return (Data(), response(to: request, status: 204))
        case ("DELETE", "/v1/admin/devices/\(id)"):
            guard let index = members.firstIndex(where: { $0.devices.contains { $0.id == id } }) else { return refusal(request, 404, "not_found") }
            members[index].devices.removeAll { $0.id == id }
            return (Data(), response(to: request, status: 204))
        default:
            return refusal(request, 404, "not_found")
        }
    }

    /// `{}` invites another device for this iPhone's member, `member_id` one for that member, and `new_member_name` a
    /// new member.
    private func invite(_ request: URLRequest, _ body: AdminBody) throws -> (Data, HTTPURLResponse) {
        var memberId = snapshot.me.memberId
        if let name = body.newMemberName {
            guard !members.contains(where: { $0.name.lowercased() == name.lowercased() }) else { return refusal(request, 409, "conflict") }
            memberId = newID()
            members.append(MemberAnswer(id: memberId, name: name, isAdmin: false, privacy: .open, pendingInvites: 1, devices: []))
        } else if let id = body.memberId {
            guard let index = members.firstIndex(where: { $0.id == id }) else { return refusal(request, 404, "not_found") }
            members[index].pendingInvites += 1
            memberId = id
        }
        // A dummy, so that no real invite shows in a screenshot.
        let invite = InviteAnswer(
            url: "pocketlarder://invite?server=https%3A%2F%2Ffixture.invalid&code=fixture-dummy-invite",
            expiresAt: .now.addingTimeInterval(24 * 60 * 60),
            memberId: memberId
        )
        return (try JSON.encoder.encode(invite), response(to: request, status: 201))
    }

    private func refusal(_ request: URLRequest, _ status: Int, _ code: String) -> (Data, HTTPURLResponse) {
        (Data(#"{"error":"\#(code)"}"#.utf8), response(to: request, status: status))
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
