import Foundation
import Testing
@testable import PocketLarderKit

private let at = TestData.date("2026-10-30T10:00:00Z")
private let newOne = "70000000-0000-4000-8000-000000000001"
private let missing = "70000000-0000-4000-8000-0000000000ff"

private func applied(_ ops: Op..., to base: Snapshot = TestData.household, at time: Date = at) -> Snapshot {
    applying(ops.map { PendingOp(op: $0, at: time) }, to: base)
}

/// The household with Sam's list as `readonly` makes it for another member.
private var samReadOnly: Snapshot {
    var s = TestData.household
    s.lists[s.lists.firstIndex { $0.id == TestData.samList }!].writable = false
    return s
}

@Test func entryAddUnfiledAndWithItem() throws {
    let filed = newID()
    let s = applied(
        Op(.entryAdd, id: newOne, listId: TestData.alexList, text: "  oat   drink "),
        Op(.entryAdd, id: filed, listId: TestData.sharedList, itemId: TestData.sponges, text: "ignored")
    )

    let first = try #require(s.entries.first { $0.id == newOne })
    #expect(first.listId == TestData.alexList)
    #expect(first.text == "oat drink")
    #expect(first.itemId == nil)
    #expect(first.storeId == nil)
    #expect(first.quantity == "")
    #expect(first.note == "")
    #expect(first.createdAt == at)
    #expect(first.boughtAt == nil)

    let second = try #require(s.entries.first { $0.id == filed })
    #expect(second.text == "Sponges")
    #expect(second.itemId == TestData.sponges)
    #expect(second.storeId == TestData.drugstore)

    let elsewhere = applied(Op(.entryAdd, id: filed, listId: TestData.sharedList, itemId: TestData.sponges, storeId: TestData.market))
    #expect(elsewhere.entries.first { $0.id == filed }?.storeId == TestData.market)
}

@Test func entryAddExistingIdIsNoop() {
    let s = applied(Op(.entryAdd, id: TestData.entrySharedMilk, listId: TestData.alexList, text: "Something else"))
    #expect(s == TestData.household)
}

@Test func entryBuyKeepsFirstTime() {
    let later = at.addingTimeInterval(3600)
    let id = TestData.entryBellPeppers
    let bought = applied(Op(.entryBuy, id: id))
    #expect(bought.entries.first { $0.id == id }?.boughtAt == at)

    let again = applied(Op(.entryBuy, id: id), to: bought, at: later)
    #expect(again.entries.first { $0.id == id }?.boughtAt == at)

    let open = applied(Op(.entryUnbuy, id: id), to: again, at: later)
    #expect(open.entries.first { $0.id == id }?.boughtAt == nil)
}

@Test func readOnlyListUnchanged() {
    let base = samReadOnly
    #expect(applied(Op(.entryAdd, id: newOne, listId: TestData.samList, text: "Tea"), to: base) == base)
    #expect(applied(Op(.entryBuy, id: TestData.entrySamOatMilk), to: base) == base)
}

@Test func placeLinksExistingItemIgnoringCase() {
    let s = applied(
        Op(.entryAdd, id: newOne, listId: TestData.alexList, text: "  milk "),
        Op(.entryPlace, id: newOne, storeId: TestData.market, categoryId: TestData.marketDairy, newItemId: missing)
    )
    let entry = s.entries.first { $0.id == newOne }
    #expect(entry?.itemId == TestData.milk)
    #expect(entry?.storeId == TestData.market)
    #expect(entry?.text == "milk")
    #expect(s.item(missing) == nil)
    #expect(s.items == TestData.household.items)
}

@Test func placeCreatesItemAndPlacement() {
    let id = TestData.entryBurritoSpice
    let s = applied(Op(.entryPlace, id: id, storeId: TestData.market, categoryId: TestData.marketProduce, newItemId: newOne))
    #expect(s.item(newOne) == Item(id: newOne, name: "Burrito spice", defaultStoreId: TestData.market))
    #expect(s.placement(item: newOne, store: TestData.market)?.categoryId == TestData.marketProduce)
    let entry = s.entries.first { $0.id == id }
    #expect(entry?.itemId == newOne)
    #expect(entry?.storeId == TestData.market)
}

@Test func deletingStoreKeepsEntries() {
    let s = applied(Op(.storeDelete, id: TestData.market))
    let household = TestData.household
    #expect(s.entries.map(\.id) == household.entries.map(\.id))
    #expect(!s.entries.contains { $0.storeId == TestData.market })
    #expect(s.entries.map(\.itemId) == household.entries.map(\.itemId))
    #expect(s.entries.map(\.text) == household.entries.map(\.text))
    #expect(s.store(TestData.market) == nil)
    #expect(!s.categories.contains { $0.storeId == TestData.market })
    #expect(!s.placements.contains { $0.storeId == TestData.market })
    #expect(s.item(TestData.milk)?.defaultStoreId == nil)
    #expect(s.item(TestData.sponges)?.defaultStoreId == TestData.drugstore)
}

@Test func deletingItemKeepsText() {
    let s = applied(Op(.itemDelete, id: TestData.milk))
    let household = TestData.household
    #expect(s.entries.map(\.id) == household.entries.map(\.id))
    #expect(s.item(TestData.milk) == nil)
    #expect(!s.placements.contains { $0.itemId == TestData.milk })
    #expect(!s.entries.contains { $0.itemId == TestData.milk })
    let milk = s.entries.first { $0.id == TestData.entrySharedMilk }
    #expect(milk?.text == "Milk")
    #expect(milk?.storeId == TestData.market)
}

@Test func reorderKeepsUnlisted() {
    let order = [TestData.drugstore, TestData.market, TestData.organicShop]
    let s = applied(Op(.storeReorder, ids: [TestData.drugstore, TestData.market]))
    #expect(s.stores.map(\.id) == order)
    #expect(s.stores.map(\.position) == [0, 1, 2])

    let noisy = applied(Op(.storeReorder, ids: [missing, TestData.drugstore, TestData.market, TestData.drugstore]))
    #expect(noisy == s)

    #expect(applied(Op(.storeReorder)) == TestData.household)
}

@Test func renameOntoTakenNameUnchanged() {
    #expect(applied(Op(.itemUpdate, id: TestData.milk, name: "OAT MILK")) == TestData.household)
    #expect(applied(Op(.itemUpdate, id: TestData.milk, name: "MILK")).item(TestData.milk)?.name == "MILK")
}

@Test func rejectedOpsChangeNothing() throws {
    let long = String(repeating: "x", count: 101)
    let cases: [Op] = [
        // entry.add: not_found
        Op(.entryAdd, id: newOne, listId: missing, text: "Tea"),
        Op(.entryAdd, id: newOne, text: "Tea"),
        Op(.entryAdd, id: newOne, listId: TestData.alexList, itemId: missing),
        Op(.entryAdd, id: newOne, listId: TestData.alexList, itemId: TestData.milk, storeId: missing),
        // entry.add: invalid
        Op(.entryAdd, id: "not-a-uuid", listId: TestData.alexList, text: "Tea"),
        Op(.entryAdd, id: "7000000A-0000-4000-8000-000000000001", listId: TestData.alexList, text: "Tea"),
        Op(.entryAdd, listId: TestData.alexList, text: "Tea"),
        Op(.entryAdd, id: newOne, listId: TestData.alexList),
        Op(.entryAdd, id: newOne, listId: TestData.alexList, storeId: TestData.market, text: "Tea"),
        Op(.entryAdd, id: newOne, listId: TestData.alexList, text: "   "),
        Op(.entryAdd, id: newOne, listId: TestData.alexList, text: long),
        Op(.entryAdd, id: newOne, listId: TestData.alexList, text: "Tea", quantity: "   "),
        Op(.entryAdd, id: newOne, listId: TestData.alexList, text: "Tea", quantity: String(repeating: "x", count: 33)),
        Op(.entryAdd, id: newOne, listId: TestData.alexList, text: "Tea", note: "   "),
        Op(.entryAdd, id: newOne, listId: TestData.alexList, text: "Tea", note: String(repeating: "x", count: 201)),
        // entry.update: not_found, invalid
        Op(.entryUpdate, id: missing, quantity: "2"),
        Op(.entryUpdate, id: TestData.entrySharedMilk),
        Op(.entryUpdate, id: TestData.entrySharedMilk, quantity: "2", note: "   "),
        Op(.entryUpdate, id: TestData.entrySharedMilk, quantity: "   ", note: "fine"),
        // entry.buy, entry.unbuy, entry.delete: not_found
        Op(.entryBuy, id: missing),
        Op(.entryUnbuy, id: missing),
        Op(.entryDelete, id: missing),
        // entry.place: not_found
        Op(.entryPlace, id: missing, storeId: TestData.market),
        Op(.entryPlace, id: TestData.entrySharedMilk, storeId: missing),
        Op(.entryPlace, id: TestData.entrySharedMilk),
        // entry.place: invalid
        Op(.entryPlace, id: TestData.entrySharedMilk, storeId: TestData.market, categoryId: missing),
        Op(.entryPlace, id: TestData.entrySharedMilk, storeId: TestData.market, categoryId: TestData.drugstoreCleaning),
        Op(.entryPlace, id: TestData.entryBurritoSpice, storeId: TestData.market, newItemId: newOne),
        Op(.entryPlace, id: TestData.entryBurritoSpice, storeId: TestData.market, categoryId: "", newItemId: newOne),
        Op(.entryPlace, id: TestData.entryBurritoSpice, storeId: TestData.market, categoryId: TestData.marketProduce),
        Op(.entryPlace, id: TestData.entryBurritoSpice, storeId: TestData.market, categoryId: TestData.marketProduce, newItemId: "not-a-uuid"),
        // entry.place: conflict
        Op(.entryPlace, id: TestData.entryBurritoSpice, storeId: TestData.market, categoryId: TestData.marketProduce, newItemId: TestData.milk),
        // member.set_privacy: invalid
        Op(.memberSetPrivacy),
        // list.create: invalid
        Op(.listCreate, id: "not-a-uuid", name: "Party", color: .teal),
        Op(.listCreate, id: newOne, color: .teal),
        Op(.listCreate, id: newOne, name: "   ", color: .teal),
        Op(.listCreate, id: newOne, name: "Party"),
        // list.create: conflict
        Op(.listCreate, id: TestData.sharedList, name: "Party", color: .teal),
        // list.update: not_found, forbidden, invalid
        Op(.listUpdate, id: missing, name: "Party"),
        Op(.listUpdate, id: TestData.alexList, name: "Party"),
        Op(.listUpdate, id: TestData.samList, archived: true),
        Op(.listUpdate, id: TestData.sharedList),
        Op(.listUpdate, id: TestData.sharedList, name: "   ", color: .red),
        // store.create: invalid, conflict
        Op(.storeCreate, id: "not-a-uuid", name: "Bakery"),
        Op(.storeCreate, id: newOne),
        Op(.storeCreate, id: newOne, name: "   "),
        Op(.storeCreate, id: TestData.market, name: "Bakery"),
        // store.rename: not_found, invalid
        Op(.storeRename, id: missing, name: "Bakery"),
        Op(.storeRename, id: TestData.market),
        Op(.storeRename, id: TestData.market, name: long),
        // store.delete: not_found
        Op(.storeDelete, id: missing),
        // category.create: not_found, invalid, conflict
        Op(.categoryCreate, id: newOne, storeId: missing, name: "Bread"),
        Op(.categoryCreate, id: "not-a-uuid", storeId: TestData.market, name: "Bread"),
        Op(.categoryCreate, id: newOne, storeId: TestData.market),
        Op(.categoryCreate, id: newOne, storeId: TestData.market, name: "   "),
        Op(.categoryCreate, id: TestData.marketDairy, storeId: TestData.market, name: "Bread"),
        // category.rename: not_found, invalid
        Op(.categoryRename, id: missing, name: "Bread"),
        Op(.categoryRename, id: TestData.marketDairy),
        Op(.categoryRename, id: TestData.marketDairy, name: "   "),
        // category.delete: not_found
        Op(.categoryDelete, id: missing),
        // category.reorder: not_found
        Op(.categoryReorder, storeId: missing, ids: [TestData.marketDairy, TestData.marketProduce]),
        // item.update: not_found, invalid, conflict
        Op(.itemUpdate, id: missing, name: "Bread"),
        Op(.itemUpdate, id: TestData.milk, defaultStoreId: missing),
        Op(.itemUpdate, id: TestData.milk, name: "Bread", defaultStoreId: missing),
        Op(.itemUpdate, id: TestData.milk),
        Op(.itemUpdate, id: TestData.milk, name: "   ", defaultStoreId: TestData.drugstore),
        Op(.itemUpdate, id: TestData.milk, name: "oat milk", defaultStoreId: TestData.drugstore),
        // item.place: not_found, invalid
        Op(.itemPlace, id: missing, storeId: TestData.market, categoryId: TestData.marketDairy),
        Op(.itemPlace, id: TestData.milk, storeId: missing, categoryId: TestData.marketDairy),
        Op(.itemPlace, id: TestData.milk, storeId: TestData.market),
        Op(.itemPlace, id: TestData.milk, storeId: TestData.market, categoryId: ""),
        Op(.itemPlace, id: TestData.milk, storeId: TestData.market, categoryId: missing),
        Op(.itemPlace, id: TestData.milk, storeId: TestData.market, categoryId: TestData.drugstoreCleaning),
        // item.delete: not_found
        Op(.itemDelete, id: missing),
    ]
    for op in cases {
        #expect(applied(op) == TestData.household, "\(op)")
    }

    // forbidden, for each entry op on a list that isn't writable.
    let forbidden = [
        Op(.entryAdd, id: newOne, listId: TestData.samList, text: "Tea"),
        Op(.entryUpdate, id: TestData.entrySamOatMilk, quantity: "2"),
        Op(.entryBuy, id: TestData.entrySamOatMilk),
        Op(.entryUnbuy, id: TestData.entrySamOatMilk),
        Op(.entryDelete, id: TestData.entrySamOatMilk),
        Op(.entryPlace, id: TestData.entrySamOatMilk, storeId: TestData.organicShop),
    ]
    let readOnly = samReadOnly
    for op in forbidden {
        #expect(applied(op, to: readOnly) == readOnly, "\(op)")
    }

    // `Op.init` can't make a bad `op_id`, but a decoded op can have one.
    let json = #"{"op_id":"not-a-uuid","type":"entry.buy","id":"\#(TestData.entrySharedMilk)"}"#
    let badOpId = try JSON.decoder.decode(Op.self, from: Data(json.utf8))
    #expect(applied(badOpId) == TestData.household)
}

@Test func remainingOpsApply() throws {
    let household = TestData.household

    // entry.add with quantity and note, `""` and absent, and empty ids as absent
    let added = applied(
        Op(.entryAdd, id: newOne, listId: TestData.alexList, text: "Tea", quantity: " 2  packs ", note: " green "),
        Op(.entryAdd, id: missing, listId: TestData.alexList, itemId: "", storeId: "", text: "Rice", quantity: "", note: "")
    )
    let tea = try #require(added.entries.first { $0.id == newOne })
    #expect(tea.quantity == "2 packs")
    #expect(tea.note == "green")
    let rice = try #require(added.entries.first { $0.id == missing })
    #expect(rice.text == "Rice")
    #expect(rice.itemId == nil)
    #expect(rice.storeId == nil)
    #expect(rice.quantity == "")
    #expect(rice.note == "")

    // entry.update sets each field present, and `""` clears it
    let id = TestData.entrySharedMilk
    let updated = applied(Op(.entryUpdate, id: id, quantity: " 2 ", note: " oat "))
    #expect(updated.entries.first { $0.id == id }?.quantity == "2")
    #expect(updated.entries.first { $0.id == id }?.note == "oat")
    let onlyNote = applied(Op(.entryUpdate, id: id, note: "soy"), to: updated)
    #expect(onlyNote.entries.first { $0.id == id }?.quantity == "2")
    #expect(onlyNote.entries.first { $0.id == id }?.note == "soy")
    let cleared = applied(Op(.entryUpdate, id: id, quantity: ""), to: onlyNote)
    #expect(cleared.entries.first { $0.id == id }?.quantity == "")
    #expect(cleared.entries.first { $0.id == id }?.note == "soy")

    // entry.delete and member.set_privacy
    let deleted = applied(Op(.entryDelete, id: id))
    #expect(deleted.entries.map(\.id) == household.entries.map(\.id).filter { $0 != id })
    let hidden = applied(Op(.memberSetPrivacy, privacy: .hidden))
    #expect(hidden.member(TestData.alex)?.privacy == .hidden)
    #expect(hidden.member(TestData.sam)?.privacy == .open)

    // list.create and list.update
    let party = applied(Op(.listCreate, id: newOne, name: " Summer   party ", color: .pink))
    #expect(party.list(newOne) == ListInfo(id: newOne, ownerId: nil, name: "Summer party", color: .pink, archived: false, writable: true))
    let renamed = applied(Op(.listUpdate, id: TestData.sharedList, name: " Home "))
    #expect(renamed.list(TestData.sharedList) == ListInfo(id: TestData.sharedList, ownerId: nil, name: "Home", color: .teal, archived: false, writable: true))
    let archived = applied(Op(.listUpdate, id: TestData.sharedList, color: .red, archived: true))
    #expect(archived.list(TestData.sharedList) == ListInfo(id: TestData.sharedList, ownerId: nil, name: "Shared", color: .red, archived: true, writable: true))

    // store.create, category.create and their positions
    let bakery = applied(Op(.storeCreate, id: newOne, name: " Bakery "))
    #expect(bakery.stores.map(\.id) == household.stores.map(\.id) + [newOne])
    #expect(bakery.store(newOne)?.name == "Bakery")
    #expect(bakery.store(newOne)?.position == 3)

    let noStores = applied(Op(.storeDelete, id: TestData.market), Op(.storeDelete, id: TestData.organicShop), Op(.storeDelete, id: TestData.drugstore))
    #expect(applied(Op(.storeCreate, id: newOne, name: "Bakery"), to: noStores).store(newOne)?.position == 0)

    let bread = applied(Op(.categoryCreate, id: newOne, storeId: TestData.market, name: " Bread "))
    #expect(bread.category(newOne)?.storeId == TestData.market)
    #expect(bread.category(newOne)?.name == "Bread")
    #expect(bread.category(newOne)?.position == 2)
    #expect(bread.categories.map(\.id) == household.categories.map(\.id) + [newOne])

    let inBakery = applied(Op(.categoryCreate, id: missing, storeId: newOne, name: "Rolls"), to: bakery)
    #expect(inBakery.category(missing)?.position == 0)
    #expect(inBakery.categories.map(\.position) == [0, 0, 0, 0, 1])

    // store.rename and category.rename
    #expect(applied(Op(.storeRename, id: TestData.market, name: " Farmers  market ")).store(TestData.market)?.name == "Farmers market")
    #expect(applied(Op(.categoryRename, id: TestData.marketDairy, name: " Cheese ")).category(TestData.marketDairy)?.name == "Cheese")

    // category.delete keeps the entries, and category.reorder leaves another store's categories alone
    let noDairy = applied(Op(.categoryDelete, id: TestData.marketDairy))
    #expect(noDairy.category(TestData.marketDairy) == nil)
    #expect(noDairy.categories.count == household.categories.count - 1)
    #expect(!noDairy.placements.contains { $0.categoryId == TestData.marketDairy })
    #expect(noDairy.placements.count == household.placements.count - 2)
    #expect(noDairy.entries == household.entries)

    let reordered = applied(Op(.categoryReorder, storeId: TestData.market, ids: [TestData.marketDairy, TestData.drugstoreCleaning, missing]))
    #expect(reordered.category(TestData.marketDairy)?.position == 0)
    #expect(reordered.category(TestData.marketProduce)?.position == 1)
    #expect(reordered.category(TestData.drugstoreCleaning)?.position == 0)
    #expect(reordered.category(TestData.organicProduce)?.position == 0)
    #expect(reordered.categories.map(\.id) == [TestData.organicProduce, TestData.drugstoreCleaning, TestData.marketDairy, TestData.marketProduce])

    // item.update sets and clears the default store, and doesn't touch the text of its entries
    let moved = applied(Op(.itemUpdate, id: TestData.milk, defaultStoreId: TestData.drugstore))
    #expect(moved.item(TestData.milk)?.defaultStoreId == TestData.drugstore)
    #expect(moved.item(TestData.milk)?.name == "Milk")
    let noDefault = applied(Op(.itemUpdate, id: TestData.milk, defaultStoreId: ""), to: moved)
    #expect(noDefault.item(TestData.milk)?.defaultStoreId == nil)
    let bothFields = applied(Op(.itemUpdate, id: TestData.milk, name: " Whole  milk ", defaultStoreId: TestData.drugstore))
    #expect(bothFields.item(TestData.milk) == Item(id: TestData.milk, name: "Whole milk", defaultStoreId: TestData.drugstore))
    #expect(bothFields.entries == household.entries)

    // item.place replaces a placement and adds one, and leaves the default store and the entries alone
    let replaced = applied(Op(.itemPlace, id: TestData.milk, storeId: TestData.market, categoryId: TestData.marketProduce))
    #expect(replaced.placement(item: TestData.milk, store: TestData.market)?.categoryId == TestData.marketProduce)
    #expect(replaced.placements.count == household.placements.count)
    #expect(replaced.items == household.items)
    #expect(replaced.entries == household.entries)
    let secondStore = applied(Op(.itemPlace, id: TestData.milk, storeId: TestData.organicShop, categoryId: TestData.organicProduce))
    #expect(secondStore.placement(item: TestData.milk, store: TestData.organicShop)?.categoryId == TestData.organicProduce)
    #expect(secondStore.placements.count == household.placements.count + 1)

    // entry.place on a filed entry: `newItemId` ignored
    let filed = applied(Op(.entryPlace, id: id, storeId: TestData.organicShop, categoryId: TestData.organicProduce, newItemId: "not-a-uuid"))
    #expect(filed.entries.first { $0.id == id }?.itemId == TestData.milk)
    #expect(filed.entries.first { $0.id == id }?.storeId == TestData.organicShop)
    #expect(filed.placement(item: TestData.milk, store: TestData.organicShop)?.categoryId == TestData.organicProduce)
    #expect(filed.item(TestData.milk)?.defaultStoreId == TestData.market)
    #expect(filed.items == household.items)

    // entry.place on a filed entry: no `categoryId` leaves placements alone
    let noCategory = applied(Op(.entryPlace, id: id, storeId: TestData.organicShop))
    #expect(noCategory.entries.first { $0.id == id }?.storeId == TestData.organicShop)
    #expect(noCategory.placements == household.placements)

    // entry.place on a filed entry: a missing default store gets filled
    let withoutDefault = applied(Op(.itemUpdate, id: TestData.milk, defaultStoreId: ""))
    let filled = applied(Op(.entryPlace, id: id, storeId: TestData.organicShop), to: withoutDefault)
    #expect(filled.item(TestData.milk)?.defaultStoreId == TestData.organicShop)

    // Only `createdAt` of entry.add and `boughtAt` of entry.buy take the op's time
    #expect(applied(Op(.entryUpdate, id: id, quantity: "2")).entries.first { $0.id == id }?.createdAt == TestData.createdAt)
}
