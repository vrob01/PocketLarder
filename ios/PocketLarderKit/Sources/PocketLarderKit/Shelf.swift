import Foundation

public enum Scope: Hashable, Sendable {
    case myView, list(String)
}

public enum StoreFilter: Hashable, Sendable {
    case all, store(String)
}

public struct CategoryGroup: Equatable, Sendable {
    public let category: Category
    public let entries: [Entry]
}

public struct StoreSection: Equatable, Sendable {
    public let store: Store
    public let groups: [CategoryGroup]
}

/// What the main screen shows for one scope and filter.
public struct Shelf: Equatable, Sendable {
    public let notFiled: [Entry]
    public let stores: [StoreSection]
    public let recentlyBought: [Entry]
}

extension Entry: Identifiable {}

/// My view is my list plus every non-archived shared list.
public func inScope(_ listId: String, _ scope: Scope, in s: Snapshot) -> Bool {
    switch scope {
    case let .list(id):
        return listId == id
    case .myView:
        guard let list = s.list(listId) else { return false }
        return list.ownerId == s.me.memberId || (list.ownerId == nil && !list.archived)
    }
}

public func shelf(_ s: Snapshot, scope: Scope, filter: StoreFilter) -> Shelf {
    let entries = s.entries.filter { inScope($0.listId, scope, in: s) }
    let open = entries.filter { $0.boughtAt == nil }

    var chosen: String?
    if case let .store(id) = filter { chosen = id }

    let notFiled = open
        .filter { !isFiled($0, in: s) && (chosen == nil || $0.storeId == nil || $0.storeId == chosen) }
        .sorted(by: walkingOrder)

    let filed = open.filter { isFiled($0, in: s) }
    let stores = byPosition(s.stores).filter { chosen == nil || $0.id == chosen }.compactMap { store -> StoreSection? in
        let categories = s.categories.filter { $0.storeId == store.id }
        let groups = categories.sorted { ($0.position, $0.id) < ($1.position, $1.id) }.compactMap { category -> CategoryGroup? in
            let here = filed.filter { $0.storeId == store.id && s.placement(item: $0.itemId, store: store.id)?.categoryId == category.id }
            return here.isEmpty ? nil : CategoryGroup(category: category, entries: here.sorted(by: walkingOrder))
        }
        return groups.isEmpty ? nil : StoreSection(store: store, groups: groups)
    }

    let recentlyBought = entries
        .filter { $0.boughtAt != nil && (chosen == nil || $0.storeId == chosen) }
        .sorted { $0.boughtAt == $1.boughtAt ? $0.id < $1.id : $0.boughtAt! > $1.boughtAt! }

    return Shelf(notFiled: notFiled, stores: stores, recentlyBought: recentlyBought)
}

/// It has an item, a store, and a placement for that pair. A missing item or store matches no placement.
public func isFiled(_ e: Entry, in s: Snapshot) -> Bool {
    s.placement(item: e.itemId, store: e.storeId) != nil
}

/// The entry's list when it's shared, otherwise nil.
public func tag(for e: Entry, in s: Snapshot) -> ListInfo? {
    s.list(e.listId).flatMap { $0.ownerId == nil ? $0 : nil }
}

/// Non-archived shared lists by name, then other members' personal lists by owner name.
public func switcherLists(_ s: Snapshot) -> [ListInfo] {
    func ownerName(_ list: ListInfo) -> String { fold(s.member(list.ownerId)?.name ?? "") }

    let lists = s.lists.filter { !$0.archived }
    let shared = lists.filter { $0.ownerId == nil }
        .sorted { (fold($0.name ?? ""), $0.id) < (fold($1.name ?? ""), $1.id) }
    let personal = lists.filter { $0.ownerId != nil && $0.ownerId != s.me.memberId }
        .sorted { (ownerName($0), $0.id) < (ownerName($1), $1.id) }
    return shared + personal
}

/// My list, then writable non-archived shared lists, then writable other personal lists.
public func addTargets(_ s: Snapshot) -> [ListInfo] {
    [s.myList].compactMap { $0 } + switcherLists(s).filter(\.writable)
}

/// `.myView` when the list is missing or archived.
public func validScope(_ scope: Scope, in s: Snapshot) -> Scope {
    guard case let .list(id) = scope, let list = s.list(id), !list.archived else { return .myView }
    return scope
}

/// The stores with at least one entry in scope, open or bought, filed or not, by position.
public func chipStores(_ s: Snapshot, scope: Scope) -> [Store] {
    let used = Set(s.entries.filter { inScope($0.listId, scope, in: s) }.compactMap(\.storeId))
    return byPosition(s.stores).filter { used.contains($0.id) }
}

/// The list `target` names when it is in `addTargets`, otherwise my list.
public func validTarget(_ target: String?, in s: Snapshot) -> ListInfo? {
    addTargets(s).first { $0.id == target } ?? s.myList
}

private func byPosition(_ stores: [Store]) -> [Store] {
    stores.sorted { ($0.position, $0.id) < ($1.position, $1.id) }
}

private func walkingOrder(_ a: Entry, _ b: Entry) -> Bool {
    (fold(a.text), a.id) < (fold(b.text), b.id)
}
