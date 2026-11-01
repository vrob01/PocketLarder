import Foundation

public enum Privacy: String, Codable, Hashable, Sendable {
    case open, readonly, hidden
}

public enum ListColor: String, CaseIterable, Codable, Hashable, Sendable {
    case red, orange, yellow, green, teal, blue, purple, pink, gray
}

public struct Snapshot: Codable, Equatable, Sendable {
    public var me: Me
    public var members: [Member]
    public var lists: [ListInfo]
    public var stores: [Store]
    public var categories: [Category]
    public var items: [Item]
    public var placements: [Placement]
    public var entries: [Entry]
}

public struct Me: Codable, Equatable, Sendable {
    public var memberId, deviceId: String
    public var isAdmin: Bool
}

public struct Member: Codable, Hashable, Sendable {
    public var id, name: String
    public var isAdmin: Bool
    public var privacy: Privacy
}

public struct ListInfo: Codable, Hashable, Sendable {
    public var id: String
    public var ownerId: String?
    public var name: String?
    public var color: ListColor?
    public var archived, writable: Bool
}

public struct Store: Codable, Hashable, Sendable {
    public var id, name: String
    public var position: Int
}

public struct Category: Codable, Hashable, Sendable {
    public var id, storeId, name: String
    public var position: Int
}

public struct Item: Codable, Hashable, Sendable {
    public var id, name: String
    public var defaultStoreId: String?
}

public struct Placement: Codable, Hashable, Sendable {
    public var itemId, storeId, categoryId: String
}

public struct Entry: Codable, Hashable, Sendable {
    public var id, listId: String
    public var itemId: String?
    public var text, quantity, note: String
    public var storeId: String?
    public var createdAt: Date
    public var boughtAt: Date?
}

extension Snapshot {
    public func member(_ id: String?) -> Member? { members.first { $0.id == id } }
    public func list(_ id: String?) -> ListInfo? { lists.first { $0.id == id } }
    public func store(_ id: String?) -> Store? { stores.first { $0.id == id } }
    public func category(_ id: String?) -> Category? { categories.first { $0.id == id } }
    public func item(_ id: String?) -> Item? { items.first { $0.id == id } }

    public func placement(item: String?, store: String?) -> Placement? {
        placements.first { $0.itemId == item && $0.storeId == store }
    }

    public var myList: ListInfo? { lists.first { $0.ownerId == me.memberId } }
}

/// A fresh random lowercase UUID. The server skips a repeated `op_id` silently, so one is never reused.
public func newID() -> String {
    UUID().uuidString.lowercased()
}

public enum JSON {
    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
