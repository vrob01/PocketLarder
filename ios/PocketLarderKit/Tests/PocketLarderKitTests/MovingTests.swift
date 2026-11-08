import Foundation
import Testing
@testable import PocketLarderKit

private let household = TestData.household

private func entry(_ id: String) throws -> Entry {
    try #require(household.entries.first { $0.id == id })
}

@Test func moveToStoreWithPlacement() throws {
    let peppers = try entry(TestData.entryBellPeppers)
    guard case let .place(op) = move(peppers, to: TestData.organicShop, in: household) else {
        Issue.record("Bell peppers are placed at Organic shop")
        return
    }
    #expect(op.type == .entryPlace)
    #expect(op.id == TestData.entryBellPeppers)
    #expect(op.storeId == TestData.organicShop)
    #expect(op.categoryId == nil)
    #expect(op.newItemId == nil)
}

@Test func moveNeedsCategoryOnce() throws {
    let milk = try entry(TestData.entrySharedMilk)
    #expect(move(milk, to: TestData.organicShop, in: household) == .needsCategory)

    guard case let .place(op) = move(milk, to: TestData.organicShop, category: TestData.organicProduce, in: household) else {
        Issue.record("A category files the milk")
        return
    }
    #expect(op.storeId == TestData.organicShop)
    #expect(op.categoryId == TestData.organicProduce)
    #expect(op.newItemId == nil)
}

@Test func fileUnfiled() throws {
    let spice = try entry(TestData.entryBurritoSpice)
    #expect(move(spice, to: TestData.market, in: household) == .needsCategory)

    var ids: [String] = []
    for _ in 0..<2 {
        guard case let .place(op) = move(spice, to: TestData.market, category: TestData.marketProduce, in: household) else {
            Issue.record("A category files the Burrito spice")
            return
        }
        #expect(op.storeId == TestData.market)
        #expect(op.categoryId == TestData.marketProduce)
        let newItemId = try #require(op.newItemId)
        #expect(UUID(uuidString: newItemId) != nil)
        #expect(newItemId == newItemId.lowercased())
        ids.append(newItemId)
    }
    #expect(ids[0] != ids[1])
}
