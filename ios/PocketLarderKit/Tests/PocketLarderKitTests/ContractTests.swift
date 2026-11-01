import Foundation
import Testing
@testable import PocketLarderKit

@Test(.enabled(if: Contract.isConfigured)) func redeemAndSnapshot() async throws {
    let snapshot = try await Contract.admin().sync([]).snapshot
    #expect(snapshot.me.isAdmin)
    #expect(snapshot.myList?.writable == true)
    #expect(snapshot.members.contains { $0.name == "Contract" })
}

@Test(.enabled(if: Contract.isConfigured)) func badTokenIsUnauthorized() async throws {
    let client = APIClient(server: try Contract.serverURL(), token: "x.y")
    await #expect(throws: APIError.server(code: "unauthorized")) {
        _ = try await client.sync([])
    }
}

@Test(.enabled(if: Contract.isConfigured)) func noTokenIsMissingToken() async throws {
    let client = APIClient(server: try Contract.serverURL(), token: nil)
    await #expect(throws: APIError.server(code: "missing_token")) {
        _ = try await client.sync([])
    }
}

@Test(.enabled(if: Contract.isConfigured)) func everyOpTypeIsAccepted() async throws {
    let list = newID(), store = newID(), otherStore = newID(), category = newID()
    let unfiled = newID(), filed = newID(), item = newID()
    // Unique for the run, so entry.place creates the new item instead of linking to an existing one.
    let text = "Contract item \(newID())"
    let ops = [
        Op(.listCreate, id: list, name: "Contract list", color: .teal),
        Op(.storeCreate, id: store, name: "Contract store"),
        Op(.storeCreate, id: otherStore, name: "Contract other store"),
        Op(.categoryCreate, id: category, storeId: store, name: "Contract category"),
        Op(.entryAdd, id: unfiled, listId: list, text: text),
        Op(.entryPlace, id: unfiled, storeId: store, categoryId: category, newItemId: item),
        // After entry.place, because the server rejects an item_id that doesn't exist yet.
        Op(.entryAdd, id: filed, listId: list, itemId: item),
        Op(.entryUpdate, id: filed, quantity: "2", note: "Contract note"),
        Op(.entryBuy, id: filed),
        Op(.entryUnbuy, id: filed),
        Op(.itemUpdate, id: item, name: text + " renamed", defaultStoreId: store),
        Op(.itemPlace, id: item, storeId: store, categoryId: category),
        Op(.storeRename, id: store, name: "Contract store renamed"),
        Op(.categoryRename, id: category, name: "Contract category renamed"),
        Op(.storeReorder, ids: [otherStore, store]),
        Op(.categoryReorder, storeId: store, ids: [category]),
        Op(.listUpdate, id: list, name: "Contract list renamed", color: .blue, archived: true),
        Op(.memberSetPrivacy, privacy: .open),
        Op(.entryDelete, id: filed),
        Op(.itemDelete, id: item),
        Op(.categoryDelete, id: category),
        Op(.storeDelete, id: store),
    ]
    let response = try await Contract.admin().sync(ops)
    #expect(response.rejected == [])
}

@Test(.enabled(if: Contract.isConfigured)) func newMemberFlow() async throws {
    let (client, memberId, name) = try await Contract.newMember("Sam")
    let me = try await client.sync([]).snapshot.me
    #expect(!me.isAdmin)
    #expect(me.memberId == memberId)

    let admin = try await Contract.admin()
    let adminId = try await admin.sync([]).snapshot.me.memberId
    let members = try await admin.members()
    #expect(members.first { $0.id == adminId }?.devices.count == 1)
    #expect(members.first { $0.id == memberId }?.devices.count == 1)
    #expect(members.first { $0.id == memberId }?.name == name)
}

@Test(.enabled(if: Contract.isConfigured)) @MainActor func larderRoundTrip() async throws {
    let adminLarder = Larder(files: try TestData.temporaryFiles().files, client: try await Contract.admin())
    await adminLarder.sync()
    let myList = adminLarder.snapshot?.myList
    let listId = try #require(myList?.id)

    let entryId = newID()
    try adminLarder.perform([Op(.entryAdd, id: entryId, listId: listId, text: "Contract round trip")])
    await adminLarder.sync()

    let pending = adminLarder.pending
    let entries = adminLarder.snapshot?.entries
    #expect(pending.isEmpty)
    #expect(entries?.contains { $0.id == entryId } == true)
}

@Test(.enabled(if: Contract.isConfigured)) @MainActor func privacyNoticesAgainstServer() async throws {
    let (samClient, samId, samName) = try await Contract.newMember("Sam")
    let samLarder = Larder(files: try TestData.temporaryFiles().files, client: samClient)
    let adminLarder = Larder(files: try TestData.temporaryFiles().files, client: try await Contract.admin())
    await adminLarder.sync()
    let lists = adminLarder.view?.lists
    let samList = try #require(lists?.first { $0.ownerId == samId })

    try samLarder.perform([Op(.memberSetPrivacy, privacy: .readonly)])
    await samLarder.sync()
    let entryId = newID()
    try adminLarder.perform([Op(.entryAdd, id: entryId, listId: samList.id, text: "Contract privacy")])
    await adminLarder.sync()

    let readOnlyNotices = adminLarder.notices
    let entries = adminLarder.view?.entries
    #expect(readOnlyNotices == [.listReadOnly(ownerName: samName)])
    #expect(entries?.contains { $0.id == entryId } == false)

    adminLarder.dismissNotice()
    try samLarder.perform([Op(.memberSetPrivacy, privacy: .hidden)])
    await samLarder.sync()
    await adminLarder.sync()

    let hiddenNotices = adminLarder.notices
    #expect(hiddenNotices == [.listHidden(ownerName: samName, lostChanges: false)])
}
