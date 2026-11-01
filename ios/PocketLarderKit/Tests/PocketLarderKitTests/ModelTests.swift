import Foundation
import Testing
@testable import PocketLarderKit

@Test func decodesAPIExampleSnapshot() throws {
    let json = """
    {
      "me": {"member_id": "3f367fb6-d649-4507-8a37-a0813a0cdfb7", "device_id": "41c68cb8-2f63-4d34-92b5-26d3521f739d", "is_admin": true},
      "members": [
        {"id": "3f367fb6-d649-4507-8a37-a0813a0cdfb7", "name": "Alex", "is_admin": true, "privacy": "open"},
        {"id": "7317f087-10f7-4bd2-b23e-c5d5726c04bd", "name": "Sam", "is_admin": false, "privacy": "hidden"}
      ],
      "lists": [
        {"id": "25662915-e490-432f-9165-23d1318ebafd", "owner_id": null, "name": "Party", "color": "teal", "archived": false, "writable": true},
        {"id": "8832e435-0cdc-4290-b837-bbcc46e65f42", "owner_id": "3f367fb6-d649-4507-8a37-a0813a0cdfb7", "name": null, "color": null, "archived": false, "writable": true}
      ],
      "stores": [
        {"id": "56058b71-5fd8-4e28-8784-5a26ddd960c0", "name": "Corner shop", "position": 0}
      ],
      "categories": [
        {"id": "5cb64f0a-df16-48a1-bb51-7896414bc438", "store_id": "56058b71-5fd8-4e28-8784-5a26ddd960c0", "name": "Dairy", "position": 0}
      ],
      "items": [
        {"id": "6c052e92-3357-493b-9e07-65ae1fb0802f", "name": "Milk", "default_store_id": "56058b71-5fd8-4e28-8784-5a26ddd960c0"}
      ],
      "placements": [
        {"item_id": "6c052e92-3357-493b-9e07-65ae1fb0802f", "store_id": "56058b71-5fd8-4e28-8784-5a26ddd960c0", "category_id": "5cb64f0a-df16-48a1-bb51-7896414bc438"}
      ],
      "entries": [
        {"id": "785a8c25-38e6-4526-80ca-290927283c0f", "list_id": "8832e435-0cdc-4290-b837-bbcc46e65f42", "item_id": "6c052e92-3357-493b-9e07-65ae1fb0802f", "text": "Milk", "quantity": "", "note": "", "store_id": "56058b71-5fd8-4e28-8784-5a26ddd960c0", "created_at": "2026-10-26T18:30:00Z", "bought_at": "2026-10-27T09:12:40Z"},
        {"id": "ae94504a-2040-4e7b-bfea-d548f7d2f25e", "list_id": "8832e435-0cdc-4290-b837-bbcc46e65f42", "item_id": null, "text": "Burrito spice", "quantity": "2", "note": "", "store_id": null, "created_at": "2026-10-27T10:00:00Z", "bought_at": null}
      ]
    }
    """
    let snapshot = try JSON.decoder.decode(Snapshot.self, from: Data(json.utf8))

    #expect(snapshot.members.count == 2)
    #expect(snapshot.lists[0].ownerId == nil)
    #expect(snapshot.lists[0].name == "Party")
    #expect(snapshot.lists[0].color == .teal)
    #expect(snapshot.lists[1].name == nil)
    #expect(snapshot.entries[0].boughtAt == ISO8601DateFormatter().date(from: "2026-10-27T09:12:40Z"))
    #expect(snapshot.entries[1].itemId == nil)
    #expect(snapshot.entries[1].storeId == nil)
    #expect(snapshot.entries[1].quantity == "2")
    #expect(snapshot.myList?.ownerId == snapshot.me.memberId)

    #expect(snapshot.member("7317f087-10f7-4bd2-b23e-c5d5726c04bd")?.name == "Sam")
    #expect(snapshot.list("25662915-e490-432f-9165-23d1318ebafd")?.name == "Party")
    #expect(snapshot.store("56058b71-5fd8-4e28-8784-5a26ddd960c0")?.name == "Corner shop")
    #expect(snapshot.category("5cb64f0a-df16-48a1-bb51-7896414bc438")?.name == "Dairy")
    #expect(snapshot.item("6c052e92-3357-493b-9e07-65ae1fb0802f")?.name == "Milk")
    let item = "6c052e92-3357-493b-9e07-65ae1fb0802f", store = "56058b71-5fd8-4e28-8784-5a26ddd960c0"
    #expect(snapshot.placement(item: item, store: store)?.categoryId == "5cb64f0a-df16-48a1-bb51-7896414bc438")

    #expect(snapshot.member(nil) == nil)
    #expect(snapshot.list(nil) == nil)
    #expect(snapshot.store(nil) == nil)
    #expect(snapshot.category(nil) == nil)
    #expect(snapshot.item(nil) == nil)
    #expect(snapshot.placement(item: nil, store: store) == nil)
    #expect(snapshot.placement(item: item, store: nil) == nil)

    #expect(try JSON.decoder.decode(Snapshot.self, from: JSON.encoder.encode(snapshot)) == snapshot)
}

@Test func encodesOnlyGivenFields() throws {
    let x = newID()
    let buy = try JSONSerialization.jsonObject(with: JSON.encoder.encode(Op(.entryBuy, id: x))) as? [String: Any]
    #expect(buy?.keys.sorted() == ["id", "op_id", "type"])
    #expect(buy?["type"] as? String == "entry.buy")

    let update = try JSONSerialization.jsonObject(with: JSON.encoder.encode(Op(.itemUpdate, id: x, defaultStoreId: ""))) as? [String: Any]
    #expect(update?["default_store_id"] as? String == "")
}

@Test func opIdsAreFreshLowercaseUUIDs() throws {
    let ops = (0..<1000).map { _ in Op(.entryBuy) }
    #expect(Set(ops.map(\.opId)).count == 1000)
    #expect(ops.allSatisfy { $0.opId.wholeMatch(of: /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/) != nil })

    #expect(try JSON.decoder.decode(Op.self, from: JSON.encoder.encode(ops[0])) == ops[0])
}
