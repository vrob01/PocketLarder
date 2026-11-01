import Foundation

/// The local copy on disk. The caller owns the directory: it is never created here, and `wipe()` leaves it.
public struct LocalFiles: Sendable {
    private let snapshotFile: URL
    private let queueFile: URL

    public init(directory: URL) {
        snapshotFile = directory.appending(path: "snapshot.json")
        queueFile = directory.appending(path: "queue.json")
    }

    /// An unreadable file counts as missing.
    public func load() -> (snapshot: Snapshot?, queue: [PendingOp]) {
        (read(snapshotFile), read(queueFile) ?? [])
    }

    public func save(snapshot: Snapshot) throws {
        try JSON.encoder.encode(snapshot).write(to: snapshotFile, options: .atomic)
    }

    public func save(queue: [PendingOp]) throws {
        try JSON.encoder.encode(queue).write(to: queueFile, options: .atomic)
    }

    public func wipe() {
        try? FileManager.default.removeItem(at: snapshotFile)
        try? FileManager.default.removeItem(at: queueFile)
    }

    private func read<Value: Decodable>(_ file: URL) -> Value? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSON.decoder.decode(Value.self, from: data)
    }
}
