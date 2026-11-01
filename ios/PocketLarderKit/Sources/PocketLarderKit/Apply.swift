import Foundation

/// A queued op and when it was made, so that re-applying it over each snapshot gives stable times.
public struct PendingOp: Codable, Equatable, Sendable {
    public let op: Op
    public let at: Date

    public init(op: Op, at: Date) {
        self.op = op
        self.at = at
    }
}

public func applying(_ pending: [PendingOp], to s: Snapshot) -> Snapshot {
    var result = s
    for p in pending {
        apply(p, to: &result)
    }
    return result
}

/// Does locally what `server/API.md` says the server does. Each case checks everything before its first change,
/// so an op the server would reject changes nothing.
public func apply(_ p: PendingOp, to s: inout Snapshot) {
    let op = p.op
    guard validID(op.opId) else { return }
    switch op.type {
    case .entryAdd:
        guard let id = op.id, let listId = op.listId, s.list(listId)?.writable == true, validID(id),
            !s.entries.contains(where: { $0.id == id }),
            let quantity = cleanOptional(op.quantity, max: Limit.quantity),
            let note = cleanOptional(op.note, max: Limit.note)
        else { return }
        let itemId = op.itemId == "" ? nil : op.itemId
        let storeId = op.storeId == "" ? nil : op.storeId
        let text: String
        let entryStore: String?
        if let itemId {
            guard let item = s.item(itemId), storeId == nil || s.store(storeId) != nil else { return }
            text = item.name
            entryStore = storeId ?? item.defaultStoreId
        } else {
            guard storeId == nil, let cleaned = cleanName(op.text) else { return }
            text = cleaned
            entryStore = nil
        }
        s.entries.append(Entry(
            id: id, listId: listId, itemId: itemId, text: text, quantity: quantity, note: note,
            storeId: entryStore, createdAt: p.at, boughtAt: nil
        ))

    case .entryUpdate:
        guard let index = writableEntry(op.id, in: s), op.quantity != nil || op.note != nil,
            let quantity = cleanOptional(op.quantity, max: Limit.quantity, current: s.entries[index].quantity),
            let note = cleanOptional(op.note, max: Limit.note, current: s.entries[index].note)
        else { return }
        s.entries[index].quantity = quantity
        s.entries[index].note = note

    case .entryBuy:
        guard let index = writableEntry(op.id, in: s) else { return }
        s.entries[index].boughtAt = s.entries[index].boughtAt ?? p.at

    case .entryUnbuy:
        guard let index = writableEntry(op.id, in: s) else { return }
        s.entries[index].boughtAt = nil

    case .entryDelete:
        guard let index = writableEntry(op.id, in: s) else { return }
        s.entries.remove(at: index)

    case .entryPlace:
        guard let index = writableEntry(op.id, in: s), let storeId = op.storeId, s.store(storeId) != nil else { return }
        let categoryId = op.categoryId == "" ? nil : op.categoryId
        if let categoryId, s.category(categoryId)?.storeId != storeId { return }
        let itemId: String
        if let filed = s.entries[index].itemId {
            itemId = filed
        } else {
            guard categoryId != nil, let newItemId = op.newItemId, validID(newItemId) else { return }
            let text = s.entries[index].text
            if let match = s.items.first(where: { nameKey($0.name) == nameKey(text) }) {
                itemId = match.id
            } else {
                guard s.item(newItemId) == nil else { return }
                s.items.append(Item(id: newItemId, name: text, defaultStoreId: storeId))
                itemId = newItemId
            }
        }
        s.entries[index].itemId = itemId
        s.entries[index].storeId = storeId
        if let categoryId {
            place(item: itemId, store: storeId, category: categoryId, in: &s)
        }
        if let item = s.items.firstIndex(where: { $0.id == itemId }), s.items[item].defaultStoreId == nil {
            s.items[item].defaultStoreId = storeId
        }

    case .memberSetPrivacy:
        guard let privacy = op.privacy, let index = s.members.firstIndex(where: { $0.id == s.me.memberId }) else { return }
        s.members[index].privacy = privacy

    case .listCreate:
        guard let id = op.id, validID(id), s.list(id) == nil, let name = cleanName(op.name), let color = op.color else { return }
        s.lists.append(ListInfo(id: id, ownerId: nil, name: name, color: color, archived: false, writable: true))

    case .listUpdate:
        let name = cleanName(op.name)
        guard let index = s.lists.firstIndex(where: { $0.id == op.id }), s.lists[index].ownerId == nil,
            op.name != nil || op.color != nil || op.archived != nil, op.name == nil || name != nil
        else { return }
        s.lists[index].name = name ?? s.lists[index].name
        s.lists[index].color = op.color ?? s.lists[index].color
        s.lists[index].archived = op.archived ?? s.lists[index].archived

    case .storeCreate:
        guard let id = op.id, validID(id), s.store(id) == nil, let name = cleanName(op.name) else { return }
        s.stores.append(Store(id: id, name: name, position: nextPosition(s.stores.map(\.position))))
        sortCatalog(&s)

    case .storeRename:
        guard let index = s.stores.firstIndex(where: { $0.id == op.id }), let name = cleanName(op.name) else { return }
        s.stores[index].name = name

    case .storeDelete:
        guard let id = op.id, s.store(id) != nil else { return }
        s.stores.removeAll { $0.id == id }
        s.categories.removeAll { $0.storeId == id }
        s.placements.removeAll { $0.storeId == id }
        for index in s.items.indices where s.items[index].defaultStoreId == id {
            s.items[index].defaultStoreId = nil
        }
        for index in s.entries.indices where s.entries[index].storeId == id {
            s.entries[index].storeId = nil
        }

    case .storeReorder:
        sortCatalog(&s)
        for (position, id) in reordered(s.stores.map(\.id), listed: op.ids).enumerated() {
            if let index = s.stores.firstIndex(where: { $0.id == id }) {
                s.stores[index].position = position
            }
        }
        sortCatalog(&s)

    case .categoryCreate:
        guard let id = op.id, validID(id), s.category(id) == nil, let storeId = op.storeId, s.store(storeId) != nil,
            let name = cleanName(op.name)
        else { return }
        let position = nextPosition(s.categories.filter { $0.storeId == storeId }.map(\.position))
        s.categories.append(Category(id: id, storeId: storeId, name: name, position: position))
        sortCatalog(&s)

    case .categoryRename:
        guard let index = s.categories.firstIndex(where: { $0.id == op.id }), let name = cleanName(op.name) else { return }
        s.categories[index].name = name

    case .categoryDelete:
        guard let id = op.id, s.category(id) != nil else { return }
        s.categories.removeAll { $0.id == id }
        s.placements.removeAll { $0.categoryId == id }

    case .categoryReorder:
        guard let storeId = op.storeId, s.store(storeId) != nil else { return }
        sortCatalog(&s)
        let current = s.categories.filter { $0.storeId == storeId }.map(\.id)
        for (position, id) in reordered(current, listed: op.ids).enumerated() {
            if let index = s.categories.firstIndex(where: { $0.id == id }) {
                s.categories[index].position = position
            }
        }
        sortCatalog(&s)

    case .itemUpdate:
        let name = cleanName(op.name)
        guard let index = s.items.firstIndex(where: { $0.id == op.id }), op.name != nil || op.defaultStoreId != nil,
            op.name == nil || name != nil
        else { return }
        if let name, s.items.contains(where: { $0.id != op.id && nameKey($0.name) == nameKey(name) }) { return }
        if let store = op.defaultStoreId, store != "", s.store(store) == nil { return }
        s.items[index].name = name ?? s.items[index].name
        if let store = op.defaultStoreId {
            s.items[index].defaultStoreId = store == "" ? nil : store
        }

    case .itemPlace:
        guard let id = op.id, s.item(id) != nil, let storeId = op.storeId, s.store(storeId) != nil,
            let categoryId = op.categoryId, s.category(categoryId)?.storeId == storeId
        else { return }
        place(item: id, store: storeId, category: categoryId, in: &s)

    case .itemDelete:
        guard let id = op.id, s.item(id) != nil else { return }
        s.items.removeAll { $0.id == id }
        s.placements.removeAll { $0.itemId == id }
        for index in s.entries.indices where s.entries[index].itemId == id {
            s.entries[index].itemId = nil
        }
    }
}

/// Mirrors `validID` in `ids.go`: the shape only, not the version or variant.
private func validID(_ id: String) -> Bool {
    let bytes = Array(id.utf8)
    return bytes.count == 36 && bytes.enumerated().allSatisfy { index, byte in
        switch index {
        case 8, 13, 18, 23: byte == UInt8(ascii: "-")
        default: (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(byte)
        }
    }
}

/// The entry's index, if it exists and its list may be changed.
private func writableEntry(_ id: String?, in s: Snapshot) -> Int? {
    guard let index = s.entries.firstIndex(where: { $0.id == id }), s.list(s.entries[index].listId)?.writable == true else {
        return nil
    }
    return index
}

private func cleanName(_ name: String?) -> String? {
    name.flatMap { cleanText($0, max: Limit.name) }
}

/// The quantity or note to store: absent keeps `current` and `""` clears it. Nil when the value fails cleaning.
private func cleanOptional(_ value: String?, max: Int, current: String = "") -> String? {
    guard let value else { return current }
    return value == "" ? "" : cleanText(value, max: max)
}

private func nextPosition(_ positions: [Int]) -> Int {
    (positions.max() ?? -1) + 1
}

/// The order `API.md` promises for a snapshot.
private func sortCatalog(_ s: inout Snapshot) {
    s.stores.sort { ($0.position, $0.id) < ($1.position, $1.id) }
    s.categories.sort { ($0.position, $0.id) < ($1.position, $1.id) }
}

/// The listed ids that are in `current`, each where it first appears, then the rest in their order.
private func reordered(_ current: [String], listed: [String]?) -> [String] {
    var order: [String] = []
    for id in (listed ?? []) + current where current.contains(id) && !order.contains(id) {
        order.append(id)
    }
    return order
}

/// Makes `category` the item's placement in `store`, replacing the one it had there.
private func place(item: String, store: String, category: String, in s: inout Snapshot) {
    s.placements.removeAll { $0.itemId == item && $0.storeId == store }
    s.placements.append(Placement(itemId: item, storeId: store, categoryId: category))
}
