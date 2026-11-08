import Testing
@testable import PocketLarderKit

private let household = TestData.household

private func item(_ id: String) throws -> Item {
    try #require(household.item(id))
}

@Test func suggestionsPrefixFirst() throws {
    #expect(suggestions(household, for: "mil").map(\.item.name) == ["Milk", "Oat milk"])

    for query in ["äp", "ap"] {
        let found = suggestions(household, for: query)
        #expect(found.map(\.item.name) == ["Äpfel"])
        #expect(found.first?.store?.name == "Market")
        #expect(found.first?.category?.name == "Produce")
    }

    #expect(suggestions(household, for: "   ").isEmpty)
    #expect(suggestions(household, for: "l", limit: 2).map(\.item.name) == ["Äpfel", "Bell peppers"])
}

@Test func addingExistingOpenItemShowsIt() throws {
    let peppers = try item(TestData.bellPeppers)
    guard case let .existing(entry) = add(peppers, to: TestData.alexList, in: household) else {
        Issue.record("Bell peppers are already on Alex's list")
        return
    }
    #expect(entry.id == TestData.entryBellPeppers)

    guard case let .add(op) = add(peppers, to: TestData.sharedList, in: household) else {
        Issue.record("Bell peppers aren't on Shared")
        return
    }
    #expect(op.type == .entryAdd)
    #expect(op.listId == TestData.sharedList)
    #expect(op.itemId == TestData.bellPeppers)
    #expect(op.id != nil)
    #expect(op.text == nil)

    // A bought entry isn't open, so the item goes on the list again.
    guard case .add = add(try item(TestData.sponges), to: TestData.alexList, in: household) else {
        Issue.record("Alex's Sponges are bought")
        return
    }
}

@Test func returnOnExistingName() {
    guard case let .add(op) = add(text: " MILK ", to: TestData.alexList, in: household) else {
        Issue.record("Milk isn't on Alex's list")
        return
    }
    #expect(op.itemId == TestData.milk)
    #expect(op.text == nil)
}

@Test func unfiledAndTooLong() {
    guard case let .add(op) = add(text: " Birthday  candles ", to: TestData.alexList, in: household) else {
        Issue.record("Birthday candles are new")
        return
    }
    #expect(op.type == .entryAdd)
    #expect(op.listId == TestData.alexList)
    #expect(op.text == "Birthday candles")
    #expect(op.itemId == nil)

    #expect(add(text: String(repeating: "x", count: 101), to: TestData.alexList, in: household) == nil)
    #expect(add(text: "   ", to: TestData.alexList, in: household) == nil)
}
