import Foundation
import PocketLarderKit
import Testing
@testable import PocketLarder

private let example = "pocketlarder://invite?server=https%3A%2F%2Flists.example.com&code=fdd4efb3-cf5b-44e7-bec4-94df8e478f5f.ArBLMeKiOpJu5jbcasIRDr8-zlqlbdWCoIfZ9EsLPio"
private let server = URL(string: "https://lists.example.test")!
private let invite = Invite(server: server, code: "code")
private let member = "10000000-0000-4000-8000-000000000001"
private let device = "10000000-0000-4000-8000-0000000000d1"
private let account = Account(server: server, token: "test-token", memberId: member, deviceId: device)
private let offline = FakeTransport.Step.error(URLError(.notConnectedToInternet))
private let unauthorized = FakeTransport.Step.answer(status: 401, json: #"{"error":"unauthorized"}"#)
private let signedOut = FakeTransport.Step.answer(status: 204, json: "")

private func redeemJSON(token: String) -> String {
    #"{"token":"\#(token)","member_id":"\#(member)","device_id":"\#(device)"}"#
}

private func redeemed(token: String = "test-token") -> FakeTransport.Step {
    .answer(status: 200, json: redeemJSON(token: token))
}

private let syncJSON = #"""
    {"rejected":[],"snapshot":{"me":{"member_id":"\#(member)","device_id":"\#(device)","is_admin":true},\#
    "members":[{"id":"\#(member)","name":"Alex","is_admin":true,"privacy":"open"}],\#
    "lists":[],"stores":[],"categories":[],"items":[],"placements":[],"entries":[]}}
    """#
private let synced = FakeTransport.Step.answer(status: 200, json: syncJSON)

private func tea() -> Op {
    Op(.entryAdd, id: newID(), listId: newID(), text: "Tea")
}

private func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appending(path: newID())
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func contents(_ directory: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: directory.path)
}

/// A new directory holding what a signed-in phone leaves behind: a snapshot and 1 unsent op.
private func seededDirectory() throws -> URL {
    let directory = try temporaryDirectory()
    let files = LocalFiles(directory: directory)
    try files.save(snapshot: try JSON.decoder.decode(SyncResponse.self, from: Data(syncJSON.utf8)).snapshot)
    try files.save(queue: [PendingOp(op: tea(), at: .now)])
    return directory
}

/// Signed in with a new directory and an empty Keychain. `script` answers the requests after the sign-in's two.
@MainActor private func signedIn(
    _ script: [FakeTransport.Step] = []
) async throws -> (model: AppModel, transport: FakeTransport, directory: URL) {
    Keychain.delete()
    let directory = try temporaryDirectory()
    let transport = FakeTransport([redeemed(), synced] + script)
    let model = AppModel(transport: transport, dataDirectory: directory)
    try #require(await model.signIn(invite, deviceName: "iPhone") == nil)
    return (model, transport, directory)
}

private func paths(_ transport: FakeTransport) async -> [String?] {
    await transport.requests.map(\.url?.path)
}

/// A forced sign-out returns before its request reaches the transport.
@MainActor private func revokeShows(_ transport: FakeTransport) async -> Bool {
    await waitUntil { await paths(transport).contains("/v1/signout") }
}

/// Every request sent with `token`, as its method, host and path.
private func sent(_ transport: FakeTransport, token: String) async -> [String] {
    await transport.requests
        .filter { $0.value(forHTTPHeaderField: "Authorization") == "Bearer \(token)" }
        .map { "\($0.httpMethod ?? "") \($0.url?.host() ?? "")\($0.url?.path ?? "")" }
}

/// A `sync()` the test doesn't wait for. It runs up to its first suspension before the initializer returns.
@MainActor private final class SyncCall {
    private(set) var returned = false

    init(_ larder: Larder) {
        Task.immediate {
            await larder.sync()
            self.returned = true
        }
    }
}

/// False after 30 seconds, so a bug fails the test instead of hanging the gate.
@MainActor private func waitUntil(_ condition: () async -> Bool) async -> Bool {
    for _ in 0..<3000 {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return false
}

/// A `signIn` the test doesn't wait for yet, whose request is open on the script's first step, a `.hold`.
@MainActor private func openSignIn(_ model: AppModel, _ transport: FakeTransport) async throws -> Task<AppModel.SignInError?, Never> {
    let redeeming = Task { await model.signIn(invite, deviceName: "iPhone") }
    try #require(await waitUntil { await transport.requests.count == 1 })
    return redeeming
}

/// A sign-in still waiting for its answer, overtaken by a second one that completed, with an empty Keychain before.
/// `script` answers the requests after those three. By default `signedOut` answers the late answer's revoke and a
/// forced sign-out, and the last step answers a request a correct run never sends, such as the sync that a late answer
/// must not start, so a bug fails the test instead of crashing the process.
@MainActor private func overtakenSignIn(_ script: [FakeTransport.Step] = [signedOut, signedOut, synced]) async throws -> (
    model: AppModel, transport: FakeTransport, directory: URL, first: Task<AppModel.SignInError?, Never>
) {
    Keychain.delete()
    let directory = try temporaryDirectory()
    let transport = FakeTransport([.hold, redeemed(token: "next-token"), synced] + script)
    let model = AppModel(transport: transport, dataDirectory: directory)
    let first = try await openSignIn(model, transport)
    try #require(await model.signIn(invite, deviceName: "iPhone") == nil)
    return (model, transport, directory, first)
}

private struct RedeemBody: Decodable {
    let code, deviceName: String
}

private struct SyncBody: Decodable {
    let ops: [Op]
}

private struct SaveFailed: Error {}

extension KeychainSuite {
    @Test @MainActor func openingInviteLinkSetsPendingInvite() throws {
        defer { Keychain.delete() }
        let model = AppModel(transport: FakeTransport([]), dataDirectory: try temporaryDirectory())
        model.open(try #require(URL(string: example)))
        let invite = try #require(parseInvite(example))
        #expect(model.pendingInvite == invite)

        model.open(try #require(URL(string: "https://example.com")))
        #expect(model.pendingInvite == invite)
    }

    @Test @MainActor func signInStoresAccountAndSyncs() async throws {
        defer { Keychain.delete() }
        let transport = FakeTransport([redeemed(), synced])
        let model = AppModel(transport: transport, dataDirectory: try temporaryDirectory())
        #expect(model.memberName == "")

        #expect(await model.signIn(invite, deviceName: "Kitchen iPhone") == nil)

        #expect(model.account == account)
        #expect(Keychain.load() == model.account)
        #expect(model.larder?.snapshot != nil)
        #expect(model.memberName == "Alex")
        let requests = await transport.requests
        #expect(requests.map(\.url?.path) == ["/v1/invites/redeem", "/v1/sync"])
        let body = try JSON.decoder.decode(RedeemBody.self, from: try #require(requests.first?.httpBody))
        #expect(body.deviceName == "Kitchen iPhone")
        #expect(body.code == "code")
    }

    @Test @MainActor func signInErrors() async throws {
        defer { Keychain.delete() }
        let cases: [(FakeTransport.Step, AppModel.SignInError)] = [
            (.answer(status: 401, json: #"{"error":"invalid_invite"}"#), .invalidInvite),
            (.answer(status: 429, json: #"{"error":"rate_limited"}"#), .rateLimited),
            (offline, .unreachable(host: "lists.example.test")),
            (.answer(status: 500, json: #"{"error":"internal"}"#), .other),
        ]
        for (step, expected) in cases {
            let model = AppModel(transport: FakeTransport([step]), dataDirectory: try temporaryDirectory())
            #expect(await model.signIn(invite, deviceName: "iPhone") == expected)
            #expect(model.account == nil)
            #expect(model.larder == nil)
            #expect(Keychain.load() == nil)
        }
    }

    @Test @MainActor func unauthorizedSyncSignsOut() async throws {
        defer { Keychain.delete() }
        let (model, _, directory) = try await signedIn([unauthorized])
        let larder = try #require(model.larder)
        try larder.perform([tea(), tea()])

        await larder.sync()

        #expect(model.account == nil)
        #expect(model.larder == nil)
        #expect(Keychain.load() == nil)
        #expect(try contents(directory) == [])
        #expect(model.signedOutLostChanges == 2)
    }

    @Test @MainActor func signOutPaths() async throws {
        defer { Keychain.delete() }
        let (model, transport, directory) = try await signedIn([offline, signedOut])
        let op = tea()
        try model.larder?.perform([op])

        #expect(await model.signOut(force: false) == .unreachable)
        #expect(model.account == account)
        #expect(Keychain.load() == account)
        #expect(model.larder?.pending.map(\.op) == [op])
        #expect(!(await paths(transport)).contains("/v1/signout"))

        #expect(await model.signOut(force: true) == .done)
        #expect(model.account == nil)
        #expect(model.larder == nil)
        #expect(Keychain.load() == nil)
        #expect(try contents(directory) == [])
        #expect(model.signedOutLostChanges == nil)
        #expect(await revokeShows(transport))

        let (clean, cleanTransport, cleanDirectory) = try await signedIn([synced, signedOut])
        #expect(await clean.signOut(force: false) == .done)
        let last = try #require(await cleanTransport.requests.last)
        #expect(last.httpMethod == "POST")
        #expect(last.url?.path == "/v1/signout")
        #expect(clean.account == nil)
        #expect(Keychain.load() == nil)
        #expect(try contents(cleanDirectory) == [])
        #expect(clean.signedOutLostChanges == nil)
    }

    @Test @MainActor func inviteLinkWhileSignedIn() async throws {
        defer { Keychain.delete() }
        let (model, transport, _) = try await signedIn()

        model.open(try #require(URL(string: example)))
        #expect(model.alreadySignedInAs == "Alex")
        #expect(model.pendingInvite == nil)
        #expect(model.account == account)

        #expect(await model.signIn(invite, deviceName: "iPhone") == .alreadySignedIn(name: "Alex"))
        #expect(model.account == account)
        #expect(await transport.requests.count == 2)
    }

    @Test @MainActor func forcedSignOutDropsAnswerInFlight() async throws {
        defer { Keychain.delete() }
        let (model, transport, directory) = try await signedIn([.hold, signedOut])
        let call = SyncCall(try #require(model.larder))
        try #require(await waitUntil { await transport.requests.count == 3 })

        #expect(await model.signOut(force: true) == .done)
        #expect(!call.returned)
        #expect(await waitUntil { await transport.requests.count == 4 })

        await transport.release(status: 200, json: syncJSON)
        try #require(await waitUntil { call.returned })
        #expect(try contents(directory) == [])
        #expect(model.account == nil)
        #expect(await transport.requests.count == 4)
    }

    @Test @MainActor func lateUnauthorizedSparesNextAccount() async throws {
        defer { Keychain.delete() }
        let (model, transport, directory) = try await signedIn([.hold, signedOut, redeemed(token: "next-token"), synced])
        let call = SyncCall(try #require(model.larder))
        try #require(await waitUntil { await transport.requests.count == 3 })

        #expect(await model.signOut(force: true) == .done)
        #expect(await waitUntil { await transport.requests.count == 4 })
        #expect(await model.signIn(invite, deviceName: "iPhone") == nil)
        let next = try #require(model.account)
        #expect(next.token == "next-token")

        await transport.release(status: 401, json: #"{"error":"unauthorized"}"#)
        try #require(await waitUntil { call.returned })
        #expect(model.account == next)
        #expect(Keychain.load() == next)
        #expect(model.larder?.snapshot != nil)
        #expect(try contents(directory).contains("snapshot.json"))
        #expect(model.signedOutLostChanges == nil)
    }

    @Test @MainActor func lateRedeemSparesSignedInAccount() async throws {
        defer { Keychain.delete() }
        let (model, transport, directory, first) = try await overtakenSignIn()
        let next = try #require(model.account)
        let larder = try #require(model.larder)
        #expect(next.token == "next-token")

        await transport.release(status: 200, json: redeemJSON(token: "late-token"))

        #expect(await first.value == .alreadySignedIn(name: "Alex"))
        #expect(model.account == next)
        #expect(Keychain.load() == next)
        #expect(model.larder === larder)
        #expect(try contents(directory).contains("snapshot.json"))
        #expect(await revokeShows(transport))
        try await Task.sleep(for: .milliseconds(50))
        #expect(await transport.requests.count == 4)
        #expect(await sent(transport, token: "late-token") == ["POST lists.example.test/v1/signout"])
    }

    @Test @MainActor func lateRedeemIgnoresRevokeAnswer() async throws {
        defer { Keychain.delete() }
        for answer in [unauthorized, .answer(status: 500, json: #"{"error":"internal"}"#), offline] {
            let (model, transport, directory, first) = try await overtakenSignIn([answer, synced])
            let next = try #require(model.account)
            let larder = try #require(model.larder)

            await transport.release(status: 200, json: redeemJSON(token: "late-token"))

            #expect(await first.value == .alreadySignedIn(name: "Alex"))
            #expect(await revokeShows(transport))
            try await Task.sleep(for: .milliseconds(50))
            #expect(model.account == next)
            #expect(Keychain.load() == next)
            #expect(model.larder === larder)
            #expect(try contents(directory).contains("snapshot.json"))
            #expect(model.signedOutLostChanges == nil)
            #expect(await transport.requests.count == 4)
        }
    }

    @Test @MainActor func heldLateRevokeSparesSignedInAccount() async throws {
        defer { Keychain.delete() }
        let (model, transport, directory, first) = try await overtakenSignIn([.hold, synced])
        let next = try #require(model.account)
        let larder = try #require(model.larder)
        await transport.release(status: 200, json: redeemJSON(token: "late-token"))

        var dropped: AppModel.SignInError?
        Task { dropped = await first.value }
        #expect(await waitUntil { dropped != nil })
        #expect(dropped == .alreadySignedIn(name: "Alex"))
        try #require(await revokeShows(transport))

        await transport.release(status: 401, json: #"{"error":"unauthorized"}"#)

        try await Task.sleep(for: .milliseconds(50))
        #expect(model.account == next)
        #expect(Keychain.load() == next)
        #expect(model.larder === larder)
        #expect(try contents(directory).contains("snapshot.json"))
        #expect(model.signedOutLostChanges == nil)
        #expect(await transport.requests.count == 4)
    }

    @Test @MainActor func lateRedeemAfterSignOutStaysSignedOut() async throws {
        defer { Keychain.delete() }
        let (model, transport, _, first) = try await overtakenSignIn()
        #expect(await model.signOut(force: true) == .done)
        #expect(await revokeShows(transport))
        #expect(await transport.requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer next-token")

        await transport.release(status: 200, json: redeemJSON(token: "late-token"))

        #expect(await first.value == .other)
        #expect(model.account == nil)
        #expect(model.larder == nil)
        #expect(Keychain.load() == nil)
        #expect(await waitUntil { await transport.requests.count == 5 })
        try await Task.sleep(for: .milliseconds(50))
        #expect(await transport.requests.count == 5)
        #expect(await sent(transport, token: "late-token") == ["POST lists.example.test/v1/signout"])
    }

    @Test @MainActor func forcedSignOutRevokesDevice() async throws {
        defer { Keychain.delete() }
        let invalid = FakeTransport.Step.answer(status: 400, json: #"{"error":"invalid"}"#)
        let routes: [(script: [FakeTransport.Step], dialog: AppModel.SignOutResult?)] = [
            ([signedOut], nil),
            ([invalid, signedOut], .unsentChanges(1)),
            ([offline, signedOut], .unreachable),
        ]
        for route in routes {
            let (model, transport, directory) = try await signedIn(route.script)
            if let dialog = route.dialog {
                try model.larder?.perform([tea()])
                #expect(await model.signOut(force: false) == dialog)
            }
            #expect(!(await paths(transport)).contains("/v1/signout"))

            #expect(await model.signOut(force: true) == .done)

            #expect(model.account == nil)
            #expect(model.larder == nil)
            #expect(Keychain.load() == nil)
            #expect(try contents(directory) == [])
            #expect(model.signedOutLostChanges == nil)
            #expect(await revokeShows(transport))
            if route.dialog == nil {
                #expect(await model.signOut(force: true) == .done)
            }
            try await Task.sleep(for: .milliseconds(50))
            let revokes = await transport.requests.filter { $0.url?.path == "/v1/signout" }
            #expect(revokes.count == 1)
            #expect(revokes.first?.httpMethod == "POST")
            #expect(revokes.first?.url?.host() == "lists.example.test")
            #expect(revokes.first?.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        }
    }

    @Test @MainActor func forcedSignOutIgnoresRevokeAnswer() async throws {
        defer { Keychain.delete() }
        for answer in [unauthorized, .answer(status: 500, json: #"{"error":"internal"}"#), offline] {
            let (model, transport, directory) = try await signedIn([answer])

            #expect(await model.signOut(force: true) == .done)

            #expect(await revokeShows(transport))
            try await Task.sleep(for: .milliseconds(50))
            #expect(model.account == nil)
            #expect(model.larder == nil)
            #expect(Keychain.load() == nil)
            #expect(try contents(directory) == [])
            #expect(model.signedOutLostChanges == nil)
            #expect(await transport.requests.count == 3)
        }
    }

    @Test @MainActor func heldRevokeSparesNextAccount() async throws {
        defer { Keychain.delete() }
        let (model, transport, directory) = try await signedIn([.hold, redeemed(token: "next-token"), synced])
        var returned = false
        Task {
            _ = await model.signOut(force: true)
            returned = true
        }
        #expect(await waitUntil { returned })
        // If it never shows, the next `signIn` would wait on the `.hold` itself, and nothing is held to release.
        try #require(await revokeShows(transport))
        #expect(await model.signIn(invite, deviceName: "iPhone") == nil)

        await transport.release(status: 401, json: #"{"error":"unauthorized"}"#)

        try await Task.sleep(for: .milliseconds(50))
        #expect(model.account?.token == "next-token")
        #expect(Keychain.load() == model.account)
        #expect(try contents(directory).contains("snapshot.json"))
        #expect(model.signedOutLostChanges == nil)
        #expect(await transport.requests.count == 5)
    }

    @Test @MainActor func failedSaveRevokesDevice() async throws {
        defer { Keychain.delete() }
        for answer in [unauthorized, .answer(status: 500, json: #"{"error":"internal"}"#), offline] {
            let directory = try seededDirectory()
            let transport = FakeTransport([redeemed(), answer, synced])
            let model = AppModel(transport: transport, dataDirectory: directory, saveAccount: { _ in throw SaveFailed() })

            #expect(await model.signIn(invite, deviceName: "iPhone") == .other)

            #expect(await revokeShows(transport))
            try await Task.sleep(for: .milliseconds(50))
            #expect(await sent(transport, token: "test-token") == ["POST lists.example.test/v1/signout"])
            #expect(model.account == nil)
            #expect(model.larder == nil)
            #expect(Keychain.load() == nil)
            #expect(try contents(directory).sorted() == ["queue.json", "snapshot.json"])
            #expect(model.signedOutLostChanges == nil)
            #expect(await transport.requests.count == 2)
        }
    }

    @Test @MainActor func heldFailedSaveRevokeSparesNextAccount() async throws {
        defer { Keychain.delete() }
        let directory = try temporaryDirectory()
        let transport = FakeTransport([redeemed(), .hold, redeemed(token: "next-token"), synced, synced])
        var failsOnce = true
        let model = AppModel(transport: transport, dataDirectory: directory, saveAccount: {
            if failsOnce {
                failsOnce = false
                throw SaveFailed()
            }
            try Keychain.save($0)
        })
        var dropped: AppModel.SignInError?
        Task { dropped = await model.signIn(invite, deviceName: "iPhone") }
        #expect(await waitUntil { dropped != nil })
        #expect(dropped == .other)
        // If it never shows, the next `signIn` would wait on the `.hold` itself, and nothing is held to release.
        try #require(await revokeShows(transport))
        #expect(await model.signIn(invite, deviceName: "iPhone") == nil)
        let next = try #require(model.account)
        let larder = try #require(model.larder)
        #expect(next.token == "next-token")

        await transport.release(status: 401, json: #"{"error":"unauthorized"}"#)

        try await Task.sleep(for: .milliseconds(50))
        #expect(model.account == next)
        #expect(Keychain.load() == next)
        #expect(model.larder === larder)
        #expect(try contents(directory).contains("snapshot.json"))
        #expect(model.signedOutLostChanges == nil)
        #expect(await transport.requests.count == 4)
        #expect(await sent(transport, token: "test-token") == ["POST lists.example.test/v1/signout"])
    }

    @Test @MainActor func signInIgnoresLeftoverFiles() async throws {
        defer { Keychain.delete() }
        let transport = FakeTransport([redeemed(), synced])
        let model = AppModel(transport: transport, dataDirectory: try seededDirectory())

        try #require(await model.signIn(invite, deviceName: "iPhone") == nil)

        let request = try #require(await transport.requests.last)
        let body = try JSON.decoder.decode(SyncBody.self, from: try #require(request.httpBody))
        #expect(body.ops.isEmpty)
        #expect(model.larder?.pending.isEmpty == true)
    }

    @Test @MainActor func relaunchRestoresAccount() async throws {
        defer { Keychain.delete() }
        let (model, transport, directory) = try await signedIn()

        let relaunched = AppModel(transport: transport, dataDirectory: directory)

        #expect(relaunched.account == model.account)
        #expect(relaunched.larder?.view != nil)
        #expect(relaunched.larder?.view == model.larder?.view)
        #expect(relaunched.memberName == "Alex")
        try await Task.sleep(for: .milliseconds(50))
        #expect(await transport.requests.count == 2)
    }

    @Test @MainActor func signOutOtherAnswers() async throws {
        defer { Keychain.delete() }

        // The server answered, so these changes are unsent, not stuck behind a lost connection.
        let invalid = try await signedIn([.answer(status: 400, json: #"{"error":"invalid"}"#)])
        try invalid.model.larder?.perform([tea()])
        #expect(await invalid.model.signOut(force: false) == .unsentChanges(1))
        #expect(invalid.model.account == account)
        #expect(Keychain.load() == account)
        #expect(invalid.model.larder?.pending.count == 1)
        #expect(LocalFiles(directory: invalid.directory).load().queue.count == 1)
        #expect(!(await paths(invalid.transport)).contains("/v1/signout"))

        let revoked = try await signedIn([unauthorized])
        try revoked.model.larder?.perform([tea()])
        #expect(await revoked.model.signOut(force: false) == .done)
        #expect(revoked.model.account == nil)
        #expect(Keychain.load() == nil)
        #expect(revoked.model.signedOutLostChanges == 1)
        #expect(!(await paths(revoked.transport)).contains("/v1/signout"))

        let failing = try await signedIn([synced, .answer(status: 500, json: #"{"error":"internal"}"#)])
        #expect(await failing.model.signOut(force: false) == .unreachable)
        #expect(failing.model.account == account)
        #expect(Keychain.load() == account)
        #expect(await failing.transport.requests.last?.url?.path == "/v1/signout")

        let gone = try await signedIn([synced, unauthorized])
        #expect(await gone.model.signOut(force: false) == .done)
        #expect(gone.model.account == nil)
        #expect(Keychain.load() == nil)
        #expect(try contents(gone.directory) == [])
        #expect(gone.model.signedOutLostChanges == nil)
    }

    @Test @MainActor func signOutRateLimited() async throws {
        defer { Keychain.delete() }
        let rateLimited = FakeTransport.Step.answer(status: 429, json: #"{"error":"rate_limited"}"#)

        // A 429 wins over the unsent change: its question already says that everything on this iPhone goes.
        let (model, transport, directory) = try await signedIn([rateLimited, signedOut])
        let op = tea()
        try model.larder?.perform([op])
        #expect(await model.signOut(force: false) == .rateLimited)
        #expect(model.account == account)
        #expect(Keychain.load() == account)
        #expect(model.larder?.pending.map(\.op) == [op])
        #expect(LocalFiles(directory: directory).load().queue.map(\.op) == [op])
        #expect(!(await paths(transport)).contains("/v1/signout"))

        #expect(await model.signOut(force: true) == .done)
        #expect(model.account == nil)
        #expect(model.larder == nil)
        #expect(Keychain.load() == nil)
        #expect(try contents(directory) == [])
        #expect(await revokeShows(transport))

        let refused = try await signedIn([synced, rateLimited])
        #expect(await refused.model.signOut(force: false) == .rateLimited)
        #expect(refused.model.account == account)
        #expect(Keychain.load() == account)
        #expect(await refused.transport.requests.last?.url?.path == "/v1/signout")
    }

    // A model built with an empty Keychain stands in for a locked launch, because `load()` returns nil in both cases
    // and a test can't lock the simulator. `Keychain.save` after `init` stands in for the phone unlocking.

    @Test @MainActor func activeRestoresLockedLaunch() async throws {
        defer { Keychain.delete() }
        let directory = try seededDirectory()
        let transport = FakeTransport([unauthorized])
        let model = AppModel(transport: transport, dataDirectory: directory)
        #expect(model.account == nil)
        #expect(model.larder == nil)
        #expect(try contents(directory).sorted() == ["queue.json", "snapshot.json"])

        try Keychain.save(account)
        model.restoreFromKeychain()

        #expect(model.account == account)
        #expect(model.memberName == "Alex")
        #expect(model.larder?.pending.count == 1)
        #expect(try contents(directory).sorted() == ["queue.json", "snapshot.json"])
        try await Task.sleep(for: .milliseconds(50))
        #expect(await transport.requests.isEmpty)

        await model.larder?.sync()
        #expect(model.account == nil)
        #expect(model.signedOutLostChanges == 1)

        model.restoreFromKeychain()
        #expect(model.account == nil)
        #expect(model.larder == nil)
    }

    @Test @MainActor func activeWhileSignedInChangesNothing() async throws {
        defer { Keychain.delete() }
        let (model, transport, _) = try await signedIn()
        let larder = try #require(model.larder)
        let other = Account(server: server, token: "other-token", memberId: member, deviceId: device)
        try Keychain.save(other)

        model.restoreFromKeychain()

        #expect(model.account == account)
        #expect(model.larder === larder)
        #expect(Keychain.load() == other)
        try await Task.sleep(for: .milliseconds(50))
        #expect(await transport.requests.count == 2)
    }

    @Test @MainActor func restoredAccountBeatsOpenRedeem() async throws {
        defer { Keychain.delete() }
        let directory = try seededDirectory()
        let transport = FakeTransport([.hold, signedOut, synced])
        let model = AppModel(transport: transport, dataDirectory: directory)
        // On another server than the restored account, so that the revoke shows which server it goes to.
        let dropped = Invite(server: try #require(URL(string: "https://other.example.test")), code: "code")
        let redeeming = Task { await model.signIn(dropped, deviceName: "iPhone") }
        try #require(await waitUntil { await transport.requests.count == 1 })

        try Keychain.save(account)
        model.restoreFromKeychain()
        let larder = model.larder

        await transport.release(status: 200, json: redeemJSON(token: "late-token"))

        #expect(await redeeming.value == .alreadySignedIn(name: "Alex"))
        #expect(model.account == account)
        #expect(Keychain.load() == account)
        #expect(model.larder === larder)
        #expect(model.larder?.pending.count == 1)
        #expect(try contents(directory).contains("queue.json"))
        #expect(await revokeShows(transport))
        try await Task.sleep(for: .milliseconds(50))
        #expect(await transport.requests.count == 2)
        #expect(await sent(transport, token: "late-token") == ["POST other.example.test/v1/signout"])
    }

    @Test @MainActor func emptyKeychainKeepsOpenRedeem() async throws {
        defer { Keychain.delete() }
        let transport = FakeTransport([.hold, synced])
        let model = AppModel(transport: transport, dataDirectory: try temporaryDirectory())
        let redeeming = try await openSignIn(model, transport)

        model.restoreFromKeychain()
        #expect(model.account == nil)

        await transport.release(status: 200, json: redeemJSON(token: "test-token"))

        #expect(await redeeming.value == nil)
        #expect(model.account == account)
        #expect(Keychain.load() == account)
        try await Task.sleep(for: .milliseconds(50))
        #expect(await transport.requests.count == 2)
    }

    @Test @MainActor func inviteLinkBeforeRestoreIsNotKept() throws {
        defer { Keychain.delete() }
        let model = AppModel(transport: FakeTransport([]), dataDirectory: try temporaryDirectory())
        model.open(try #require(URL(string: example)))
        #expect(model.pendingInvite != nil)

        try Keychain.save(account)
        model.restoreFromKeychain()

        #expect(model.pendingInvite == nil)
        // The host, because this directory has no snapshot.
        #expect(model.alreadySignedInAs == "lists.example.test")
    }

    @Test @MainActor func fixtureLeavesKeychainAndFilesAlone() async throws {
        defer { Keychain.delete() }
        try Keychain.save(account)
        let marker = AppModel.defaultDataDirectory.appending(path: newID())
        try Data().write(to: marker)
        defer { try? FileManager.default.removeItem(at: marker) }

        let model = AppModel.fixture()
        #expect(model.account?.server.absoluteString == "https://fixture.invalid")
        #expect(model.account?.memberId == member)

        #expect(await model.signOut(force: true) == .done)
        model.restoreFromKeychain()

        #expect(model.account == nil)
        #expect(Keychain.load() == account)
        #expect(FileManager.default.fileExists(atPath: marker.path))
    }

    @Test @MainActor func fixtureStartsFresh() async throws {
        let first = AppModel.fixture()
        let larder = try #require(first.larder)
        await larder.sync()
        let view = try #require(larder.view)
        let list = try #require(view.myList)
        try larder.perform([Op(.entryAdd, id: newID(), listId: list.id, text: "Only in the first")])
        await larder.sync()
        #expect(larder.pending.isEmpty)
        #expect(larder.view?.entries.contains { $0.text == "Only in the first" } == true)

        let second = AppModel.fixture()
        let other = try #require(second.larder)
        #expect(other.pending.isEmpty)
        await other.sync()
        #expect(other.view != nil)
        #expect(other.view?.entries.contains { $0.text == "Only in the first" } == false)
    }

    @Test @MainActor func scopeDrivesAddTarget() throws {
        let model = AppModel(transport: FakeTransport([]), dataDirectory: try temporaryDirectory())
        #expect(model.scope == .myView)
        #expect(model.addTarget == nil)

        model.scope = .list("shared")
        #expect(model.addTarget == "shared")

        model.scope = .myView
        #expect(model.addTarget == nil)

        model.addTarget = "picked"
        model.scope = .myView
        #expect(model.addTarget == "picked")
    }

    @Test @MainActor func scopeResetsAfterFiveMinutes() throws {
        let model = AppModel(transport: FakeTransport([]), dataDirectory: try temporaryDirectory())
        let left = Date(timeIntervalSince1970: 1_000_000)

        model.scope = .list("shared")
        model.didEnterBackground(now: left)
        model.didBecomeActive(now: left.addingTimeInterval(300))
        #expect(model.scope == .list("shared"))
        #expect(model.addTarget == "shared")

        model.didEnterBackground(now: left)
        model.didBecomeActive(now: left.addingTimeInterval(301))
        #expect(model.scope == .myView)
        #expect(model.addTarget == nil)

        model.addTarget = "picked"
        model.didEnterBackground(now: left)
        model.didBecomeActive(now: left.addingTimeInterval(300))
        #expect(model.addTarget == "picked")

        model.didEnterBackground(now: left)
        model.didBecomeActive(now: left.addingTimeInterval(301))
        #expect(model.scope == .myView)
        #expect(model.addTarget == nil)

        // Becoming active without having left changes nothing, however late it is.
        model.scope = .list("shared")
        model.didBecomeActive(now: left.addingTimeInterval(1000))
        #expect(model.scope == .list("shared"))
    }

    @Test @MainActor func wipeResetsScope() async throws {
        defer { Keychain.delete() }
        let (model, _, _) = try await signedIn([signedOut])
        model.scope = .list("shared")
        #expect(await model.signOut(force: true) == .done)
        #expect(model.scope == .myView)
        #expect(model.addTarget == nil)

        let (picked, _, _) = try await signedIn([signedOut])
        picked.addTarget = "picked"
        #expect(await picked.signOut(force: true) == .done)
        #expect(picked.addTarget == nil)
    }
}

/// A missing catalog key would otherwise show "1 changes" with no failure.
@Test func copyTexts() {
    #expect(signInErrorText(.invalidInvite) == "This invite can't be used. It may have expired or been used already. Ask for a new one.")
    #expect(signInErrorText(.rateLimited) == "Too many sign-in attempts on this server. Try again in a minute.")
    #expect(signInErrorText(.unreachable(host: "lists.example.test")) == "Can't reach lists.example.test.")
    #expect(signInErrorText(.alreadySignedIn(name: "Alex")) == "This iPhone is already signed in as Alex. Sign out first to use this invite.")
    #expect(signInErrorText(.other) == "Couldn't sign in. Try again, or ask for a new invite.")
    #expect(signedOutText(lostChanges: 0) == "This iPhone was signed out.")
    #expect(signedOutText(lostChanges: 1) == "This iPhone was signed out. 1 change that wasn't sent yet is lost.")
    #expect(signedOutText(lostChanges: 2) == "This iPhone was signed out. 2 changes that weren't sent yet are lost.")
    #expect(unsentChangesText(1) == "1 change hasn't been sent yet. Sign out and lose it?")
    #expect(unsentChangesText(2) == "2 changes haven't been sent yet. Sign out and lose them?")
    #expect(rateLimitedSignOutText(host: "lists.example.test") == "lists.example.test limited this iPhone's requests: too many in the past minute. Sign out anyway? This deletes everything on this iPhone. Ask an admin to remove this device from the household.")
}
