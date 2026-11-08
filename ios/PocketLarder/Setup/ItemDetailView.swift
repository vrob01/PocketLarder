import PocketLarderKit
import SwiftUI

/// One catalog item: its name, its usual store, its category in each store, and deleting it.
struct ItemDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let larder: Larder
    let item: Item
    @State private var name: String
    @State private var deleting = false
    @State private var saveFailure: String?
    @FocusState private var nameFocused: Bool

    init(larder: Larder, item: Item) {
        self.larder = larder
        self.item = item
        _name = State(initialValue: item.name)
    }

    /// The item as it is now, so that a sync's changes show.
    private var current: Item { larder.view?.item(item.id) ?? item }
    private var cleanName: String? { cleanText(name, max: Limit.name) }

    var body: some View {
        let view = larder.view
        let stores = view.map(storesInOrder) ?? []
        Form {
            Section("Name") {
                HStack {
                    TextField("Name", text: $name)
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .onSubmit { rename() }
                        .accessibilityIdentifier("item.name")
                    Button {
                        rename()
                    } label: {
                        // 44 points high without making the row taller.
                        Text("Save").contentShape(Rectangle().inset(by: -11))
                    }
                    .buttonStyle(.borderless)
                    .disabled(cleanName == nil)
                    .accessibilityIdentifier("item.save")
                }
            }
            Section {
                Picker("Usual store", selection: usualStore) {
                    Text("None").tag("")
                    ForEach(stores, id: \.id) { Text($0.name).tag($0.id) }
                }
                .accessibilityIdentifier("item.usualStore")
            }
            Section("Category in each store") {
                ForEach(stores, id: \.id) { store in
                    // The API can't take a placement away, so None is there only while there is none.
                    Picker(store.name, selection: category(in: store)) {
                        if view?.placement(item: item.id, store: store.id) == nil {
                            Text("None").tag("")
                        }
                        ForEach(categories(of: store), id: \.id) { Text($0.name).tag($0.id) }
                    }
                    .accessibilityIdentifier("item.category.\(store.name)")
                }
            }
            if let saveFailure {
                Section {
                    Text(saveFailure).accessibilityIdentifier("item.saveFailure")
                }
            }
            Section {
                Button("Delete item", role: .destructive) { deleting = true }
                    .accessibilityIdentifier("item.delete")
            }
        }
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.inline)
        .alert(Text("Delete \(current.name)? Entries keep their name and move to Not filed yet."), isPresented: $deleting) {
            Button("Delete", role: .destructive) {
                saveFailure = announced(larder.failureSaving([Op(.itemDelete, id: item.id)]))
            }
            Button("Cancel", role: .cancel) {}
        }
        // A delete here or a sync can take the item away.
        .onChange(of: larder.view) {
            if larder.view?.item(item.id) == nil { dismiss() }
        }
    }

    /// Sends the change as soon as it is picked. None sends `""`.
    private var usualStore: Binding<String> {
        Binding(
            get: { current.defaultStoreId ?? "" },
            set: { store in
                guard store != current.defaultStoreId ?? "" else { return }
                saveFailure = announced(larder.failureSaving([Op(.itemUpdate, id: item.id, defaultStoreId: store)]))
            }
        )
    }

    private func categories(of store: Store) -> [PocketLarderKit.Category] {
        larder.view.map { categoriesInOrder(of: store.id, in: $0) } ?? []
    }

    /// The item's category in `store`, sent as soon as it is picked.
    private func category(in store: Store) -> Binding<String> {
        let placed = larder.view?.placement(item: item.id, store: store.id)?.categoryId
        return Binding(
            get: { placed ?? "" },
            set: { category in
                guard category != "", category != placed else { return }
                saveFailure = announced(larder.failureSaving([Op(.itemPlace, id: item.id, storeId: store.id, categoryId: category)]))
            }
        )
    }

    /// A name equal to the current one only ends the editing.
    private func rename() {
        nameFocused = false
        guard let cleanName, cleanName != current.name else { return }
        saveFailure = announced(larder.failureSaving([Op(.itemUpdate, id: item.id, name: cleanName)]))
        if saveFailure == nil { name = cleanName }
    }
}
