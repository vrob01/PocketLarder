public struct Suggestion: Equatable, Sendable {
    public let item: Item
    public let store: Store?
    public let category: Category?
}

/// Items whose folded name starts with the query, then those that contain it, each group alphabetical.
public func suggestions(_ s: Snapshot, for query: String, limit: Int = 8) -> [Suggestion] {
    guard let cleaned = cleanText(query, max: Limit.name) else { return [] }
    let needle = fold(cleaned)
    let matches = s.items
        .filter { fold($0.name).contains(needle) }
        .sorted { (fold($0.name), $0.id) < (fold($1.name), $1.id) }
    let prefixed = matches.filter { fold($0.name).hasPrefix(needle) }
    let others = matches.filter { !fold($0.name).hasPrefix(needle) }
    return (prefixed + others).prefix(limit).map { item in
        Suggestion(
            item: item,
            store: s.store(item.defaultStoreId),
            category: s.category(s.placement(item: item.id, store: item.defaultStoreId)?.categoryId)
        )
    }
}

public enum AddOutcome: Equatable, Sendable {
    case add(Op), existing(Entry)
}

/// `.existing` when that item is already open on the list.
public func add(_ item: Item, to listId: String, in s: Snapshot) -> AddOutcome {
    if let open = s.entries.first(where: { $0.listId == listId && $0.itemId == item.id && $0.boughtAt == nil }) {
        return .existing(open)
    }
    return .add(Op(.entryAdd, id: newID(), listId: listId, itemId: item.id))
}

/// Nil when the text doesn't clean. A catalog item of that name is added as itself, anything else unfiled.
public func add(text: String, to listId: String, in s: Snapshot) -> AddOutcome? {
    guard let cleaned = cleanText(text, max: Limit.name) else { return nil }
    if let item = s.items.first(where: { nameKey($0.name) == nameKey(cleaned) }) {
        return add(item, to: listId, in: s)
    }
    return .add(Op(.entryAdd, id: newID(), listId: listId, text: cleaned))
}
