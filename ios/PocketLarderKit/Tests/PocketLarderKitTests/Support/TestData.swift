import Foundation
@testable import PocketLarderKit

/// The household the engine's tests, and those of later tasks, work on. Every array is in the order a server's
/// snapshot would have it.
enum TestData {
    static let alex = "10000000-0000-4000-8000-000000000001"
    static let sam = "10000000-0000-4000-8000-000000000002"
    static let alexDevice = "10000000-0000-4000-8000-0000000000d1"

    static let alexList = "20000000-0000-4000-8000-000000000001"
    static let samList = "20000000-0000-4000-8000-000000000002"
    static let sharedList = "20000000-0000-4000-8000-000000000003"
    static let bbqList = "20000000-0000-4000-8000-000000000004"
    static let oldPartyList = "20000000-0000-4000-8000-000000000005"

    static let market = "30000000-0000-4000-8000-000000000001"
    static let organicShop = "30000000-0000-4000-8000-000000000002"
    static let drugstore = "30000000-0000-4000-8000-000000000003"

    static let marketProduce = "40000000-0000-4000-8000-000000000001"
    static let organicProduce = "40000000-0000-4000-8000-000000000002"
    static let drugstoreCleaning = "40000000-0000-4000-8000-000000000003"
    static let marketDairy = "40000000-0000-4000-8000-000000000004"

    static let bellPeppers = "50000000-0000-4000-8000-000000000001"
    static let milk = "50000000-0000-4000-8000-000000000002"
    static let oatMilk = "50000000-0000-4000-8000-000000000003"
    static let apfel = "50000000-0000-4000-8000-000000000004"
    static let sponges = "50000000-0000-4000-8000-000000000005"

    static let entryBellPeppers = "60000000-0000-4000-8000-000000000001"
    static let entryBurritoSpice = "60000000-0000-4000-8000-000000000002"
    static let entrySharedMilk = "60000000-0000-4000-8000-000000000003"
    static let entrySharedApfel = "60000000-0000-4000-8000-000000000004"
    static let entryBBQSponges = "60000000-0000-4000-8000-000000000005"
    static let entrySamOatMilk = "60000000-0000-4000-8000-000000000006"
    static let entryOldPartyOatMilk = "60000000-0000-4000-8000-000000000007"
    static let entryBoughtMilk = "60000000-0000-4000-8000-000000000008"
    static let entryBoughtSponges = "60000000-0000-4000-8000-000000000009"

    static let createdAt = date("2026-10-26T18:30:00Z")

    static let household = Snapshot(
        me: Me(memberId: alex, deviceId: alexDevice, isAdmin: true),
        members: [
            Member(id: alex, name: "Alex", isAdmin: true, privacy: .open),
            Member(id: sam, name: "Sam", isAdmin: false, privacy: .open),
        ],
        lists: [
            ListInfo(id: alexList, ownerId: alex, name: nil, color: nil, archived: false, writable: true),
            ListInfo(id: samList, ownerId: sam, name: nil, color: nil, archived: false, writable: true),
            ListInfo(id: sharedList, ownerId: nil, name: "Shared", color: .teal, archived: false, writable: true),
            ListInfo(id: bbqList, ownerId: nil, name: "BBQ Sat", color: .orange, archived: false, writable: true),
            ListInfo(id: oldPartyList, ownerId: nil, name: "Old party", color: .gray, archived: true, writable: true),
        ],
        stores: [
            Store(id: market, name: "Market", position: 0),
            Store(id: organicShop, name: "Organic shop", position: 1),
            Store(id: drugstore, name: "Drugstore", position: 2),
        ],
        categories: [
            PocketLarderKit.Category(id: marketProduce, storeId: market, name: "Produce", position: 0),
            PocketLarderKit.Category(id: organicProduce, storeId: organicShop, name: "Produce", position: 0),
            PocketLarderKit.Category(id: drugstoreCleaning, storeId: drugstore, name: "Cleaning", position: 0),
            PocketLarderKit.Category(id: marketDairy, storeId: market, name: "Dairy", position: 1),
        ],
        items: [
            Item(id: bellPeppers, name: "Bell peppers", defaultStoreId: market),
            Item(id: milk, name: "Milk", defaultStoreId: market),
            Item(id: oatMilk, name: "Oat milk", defaultStoreId: market),
            Item(id: apfel, name: "Äpfel", defaultStoreId: market),
            Item(id: sponges, name: "Sponges", defaultStoreId: drugstore),
        ],
        placements: [
            Placement(itemId: bellPeppers, storeId: market, categoryId: marketProduce),
            Placement(itemId: bellPeppers, storeId: organicShop, categoryId: organicProduce),
            Placement(itemId: milk, storeId: market, categoryId: marketDairy),
            Placement(itemId: oatMilk, storeId: market, categoryId: marketDairy),
            Placement(itemId: apfel, storeId: market, categoryId: marketProduce),
            Placement(itemId: sponges, storeId: drugstore, categoryId: drugstoreCleaning),
        ],
        entries: [
            entry(entryBellPeppers, alexList, bellPeppers, "Bell peppers", market),
            entry(entryBurritoSpice, alexList, nil, "Burrito spice", nil),
            entry(entrySharedMilk, sharedList, milk, "Milk", market),
            entry(entrySharedApfel, sharedList, apfel, "Äpfel", market),
            entry(entryBBQSponges, bbqList, sponges, "Sponges", drugstore),
            entry(entrySamOatMilk, samList, oatMilk, "Oat milk", market),
            entry(entryOldPartyOatMilk, oldPartyList, oatMilk, "Oat milk", market),
            entry(entryBoughtMilk, sharedList, milk, "Milk", market, boughtAt: date("2026-10-27T09:00:00Z")),
            entry(entryBoughtSponges, alexList, sponges, "Sponges", drugstore, boughtAt: date("2026-10-28T09:00:00Z")),
        ]
    )

    static func date(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    /// A new empty directory and the `LocalFiles` on it.
    static func temporaryFiles() throws -> (directory: URL, files: LocalFiles) {
        let directory = FileManager.default.temporaryDirectory.appending(path: newID())
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (directory, LocalFiles(directory: directory))
    }

    private static func entry(
        _ id: String, _ listId: String, _ itemId: String?, _ text: String, _ storeId: String?, boughtAt: Date? = nil
    ) -> Entry {
        Entry(id: id, listId: listId, itemId: itemId, text: text, quantity: "", note: "", storeId: storeId, createdAt: createdAt, boughtAt: boughtAt)
    }
}
