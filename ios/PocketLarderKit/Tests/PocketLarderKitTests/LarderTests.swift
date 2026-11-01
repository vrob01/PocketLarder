import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import PocketLarderKit

private let at = TestData.date("2026-10-30T10:00:00Z")
private let offline = FakeTransport.Step.error(URLError(.notConnectedToInternet))
private let unauthorized = #"{"error":"unauthorized"}"#

private struct SyncAnswer: Encodable {
    var rejected: [Rejection]
    var snapshot: Snapshot
}

private func syncJSON(_ snapshot: Snapshot = TestData.household, rejected: [Rejection] = []) throws -> String {
    String(decoding: try JSON.encoder.encode(SyncAnswer(rejected: rejected, snapshot: snapshot)), as: UTF8.self)
}

private func synced(_ snapshot: Snapshot = TestData.household, rejected: [Rejection] = []) throws -> FakeTransport.Step {
    .answer(status: 200, json: try syncJSON(snapshot, rejected: rejected))
}

private func add(_ text: String) -> Op {
    Op(.entryAdd, id: newID(), listId: TestData.alexList, text: text)
}

/// A `Larder` on the household, in a directory of its own, with `syncDelay` `.zero`.
@MainActor private func makeLarder(
    _ script: [FakeTransport.Step]
) throws -> (larder: Larder, transport: FakeTransport, files: LocalFiles, directory: URL) {
    let (directory, files) = try TestData.temporaryFiles()
    try files.save(snapshot: TestData.household)
    let transport = FakeTransport(script)
    let client = APIClient(server: URL(string: "https://lists.example.test")!, token: "t", transport: transport)
    let larder = Larder(files: files, client: client)
    larder.syncDelay = .zero
    return (larder, transport, files, directory)
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

/// Long enough for a request that shouldn't happen to show up.
private func pause() async throws {
    try await Task.sleep(for: .milliseconds(50))
}

private struct SentBody: Decodable {
    let ops: [Op]
}

private func sentOpIds(_ request: URLRequest) throws -> [String] {
    try JSON.decoder.decode(SentBody.self, from: try #require(request.httpBody)).ops.map(\.opId)
}

@Test @MainActor func performPersistsBeforeShowing() async throws {
    let (_, files) = try TestData.temporaryFiles()
    try files.save(snapshot: TestData.household)
    let larder = Larder(files: files, client: nil)
    let op = add("Tea")

    try larder.perform([op], now: Date(timeIntervalSince1970: 1_800_000_000.75))

    let expected = [PendingOp(op: op, at: Date(timeIntervalSince1970: 1_800_000_000))]
    #expect(larder.pending == expected)
    #expect(files.load().queue == expected)
    #expect(larder.view?.entries.contains { $0.id == op.id } == true)
    #expect(larder.snapshot == TestData.household)

    // A nil client never sends, so the op stays queued.
    await larder.sync()
    #expect(larder.pending == expected)
}

@Test @MainActor func queueSurvivesRelaunch() async throws {
    let (larder, _, files, _) = try makeLarder([offline, offline])
    let op = add("Tea")

    try larder.perform([op])
    #expect(await waitUntil { larder.isOffline })

    let relaunched = Larder(files: files, client: nil)
    #expect(relaunched.pending == larder.pending)
    #expect(relaunched.pending.map(\.op) == [op])
    #expect(relaunched.snapshot == TestData.household)
    #expect(relaunched.view?.entries.contains { $0.id == op.id } == true)
}

@Test @MainActor func opsAddedDuringSyncSurvive() async throws {
    let a = add("A"), b = add("B")
    let pendingB = [PendingOp(op: b, at: at)]
    let afterA = applying([PendingOp(op: a, at: at)], to: TestData.household)
    let afterB = applying(pendingB, to: afterA)
    // The spare step: B's schedule can add a round, which must change nothing.
    let (larder, transport, files, _) = try makeLarder([.hold, .hold, try synced(afterB)])

    try larder.perform([a], now: at)
    let call = SyncCall(larder)
    try #require(await waitUntil { await transport.requests.count == 1 })

    try larder.perform([b], now: at)
    try await pause()
    #expect(await transport.requests.count == 1)

    await transport.release(status: 200, json: try syncJSON(afterA))
    try #require(await waitUntil { await transport.requests.count == 2 })

    #expect(larder.pending == pendingB)
    #expect(larder.snapshot == afterA)
    #expect(larder.view?.entries.contains { $0.id == a.id } == true)
    #expect(larder.view?.entries.contains { $0.id == b.id } == true)
    #expect(files.load().queue == pendingB)
    #expect(files.load().snapshot == afterA)
    let requests = await transport.requests
    #expect(try sentOpIds(requests[0]) == [a.opId])
    #expect(try sentOpIds(requests[1]) == [b.opId])

    await transport.release(status: 200, json: try syncJSON(afterB))
    try #require(await waitUntil { call.returned })
    #expect(larder.pending == [])
    #expect(larder.view == afterB)
    #expect(files.load().queue == [])
}

@Test @MainActor func failedSyncKeepsSameOps() async throws {
    let (larder, _, files, _) = try makeLarder([offline, try synced()])
    try larder.perform([add("A"), add("B")], now: at)
    let queued = larder.pending

    await larder.sync()
    #expect(larder.pending == queued)
    #expect(files.load().queue == queued)
    #expect(larder.isOffline)

    await larder.sync()
    #expect(!larder.isOffline)
    #expect(larder.pending == [])
    #expect(files.load().queue == [])
}

@Test @MainActor func longQueueSendsInOrderedBatches() async throws {
    let (larder, transport, files, _) = try makeLarder([.hold, .hold, try synced(), try synced()])
    let ops = (0..<1201).map { add("Item \($0)") }
    try larder.perform(ops)

    let call = SyncCall(larder)
    try #require(await waitUntil { await transport.requests.count == 1 })
    try await pause()
    #expect(await transport.requests.count == 1)

    await transport.release(status: 200, json: try syncJSON())
    try #require(await waitUntil { await transport.requests.count == 2 })
    try await pause()
    #expect(await transport.requests.count == 2)
    #expect(larder.pending.count == 701)

    await transport.release(status: 200, json: try syncJSON())
    try #require(await waitUntil { call.returned })

    let sent = try await transport.requests.map(sentOpIds)
    #expect(sent.map(\.count) == [500, 500, 201])
    #expect(sent.flatMap { $0 } == ops.map(\.opId))
    #expect(larder.pending == [])
    #expect(files.load().queue == [])
}

@Test @MainActor func unauthorizedSignsOut() async throws {
    let rename = Op(.itemUpdate, id: TestData.milk, name: "Bread")
    let (larder, transport, files, directory) = try makeLarder([
        try synced(rejected: [Rejection(opId: rename.opId, reason: "conflict")]),
        offline,
        .answer(status: 401, json: unauthorized),
        try synced(),
    ])
    var signedOut: [Int] = []
    larder.onSignedOut = { signedOut.append($0) }

    try larder.perform([rename])
    await larder.sync()
    #expect(larder.notices.count == 1)

    try larder.perform([add("A"), add("B"), add("C")])
    await larder.sync()
    #expect(larder.isOffline)

    await larder.sync()
    #expect(signedOut == [3])
    #expect(larder.snapshot == nil)
    #expect(larder.view == nil)
    #expect(larder.pending == [])
    #expect(larder.notices == [])
    #expect(!larder.isOffline)
    let loaded = files.load()
    #expect(loaded.snapshot == nil)
    #expect(loaded.queue == [])
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [])
    #expect(FileManager.default.fileExists(atPath: directory.path))
    #expect(await transport.requests.count == 3)
}

@Test @MainActor func onlyARealUnauthorizedWipes() async throws {
    let cases: [(step: FakeTransport.Step, isOffline: Bool)] = [
        (.answer(status: 403, json: unauthorized), false),
        (.answer(status: 500, json: unauthorized), true),
        (.answer(status: 401, json: #"{"error":"missing_token"}"#), true),
    ]
    for (step, isOffline) in cases {
        let (larder, transport, files, _) = try makeLarder([step])
        var signedOut = false
        larder.onSignedOut = { _ in signedOut = true }
        try larder.perform([add("A"), add("B")], now: at)
        let queued = larder.pending
        let view = larder.view

        await larder.sync()

        #expect(larder.isOffline == isOffline)
        #expect(!signedOut)
        #expect(larder.pending == queued)
        #expect(larder.snapshot == TestData.household)
        #expect(larder.view == view)
        let loaded = files.load()
        #expect(loaded.snapshot == TestData.household)
        #expect(loaded.queue == queued)
        #expect(await transport.requests.count == 1)
    }
}

@Test @MainActor func serverErrorKeepsQueue() async throws {
    let cases: [FakeTransport.Step] = [
        .answer(status: 500, json: #"{"error":"internal"}"#),
        .answer(status: 503, json: "Service Unavailable"),
    ]
    for step in cases {
        let (larder, _, files, _) = try makeLarder([step])
        try larder.perform([add("A")], now: at)
        let queued = larder.pending

        await larder.sync()

        #expect(larder.pending == queued)
        #expect(files.load().queue == queued)
        #expect(larder.isOffline)
    }
}

@Test @MainActor func performThrowsWhenQueueCantBeSaved() async throws {
    let (larder, transport, _, directory) = try makeLarder([try synced()])
    let view = larder.view
    try FileManager.default.removeItem(at: directory)

    #expect(throws: (any Error).self) {
        try larder.perform([add("A")])
    }

    #expect(larder.pending == [])
    #expect(larder.view == view)
    try await pause()
    #expect(await transport.requests.isEmpty)

    // A failed save after a 200 is ignored: memory moves on.
    await larder.sync()
    #expect(!larder.isOffline)
    #expect(larder.snapshot == TestData.household)
    #expect(await transport.requests.count == 1)
}

@Test @MainActor func unreadableFilesCountAsMissing() throws {
    let (directory, files) = try TestData.temporaryFiles()
    try Data("garbage".utf8).write(to: directory.appending(path: "snapshot.json"))
    try Data("garbage".utf8).write(to: directory.appending(path: "queue.json"))

    let garbage = files.load()
    #expect(garbage.snapshot == nil)
    #expect(garbage.queue == [])
    let larder = Larder(files: files, client: nil)
    #expect(larder.snapshot == nil)
    #expect(larder.view == nil)
    #expect(larder.pending == [])

    let queue = [PendingOp(op: add("A"), at: at), PendingOp(op: Op(.storeReorder, ids: [TestData.market]), at: at)]
    try files.save(snapshot: TestData.household)
    try files.save(queue: queue)
    let loaded = files.load()
    #expect(loaded.snapshot == TestData.household)
    #expect(loaded.queue == queue)
}

@Test @MainActor func syncDuringRequestRunsOnceMore() async throws {
    let (larder, transport, _, _) = try makeLarder([.hold, .hold, try synced()])

    let first = SyncCall(larder)
    try #require(await waitUntil { await transport.requests.count == 1 })
    let second = SyncCall(larder)
    let third = SyncCall(larder)
    #expect(await transport.requests.count == 1)

    await transport.release(status: 200, json: try syncJSON())
    try #require(await waitUntil { await transport.requests.count == 2 })
    try await pause()
    #expect(!first.returned)
    #expect(!second.returned)
    #expect(!third.returned)

    await transport.release(status: 200, json: try syncJSON())
    try #require(await waitUntil { first.returned && second.returned && third.returned })
    try await pause()
    #expect(await transport.requests.count == 2)
}

@Test @MainActor func otherErrorsKeepQueueWithoutOffline() async throws {
    let cases: [FakeTransport.Step] = [
        .answer(status: 400, json: #"{"error":"invalid"}"#),
        .answer(status: 413, json: #"{"error":"too_large"}"#),
        .answer(status: 404, json: "404 page not found\n"),
        .answer(status: 401, json: "Unauthorized"),
        .answer(status: 301, json: ""),
        .answer(status: 200, json: "not the snapshot"),
    ]
    for step in cases {
        let (larder, _, files, _) = try makeLarder([offline, step])
        var signedOut = false
        larder.onSignedOut = { _ in signedOut = true }
        try larder.perform([add("A"), add("B")], now: at)
        let queued = larder.pending

        await larder.sync()
        #expect(larder.isOffline)

        await larder.sync()
        #expect(!larder.isOffline)
        #expect(larder.pending == queued)
        #expect(files.load().queue == queued)
        #expect(files.load().snapshot == TestData.household)
        #expect(!signedOut)
    }
}

@Test @MainActor func signOutHappensOnce() async throws {
    let (larder, transport, _, _) = try makeLarder([.hold, try synced()])
    var signedOut: [Int] = []
    larder.onSignedOut = { signedOut.append($0) }

    try larder.perform([add("A")])
    let first = SyncCall(larder)
    try #require(await waitUntil { await transport.requests.count == 1 })

    try larder.perform([add("B")])
    let second = SyncCall(larder)

    await transport.release(status: 401, json: unauthorized)
    try #require(await waitUntil { first.returned && second.returned })
    try await pause()

    #expect(await transport.requests.count == 1)
    #expect(signedOut == [2])
    #expect(larder.pending == [])

    // A schedule still waiting when the 401 arrives is dropped too.
    let (waiting, waitingTransport, _, _) = try makeLarder([.hold, try synced()])
    waiting.syncDelay = .milliseconds(100)
    let held = SyncCall(waiting)
    try #require(await waitUntil { await waitingTransport.requests.count == 1 })
    try waiting.perform([add("A")])
    await waitingTransport.release(status: 401, json: unauthorized)
    try #require(await waitUntil { held.returned })
    try await Task.sleep(for: .milliseconds(200))
    #expect(await waitingTransport.requests.count == 1)
}

@Test @MainActor func dismissNoticeOnEmptyIsSafe() async throws {
    let rename = Op(.itemUpdate, id: TestData.milk, name: "Oat milk")
    let (larder, _, _, _) = try makeLarder([try synced(rejected: [Rejection(opId: rename.opId, reason: "conflict")])])
    try larder.perform([rename])

    await larder.sync()
    #expect(larder.notices == [.renameConflict(from: "Milk", to: "Oat milk")])

    larder.dismissNotice()
    larder.dismissNotice()
    #expect(larder.notices == [])
}

@Test @MainActor func closeDropsAnswerInFlight() async throws {
    let (larder, transport, files, directory) = try makeLarder([.hold, try synced()])
    try larder.perform([add("A")])
    let call = SyncCall(larder)
    try #require(await waitUntil { await transport.requests.count == 1 })

    larder.close()
    files.wipe()
    await transport.release(status: 200, json: try syncJSON())
    try #require(await waitUntil { call.returned })
    try await pause()

    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [])
    #expect(await transport.requests.count == 1)
    #expect(larder.pending.count == 1)
}

@Test @MainActor func closeDropsUnauthorizedInFlight() async throws {
    let (larder, transport, files, _) = try makeLarder([.hold])
    var signedOut = false
    larder.onSignedOut = { _ in signedOut = true }
    try larder.perform([add("A")], now: at)
    let queued = larder.pending
    let call = SyncCall(larder)
    try #require(await waitUntil { await transport.requests.count == 1 })

    larder.close()
    await transport.release(status: 401, json: unauthorized)
    try #require(await waitUntil { call.returned })

    #expect(!signedOut)
    #expect(files.load().queue == queued)
    #expect(files.load().snapshot == TestData.household)
    #expect(larder.pending == queued)
}

@Test @MainActor func closedLarderDoesNothing() async throws {
    let (larder, transport, files, directory) = try makeLarder([try synced()])
    try larder.perform([add("A")])
    let queued = larder.pending

    larder.close()
    larder.close()
    try await pause()
    #expect(await transport.requests.isEmpty)

    await larder.sync()
    #expect(await transport.requests.isEmpty)

    files.wipe()
    try larder.perform([add("B")])
    try await pause()
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [])
    #expect(larder.pending == queued)
    #expect(await transport.requests.isEmpty)
}

@Test @MainActor func closeBeforeFirstRoundSendsNothing() async throws {
    let (larder, transport, _, _) = try makeLarder([try synced()])

    let call = SyncCall(larder)
    larder.close()
    try #require(await waitUntil { call.returned })

    #expect(await transport.requests.isEmpty)
}
