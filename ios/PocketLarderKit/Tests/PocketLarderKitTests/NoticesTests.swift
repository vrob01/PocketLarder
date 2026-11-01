import Testing
@testable import PocketLarderKit

/// `household` as a member sees it once Sam has set `privacy`: `hidden` takes the list and its entries away.
private func afterSam(_ privacy: Privacy) -> Snapshot {
    var s = TestData.household
    s.members[s.members.firstIndex { $0.id == TestData.sam }!].privacy = privacy
    if privacy == .hidden {
        s.lists.removeAll { $0.id == TestData.samList }
        s.entries.removeAll { $0.listId == TestData.samList }
    } else {
        s.lists[s.lists.firstIndex { $0.id == TestData.samList }!].writable = privacy == .open
    }
    return s
}

@Test func hiddenListNotice() {
    let add = Op(.entryAdd, id: newID(), listId: TestData.samList, text: "Tea")
    let forbidden = Rejection(opId: add.opId, reason: "forbidden")
    let hidden = afterSam(.hidden)

    #expect(notices(before: TestData.household, after: hidden, sent: [add], rejected: [forbidden]) == [.listHidden(ownerName: "Sam", lostChanges: true)])
    #expect(notices(before: TestData.household, after: hidden, sent: [], rejected: []) == [.listHidden(ownerName: "Sam", lostChanges: false)])

    // An entry op finds its list through `before`, because the entry is gone from `after`.
    let buy = Op(.entryBuy, id: TestData.entrySamOatMilk)
    #expect(notices(before: TestData.household, after: hidden, sent: [buy], rejected: [Rejection(opId: buy.opId, reason: "forbidden")]) == [.listHidden(ownerName: "Sam", lostChanges: true)])

    // Hidden lists come first, in `before.lists` order, then the others in `rejected` order.
    let rename = Op(.itemUpdate, id: TestData.milk, name: "Oat milk")
    #expect(
        notices(before: TestData.household, after: hidden, sent: [rename], rejected: [Rejection(opId: rename.opId, reason: "conflict")])
            == [.listHidden(ownerName: "Sam", lostChanges: false), .renameConflict(from: "Milk", to: "Oat milk")]
    )

    #expect(notices(before: nil, after: hidden, sent: [add], rejected: [forbidden]) == [])
}

@Test func readOnlyNotice() {
    let add = Op(.entryAdd, id: newID(), listId: TestData.samList, text: "Tea")
    let forbidden = Rejection(opId: add.opId, reason: "forbidden")
    let readOnly = afterSam(.readonly)

    #expect(notices(before: TestData.household, after: readOnly, sent: [add], rejected: [forbidden]) == [.listReadOnly(ownerName: "Sam")])
    #expect(notices(before: nil, after: readOnly, sent: [add], rejected: [forbidden]) == [.listReadOnly(ownerName: "Sam")])

    let buy = Op(.entryBuy, id: TestData.entrySamOatMilk)
    let buyForbidden = Rejection(opId: buy.opId, reason: "forbidden")
    #expect(notices(before: TestData.household, after: readOnly, sent: [buy], rejected: [buyForbidden]) == [.listReadOnly(ownerName: "Sam")])
    #expect(notices(before: TestData.household, after: readOnly, sent: [add, buy], rejected: [forbidden, buyForbidden]) == [.listReadOnly(ownerName: "Sam")])
}

@Test func renameConflictNotice() {
    let rename = Op(.itemUpdate, id: TestData.milk, name: "Bread")
    let conflict = Rejection(opId: rename.opId, reason: "conflict")
    let expected = [Notice.renameConflict(from: "Milk", to: "Bread")]

    #expect(notices(before: TestData.household, after: TestData.household, sent: [rename], rejected: [conflict]) == expected)
    #expect(notices(before: nil, after: TestData.household, sent: [rename], rejected: [conflict]) == expected)

    // `before` is the view with the op applied, so it can already show the rename.
    let renamed = applying([PendingOp(op: rename, at: TestData.createdAt)], to: TestData.household)
    #expect(renamed.item(TestData.milk)?.name == "Bread")
    #expect(notices(before: renamed, after: TestData.household, sent: [rename], rejected: [conflict]) == expected)

    // An item that another member deleted is only in `before`.
    var noMilk = TestData.household
    noMilk.items.removeAll { $0.id == TestData.milk }
    #expect(notices(before: TestData.household, after: noMilk, sent: [rename], rejected: [conflict]) == expected)
    #expect(notices(before: nil, after: noMilk, sent: [rename], rejected: [conflict]) == [])
}

@Test func quietCases() {
    let household = TestData.household
    let add = Op(.entryAdd, id: newID(), listId: TestData.samList, text: "Tea")

    #expect(notices(before: household, after: household, sent: [add], rejected: [Rejection(opId: add.opId, reason: "not_found")]) == [])
    #expect(notices(before: household, after: household, sent: [add], rejected: [Rejection(opId: add.opId, reason: "invalid")]) == [])

    // Sam was removed, rather than hiding the list.
    var noSam = afterSam(.hidden)
    noSam.members.removeAll { $0.id == TestData.sam }
    #expect(notices(before: household, after: noSam, sent: [], rejected: []) == [])

    // Gone while its owner's privacy is still open, and my own list or a shared list gone: no owner hid them.
    var noList = household
    noList.lists.removeAll { [TestData.samList, TestData.alexList, TestData.sharedList].contains($0.id) }
    #expect(notices(before: household, after: noList, sent: [], rejected: []) == [])
    noList.members[noList.members.firstIndex { $0.id == TestData.alex }!].privacy = .hidden
    #expect(notices(before: household, after: noList, sent: [], rejected: []) == [])

    // A rejection of an op that wasn't sent, a forbidden op on a list that's still writable, or one with no list.
    #expect(notices(before: household, after: afterSam(.readonly), sent: [], rejected: [Rejection(opId: add.opId, reason: "forbidden")]) == [])
    #expect(notices(before: household, after: household, sent: [add], rejected: [Rejection(opId: add.opId, reason: "forbidden")]) == [])
    let personal = Op(.listUpdate, id: TestData.samList, name: "Party")
    #expect(notices(before: household, after: afterSam(.readonly), sent: [personal], rejected: [Rejection(opId: personal.opId, reason: "forbidden")]) == [])

    // A conflict on anything but an item.update with a name.
    let create = Op(.listCreate, id: TestData.sharedList, name: "Party", color: .teal)
    #expect(notices(before: household, after: household, sent: [create], rejected: [Rejection(opId: create.opId, reason: "conflict")]) == [])
    let noName = Op(.itemUpdate, id: TestData.milk, defaultStoreId: TestData.market)
    #expect(notices(before: household, after: household, sent: [noName], rejected: [Rejection(opId: noName.opId, reason: "conflict")]) == [])
}
