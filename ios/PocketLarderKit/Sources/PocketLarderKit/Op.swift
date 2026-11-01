public enum OpType: String, Codable, Sendable {
    case entryAdd = "entry.add"
    case entryUpdate = "entry.update"
    case entryBuy = "entry.buy"
    case entryUnbuy = "entry.unbuy"
    case entryDelete = "entry.delete"
    case entryPlace = "entry.place"
    case memberSetPrivacy = "member.set_privacy"
    case listCreate = "list.create"
    case listUpdate = "list.update"
    case storeCreate = "store.create"
    case storeRename = "store.rename"
    case storeDelete = "store.delete"
    case storeReorder = "store.reorder"
    case categoryCreate = "category.create"
    case categoryRename = "category.rename"
    case categoryDelete = "category.delete"
    case categoryReorder = "category.reorder"
    case itemUpdate = "item.update"
    case itemPlace = "item.place"
    case itemDelete = "item.delete"
}

public struct Op: Codable, Equatable, Sendable {
    public let opId: String
    public let type: OpType
    public var id, listId, itemId, storeId, categoryId, newItemId, text, quantity, note, name, defaultStoreId: String?
    public var color: ListColor?
    public var archived: Bool?
    public var ids: [String]?
    public var privacy: Privacy?

    public init(
        _ type: OpType,
        id: String? = nil,
        listId: String? = nil,
        itemId: String? = nil,
        storeId: String? = nil,
        categoryId: String? = nil,
        newItemId: String? = nil,
        text: String? = nil,
        quantity: String? = nil,
        note: String? = nil,
        name: String? = nil,
        defaultStoreId: String? = nil,
        color: ListColor? = nil,
        archived: Bool? = nil,
        ids: [String]? = nil,
        privacy: Privacy? = nil
    ) {
        opId = newID()
        self.type = type
        self.id = id
        self.listId = listId
        self.itemId = itemId
        self.storeId = storeId
        self.categoryId = categoryId
        self.newItemId = newItemId
        self.text = text
        self.quantity = quantity
        self.note = note
        self.name = name
        self.defaultStoreId = defaultStoreId
        self.color = color
        self.archived = archived
        self.ids = ids
        self.privacy = privacy
    }
}
