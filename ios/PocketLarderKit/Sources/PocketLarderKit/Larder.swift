import Foundation
import Observation

/// The offline engine: the local copy, the queue of ops the server hasn't acknowledged, and the sync that sends them.
@MainActor @Observable public final class Larder {
    public private(set) var snapshot: Snapshot?
    public private(set) var pending: [PendingOp]
    /// `snapshot` with `pending` applied.
    public private(set) var view: Snapshot?
    public private(set) var isOffline = false
    public private(set) var notices: [Notice] = []
    public var syncDelay: Duration = .seconds(1)
    public var onSignedOut: ((_ lostChanges: Int) -> Void)?

    private let files: LocalFiles
    private let client: APIClient?
    private var schedule: Task<Void, Never>?
    private var running: Task<Void, Never>?
    /// Set by a `sync()` during a request. Each round clears it, and an error ends the loop without looking at it.
    private var extraRound = false

    public init(files: LocalFiles, client: APIClient?) {
        self.files = files
        self.client = client
        let loaded = files.load()
        snapshot = loaded.snapshot
        pending = loaded.queue
        view = loaded.snapshot.map { applying(loaded.queue, to: $0) }
    }

    /// Queues `ops`. The queue is on disk before anything shows, and nothing changes if that fails.
    public func perform(_ ops: [Op], now: Date = .now) throws {
        // Whole seconds, because that is all `JSON.encoder` keeps: a `PendingOp` stays equal across a relaunch.
        let at = Date(timeIntervalSince1970: now.timeIntervalSince1970.rounded(.down))
        let queue = pending + ops.map { PendingOp(op: $0, at: at) }
        try files.save(queue: queue)
        pending = queue
        view = snapshot.map { applying(queue, to: $0) }
        guard client != nil else { return }
        schedule?.cancel()
        let delay = syncDelay
        schedule = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.sync()
        }
    }

    /// Returns when the state is settled: a call during a request asks for one more round and waits for the loop.
    public func sync() async {
        guard let client else { return }
        schedule?.cancel()
        schedule = nil
        if let running {
            extraRound = true
            await running.value
            return
        }
        // A task of its own, so that cancelling a caller or a schedule never reaches a request in flight.
        let loop = Task { await runRounds(client) }
        running = loop
        await loop.value
    }

    public func dismissNotice() {
        if !notices.isEmpty {
            notices.removeFirst()
        }
    }

    private func runRounds(_ client: APIClient) async {
        repeat {
            extraRound = false
            let sent = pending.prefix(500).map(\.op)
            do {
                receive(try await client.sync(sent), for: sent)
            } catch {
                fail(error)
                break
            }
        } while extraRound || !pending.isEmpty
        running = nil
    }

    private func receive(_ response: SyncResponse, for sent: [Op]) {
        let before = view
        let sentIds = Set(sent.map(\.opId))
        snapshot = response.snapshot
        pending.removeAll { sentIds.contains($0.op.opId) }
        // Snapshot first: a crash between the two re-sends ops the server skips, rather than showing a view without
        // them. A failed save changes nothing either: memory moves on, and a stale queue file only re-sends repeats.
        try? files.save(snapshot: response.snapshot)
        try? files.save(queue: pending)
        notices += PocketLarderKit.notices(before: before, after: response.snapshot, sent: sent, rejected: response.rejected)
        view = applying(pending, to: response.snapshot)
        isOffline = false
    }

    private func fail(_ error: APIError) {
        switch error {
        case .server(code: "unauthorized"):
            let lostChanges = pending.count
            files.wipe()
            snapshot = nil
            pending = []
            view = nil
            notices = []
            isOffline = false
            schedule?.cancel()
            schedule = nil
            onSignedOut?(lostChanges)
        case .offline, .server(code: "internal"), .unexpected(status: 500...599):
            isOffline = true
        default:
            // The server answered, so this isn't a lack of connection.
            isOffline = false
        }
    }
}
