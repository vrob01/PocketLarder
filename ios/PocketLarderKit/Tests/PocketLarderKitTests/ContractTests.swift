import Foundation
import Testing
@testable import PocketLarderKit

@Test(.enabled(if: Contract.isConfigured)) func redeemAndSnapshot() async throws {
    let snapshot = try await Contract.admin().sync([]).snapshot
    #expect(snapshot.me.isAdmin)
    #expect(snapshot.myList?.writable == true)
    #expect(snapshot.members.contains { $0.name == "Contract" })
}

/// Fails when the app's setting asks for more than this commit's server: raise the server's version with it.
@Test(.enabled(if: Contract.isConfigured)) func serverIsCompatible() async throws {
    let outcome = await APIClient(server: try Contract.serverURL(), token: nil).serverVersion()
    guard case .compatible = outcome else {
        Issue.record("This commit's server isn't compatible with the app's setting: \(outcome)")
        return
    }
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

@Test(.enabled(if: Contract.isConfigured)) func usedInviteIsRedeemed() async throws {
    _ = try await Contract.admin()
    await #expect(throws: APIError.server(code: "invite_redeemed")) {
        _ = try await Contract.redeemAdmin()
    }
}

@Test(.enabled(if: Contract.isConfigured)) func badMemberNameIsInvalid() async throws {
    let admin = try await Contract.admin()
    await #expect(throws: APIError.invalid(detail: "bad_member_name")) {
        _ = try await admin.createInvite(newMemberName: "")
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

/// `apply` is a second copy of the server's rules, so the phone's view of a batch must be what the server makes of it.
@Test(.enabled(if: Contract.isConfigured)) func applyMatchesServer() async throws {
    let admin = try await Contract.admin()
    let before = try await admin.sync([]).snapshot
    let myList = try #require(before.myList?.id)
    let list = newID(), store = newID(), other = newID(), category = newID(), second = newID(), otherCategory = newID()
    let unfiled = newID(), filed = newID(), linked = newID(), item = newID(), unusedItem = newID()
    // Unique for the run, with İ, which Go and Swift lowercase differently.
    let run = newID()
    let name = "İrmik \(run)"
    let missing = Op(.entryBuy, id: newID())
    let ops = [
        Op(.listCreate, id: list, name: "Parity list", color: .green),
        Op(.listUpdate, id: list, name: "Parity list renamed", archived: true),
        Op(.storeCreate, id: store, name: "Parity store"),
        Op(.storeCreate, id: other, name: "Parity other store"),
        Op(.storeRename, id: other, name: "Parity other store renamed"),
        Op(.categoryCreate, id: category, storeId: store, name: "Parity category"),
        Op(.categoryCreate, id: second, storeId: store, name: "Parity second category"),
        Op(.categoryCreate, id: otherCategory, storeId: other, name: "Parity other category"),
        Op(.categoryReorder, storeId: store, ids: [second, category]),
        Op(.entryAdd, id: unfiled, listId: myList, text: name),
        Op(.entryPlace, id: unfiled, storeId: store, categoryId: category, newItemId: item),
        Op(.entryAdd, id: filed, listId: list, itemId: item, quantity: "2"),
        Op(.entryUpdate, id: filed, note: "Parity note"),
        Op(.entryBuy, id: filed),
        // The same name in lower case, so filing it links it to the item instead of making `unusedItem`.
        Op(.entryAdd, id: linked, listId: myList, text: "irmik \(run)"),
        Op(.entryPlace, id: linked, storeId: store, categoryId: second, newItemId: unusedItem),
        Op(.itemUpdate, id: item, name: name + " renamed", defaultStoreId: other),
        Op(.itemPlace, id: item, storeId: other, categoryId: otherCategory),
        Op(.categoryDelete, id: category),
        Op(.storeDelete, id: other),
        missing,
    ]
    let local = applying(ops.map { PendingOp(op: $0, at: .now) }, to: before)
    let response = try await admin.sync(ops)
    let ids: Set = [list, store, other, category, second, otherCategory, unfiled, filed, linked, item, unusedItem]
    #expect(response.rejected.map(\.opId) == [missing.opId])
    #expect(ours(local, ids) == ours(response.snapshot, ids))
}

/// The rows with `ids`, in id order, without the times and the store positions that other tests can change meanwhile.
private func ours(_ s: Snapshot, _ ids: Set<String>) -> Snapshot {
    var s = s
    s.members = []
    s.lists = s.lists.filter { ids.contains($0.id) }.sorted { $0.id < $1.id }
    let stores = s.stores.filter { ids.contains($0.id) }
    let first = stores.map(\.position).min() ?? 0
    s.stores = stores.map { var store = $0; store.position -= first; return store }.sorted { $0.id < $1.id }
    s.categories = s.categories.filter { ids.contains($0.id) }.sorted { $0.id < $1.id }
    s.items = s.items.filter { ids.contains($0.id) }.sorted { $0.id < $1.id }
    s.placements = s.placements.filter { ids.contains($0.itemId) }.sorted { ($0.itemId, $0.storeId) < ($1.itemId, $1.storeId) }
    s.entries = s.entries.filter { ids.contains($0.id) }.map { entry in
        var entry = entry
        entry.createdAt = .distantPast
        entry.boughtAt = entry.boughtAt.map { _ in .distantPast }
        return entry
    }.sorted { $0.id < $1.id }
    return s
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

@Test(.enabled(if: Contract.isConfigured)) func inviteCapAgainstServer() async throws {
    let (client, _, _) = try await Contract.newMember("Cap")
    for _ in 1...10 {
        _ = try await client.createInvite()
    }
    await #expect(throws: APIError.server(code: "too_many_invites")) {
        _ = try await client.createInvite()
    }
    let revoked = try await client.revokeInvites()
    #expect(revoked == 10)
    _ = try await client.createInvite()
}

@Test(.enabled(if: Contract.isConfigured)) func invitesAgainstServer() async throws {
    let (client, memberId, _) = try await Contract.newMember("Invites")
    let paired = try await client.invites()
    #expect(paired.map(\.state) == [.redeemed])

    let admin = try await Contract.admin()
    let created = try await admin.createInvite(memberId: memberId)
    let forAdmin = try await admin.invites(memberId: memberId)
    let own = try await client.invites()
    // Both can expire in the same second, which leaves their order to their ids.
    #expect(forAdmin.map(\.state).sorted { $0.rawValue < $1.rawValue } == [.open, .redeemed])
    #expect(own == forAdmin)
    await #expect(throws: APIError.server(code: "forbidden")) {
        _ = try await client.invites(memberId: memberId)
    }

    let redeemed = try #require(own.first { $0.state == .redeemed })
    try await client.cancelInvite(created.id)
    let afterCancel = try await client.invites()
    #expect(afterCancel == [redeemed])
    await #expect(throws: APIError.server(code: "invite_redeemed")) {
        try await client.cancelInvite(redeemed.id)
    }

    let cleared = try await client.clearInvites()
    let afterClear = try await client.invites()
    #expect(cleared == 1)
    #expect(afterClear.isEmpty)
    _ = try await client.sync([])
}
