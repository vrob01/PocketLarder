public enum MoveOutcome: Equatable, Sendable { case place(Op), needsCategory }

/// What moving the entry to a store takes: the op, or a category first when the item isn't placed there.
public func move(_ e: Entry, to storeId: String, category: String? = nil, in s: Snapshot) -> MoveOutcome {
    if e.itemId != nil {
        guard category != nil || s.placement(item: e.itemId, store: storeId) != nil else { return .needsCategory }
        return .place(Op(.entryPlace, id: e.id, storeId: storeId, categoryId: category))
    }
    guard let category else { return .needsCategory }
    return .place(Op(.entryPlace, id: e.id, storeId: storeId, categoryId: category, newItemId: newID()))
}
