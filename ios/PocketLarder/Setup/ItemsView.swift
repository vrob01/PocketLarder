import PocketLarderKit
import SwiftUI

/// The catalog, searchable, under the Items segment of "Stores & items".
struct ItemsView: View {
    let larder: Larder
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Search items", text: $query)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .accessibilityIdentifier("items.search")
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(Color(.tertiarySystemFill), in: Capsule())
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
            List {
                if let view = larder.view {
                    ForEach(shown(view), id: \.id) { item in
                        NavigationLink {
                            ItemDetailView(larder: larder, item: item)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                if let detail = detail(item, in: view) {
                                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .accessibilityIdentifier("items.item")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    /// By name. A blank query shows every item.
    private func shown(_ view: Snapshot) -> [Item] {
        let items = view.items.sorted { (fold($0.name), $0.id) < (fold($1.name), $1.id) }
        guard let cleaned = cleanText(query, max: .max) else { return items }
        let folded = fold(cleaned)
        return items.filter { fold($0.name).contains(folded) }
    }
}

/// "Market · Produce", or the usual store alone while the item has no category there, then the count of the other
/// stores it is placed in. Nil without a usual store.
private func detail(_ item: Item, in view: Snapshot) -> String? {
    guard let store = view.store(item.defaultStoreId) else { return nil }
    let category = view.placement(item: item.id, store: store.id).flatMap { view.category($0.categoryId) }
    let usual = category.map { String(localized: "\(store.name) · \($0.name)") } ?? store.name
    let others = view.placements.filter { $0.itemId == item.id && $0.storeId != store.id }.count
    return others == 0 ? usual : usual + String(localized: ", also at \(others) other stores")
}
