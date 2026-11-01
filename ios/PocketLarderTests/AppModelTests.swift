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

private func redeemed(token: String = "test-token") -> FakeTransport.Step {
    .answer(status: 200, json: #"{"token":"\#(token)","member_id":"\#(member)","device_id":"\#(device)"}"#)
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

private struct RedeemBody: Decodable {
    let code, deviceName: String
}

private struct SyncBody: Decodable {
    let ops: [Op]
}

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
        let body = try JSON.decoder.decode(RedeemBody.self, from: try #require(requests[0].httpBody))
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
        let (model, transport, directory) = try await signedIn([offline])
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
        let (model, transport, directory) = try await signedIn([.hold])
        let call = SyncCall(try #require(model.larder))
        try #require(await waitUntil { await transport.requests.count == 3 })

        #expect(await model.signOut(force: true) == .done)
        #expect(!call.returned)

        await transport.release(status: 200, json: syncJSON)
        try #require(await waitUntil { call.returned })
        #expect(try contents(directory) == [])
        #expect(model.account == nil)
        #expect(await transport.requests.count == 3)
    }

    @Test @MainActor func lateUnauthorizedSparesNextAccount() async throws {
        defer { Keychain.delete() }
        let (model, transport, directory) = try await signedIn([.hold, redeemed(token: "next-token"), synced])
        let call = SyncCall(try #require(model.larder))
        try #require(await waitUntil { await transport.requests.count == 3 })

        #expect(await model.signOut(force: true) == .done)
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

    @Test @MainActor func signInIgnoresLeftoverFiles() async throws {
        defer { Keychain.delete() }
        let directory = try temporaryDirectory()
        let files = LocalFiles(directory: directory)
        try files.save(snapshot: try JSON.decoder.decode(SyncResponse.self, from: Data(syncJSON.utf8)).snapshot)
        try files.save(queue: [PendingOp(op: tea(), at: .now)])
        let transport = FakeTransport([redeemed(), synced])
        let model = AppModel(transport: transport, dataDirectory: directory)

        #expect(await model.signIn(invite, deviceName: "iPhone") == nil)

        let requests = await transport.requests
        let body = try JSON.decoder.decode(SyncBody.self, from: try #require(requests[1].httpBody))
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
}
