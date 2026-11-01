public enum Notice: Equatable, Sendable {
    case listHidden(ownerName: String, lostChanges: Bool)
    case listReadOnly(ownerName: String)
    case renameConflict(from: String, to: String)
}

/// What a sync's answer has to tell the user. `before` is the view the user saw: `listHidden` notices come in its
/// list order, then the others in `rejected` order, with at most one per list.
public func notices(before: Snapshot?, after: Snapshot, sent: [Op], rejected: [Rejection]) -> [Notice] {
    func listId(of op: Op) -> String? {
        op.listId ?? before?.entries.first { $0.id == op.id }?.listId
    }

    let rejectedOps = rejected.compactMap { rejection in
        sent.first { $0.opId == rejection.opId }.map { (reason: rejection.reason, op: $0) }
    }
    let forbiddenLists = rejectedOps.filter { $0.reason == "forbidden" }.compactMap { listId(of: $0.op) }

    var result: [Notice] = []
    for list in before?.lists ?? [] where list.ownerId != nil && list.ownerId != after.me.memberId && after.list(list.id) == nil {
        if let owner = after.member(list.ownerId), owner.privacy == .hidden {
            result.append(.listHidden(ownerName: owner.name, lostChanges: forbiddenLists.contains(list.id)))
        }
    }

    var readOnlyLists: Set<String> = []
    for (reason, op) in rejectedOps {
        switch reason {
        case "forbidden":
            guard let list = after.list(listId(of: op)), !list.writable, let owner = after.member(list.ownerId),
                readOnlyLists.insert(list.id).inserted
            else { continue }
            result.append(.listReadOnly(ownerName: owner.name))
        case "conflict":
            // `after` first: `before` already shows a rename the server refused because of a name it hadn't seen.
            guard op.type == .itemUpdate, let to = op.name, let from = after.item(op.id)?.name ?? before?.item(op.id)?.name else { continue }
            result.append(.renameConflict(from: from, to: to))
        default:
            continue
        }
    }
    return result
}
