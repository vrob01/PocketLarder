import Foundation
import Testing
@testable import PocketLarderKit

private let household = TestData.household

private func setList(_ id: String, in s: inout Snapshot, _ change: (inout ListInfo) -> Void) throws {
    let index = try #require(s.lists.firstIndex { $0.id == id })
    change(&s.lists[index])
}

private func openEntry(_ id: String, _ text: String, item: String, store: String?) -> Entry {
    Entry(
        id: id, listId: TestData.alexList, itemId: item, text: text, quantity: "", note: "", storeId: store,
        createdAt: TestData.createdAt, boughtAt: nil
    )
}

@Test func myViewMergesOwnAndShared() {
    let result = shelf(household, scope: .myView, filter: .all)
    let open = result.notFiled + result.stores.flatMap { $0.groups.flatMap(\.entries) }
    #expect(Set((open + result.recentlyBought).map(\.id)) == [
        TestData.entryBellPeppers, TestData.entryBurritoSpice, TestData.entrySharedMilk, TestData.entrySharedApfel,
        TestData.entryBBQSponges, TestData.entryBoughtMilk, TestData.entryBoughtSponges,
    ])
}

@Test func walkingOrder() throws {
    let result = shelf(household, scope: .myView, filter: .all)
    #expect(result.stores.map(\.store.name) == ["Market", "Drugstore"])
    let market = try #require(result.stores.first)
    #expect(market.groups.map(\.category.name) == ["Produce", "Dairy"])
    #expect(market.groups.map { $0.entries.map(\.text) } == [["Äpfel", "Bell peppers"], ["Milk"]])

    let drugstore = shelf(household, scope: .myView, filter: .store(TestData.drugstore))
    #expect(drugstore.stores.map(\.store.name) == ["Drugstore"])
}

@Test func notFiledRules() {
    var s = household
    // Sponges have no placement at the Market.
    s.entries.append(openEntry("60000000-0000-4000-8000-0000000000a1", "Sponges", item: TestData.sponges, store: TestData.market))
    s.entries.append(openEntry("60000000-0000-4000-8000-0000000000a2", "Bell peppers", item: TestData.bellPeppers, store: nil))

    let all = shelf(s, scope: .myView, filter: .all)
    #expect(all.notFiled.map(\.text) == ["Bell peppers", "Burrito spice", "Sponges"])

    let market = shelf(s, scope: .myView, filter: .store(TestData.market))
    #expect(market.notFiled.map(\.text) == ["Bell peppers", "Burrito spice", "Sponges"])

    let drugstore = shelf(s, scope: .myView, filter: .store(TestData.drugstore))
    #expect(drugstore.notFiled.map(\.text) == ["Bell peppers", "Burrito spice"])
}

@Test func recentlyBoughtNewestFirst() {
    let all = shelf(household, scope: .myView, filter: .all)
    #expect(all.recentlyBought.map(\.id) == [TestData.entryBoughtSponges, TestData.entryBoughtMilk])

    let drugstore = shelf(household, scope: .myView, filter: .store(TestData.drugstore))
    #expect(drugstore.recentlyBought.map(\.id) == [TestData.entryBoughtSponges])

    var s = household
    s.entries.insert(
        Entry(
            id: "60000000-0000-4000-8000-0000000000a3", listId: TestData.alexList, itemId: nil, text: "Tie", quantity: "", note: "",
            storeId: nil, createdAt: TestData.createdAt, boughtAt: TestData.date("2026-10-28T09:00:00Z")
        ),
        at: 0
    )
    #expect(shelf(s, scope: .myView, filter: .all).recentlyBought.map(\.text) == ["Sponges", "Tie", "Milk"])
}

@Test func switcherAndTargets() throws {
    var s = household
    #expect(switcherLists(s).map(\.id) == [TestData.bbqList, TestData.sharedList, TestData.samList])
    #expect(addTargets(s).map(\.id) == [TestData.alexList, TestData.bbqList, TestData.sharedList, TestData.samList])

    try setList(TestData.samList, in: &s) { $0.writable = false }
    #expect(switcherLists(s).map(\.id) == [TestData.bbqList, TestData.sharedList, TestData.samList])
    #expect(addTargets(s).map(\.id) == [TestData.alexList, TestData.bbqList, TestData.sharedList])
}

@Test func hiddenScopeFallsBackToMyView() throws {
    #expect(validScope(.list(TestData.samList), in: household) == .list(TestData.samList))
    #expect(validScope(.myView, in: household) == .myView)

    var hidden = household
    hidden.lists.removeAll { $0.id == TestData.samList }
    #expect(validScope(.list(TestData.samList), in: hidden) == .myView)

    #expect(validScope(.list(TestData.oldPartyList), in: household) == .myView)
}

@Test func chipsFollowScope() {
    #expect(chipStores(household, scope: .myView).map(\.name) == ["Market", "Drugstore"])
    #expect(chipStores(household, scope: .list(TestData.samList)).map(\.name) == ["Market"])
    // Sponges are bought, and still give the Drugstore its chip.
    #expect(chipStores(household, scope: .list(TestData.alexList)).map(\.name) == ["Market", "Drugstore"])
}

@Test func targetFallsBackToMyList() throws {
    #expect(validTarget(nil, in: household)?.id == TestData.alexList)
    #expect(validTarget(TestData.sharedList, in: household)?.id == TestData.sharedList)
    #expect(validTarget(newID(), in: household)?.id == TestData.alexList)

    var s = household
    try setList(TestData.samList, in: &s) { $0.writable = false }
    #expect(validTarget(TestData.samList, in: s)?.id == TestData.alexList)
    try setList(TestData.sharedList, in: &s) { $0.archived = true }
    #expect(validTarget(TestData.sharedList, in: s)?.id == TestData.alexList)
}

@Test func tagsOnlySharedLists() throws {
    let entries = household.entries
    let shared = try #require(entries.first { $0.id == TestData.entrySharedMilk })
    let own = try #require(entries.first { $0.id == TestData.entryBellPeppers })
    #expect(tag(for: shared, in: household)?.name == "Shared")
    #expect(tag(for: own, in: household) == nil)
}
