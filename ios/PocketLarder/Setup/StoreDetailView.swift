import PocketLarderKit
import SwiftUI

/// One store: its name, its categories in the order you walk through it, and deleting it.
struct StoreDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let larder: Larder
    let store: Store
    @State private var name: String
    @State private var sheet: CategorySheet?
    @State private var deleting = false
    @State private var saveFailure: String?
    @FocusState private var nameFocused: Bool

    private enum CategorySheet: Identifiable {
        case add
        case rename(PocketLarderKit.Category)

        var id: String {
            switch self {
            case .add: ""
            case let .rename(category): category.id
            }
        }
    }

    init(larder: Larder, store: Store) {
        self.larder = larder
        self.store = store
        _name = State(initialValue: store.name)
    }

    /// The store as it is now, so that a sync's changes show.
    private var current: Store { larder.view?.store(store.id) ?? store }
    private var cleanName: String? { cleanText(name, max: Limit.name) }

    var body: some View {
        let categories = larder.view.map { categoriesInOrder(of: store.id, in: $0) } ?? []
        List {
            Section("Name") {
                HStack {
                    TextField("Name", text: $name)
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .onSubmit { rename() }
                        .accessibilityIdentifier("store.name")
                    Button {
                        rename()
                    } label: {
                        // 44 points high without making the row taller, here and on the rows below.
                        Text("Save").contentShape(Rectangle().inset(by: -11))
                    }
                    .buttonStyle(.borderless)
                    .disabled(cleanName == nil)
                    .accessibilityIdentifier("store.save")
                }
            }
            Section("Categories") {
                ForEach(categories, id: \.id) { category in
                    Button {
                        sheet = .rename(category)
                    } label: {
                        Text(category.name)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle().inset(by: -11))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("store.category")
                }
                .onMove { from, to in
                    var ids = categories.map(\.id)
                    ids.move(fromOffsets: from, toOffset: to)
                    guard ids != categories.map(\.id) else { return }
                    saveFailure = announced(larder.failureSaving([Op(.categoryReorder, storeId: store.id, ids: ids)]))
                }
                .onDelete { offsets in
                    for id in offsets.map({ categories[$0].id }) {
                        saveFailure = announced(larder.failureSaving([Op(.categoryDelete, id: id)]))
                    }
                }
                Button {
                    sheet = .add
                } label: {
                    Label("Add category", systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle().inset(by: -11))
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("store.addCategory")
            }
            if let saveFailure {
                Section {
                    Text(saveFailure).accessibilityIdentifier("store.saveFailure")
                }
            }
            Section {
                Button(role: .destructive) {
                    deleting = true
                } label: {
                    Text("Delete store")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle().inset(by: -11))
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("store.delete")
            }
        }
        .listStyle(.insetGrouped)
        // Always editing, so that the drag handles and Delete show. Buttons with their own style still take taps.
        .environment(\.editMode, .constant(.active))
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.inline)
        .alert(Text("Delete \(current.name)? Its categories go too. Entries filed there move to Not filed yet."), isPresented: $deleting) {
            Button("Delete", role: .destructive) {
                saveFailure = announced(larder.failureSaving([Op(.storeDelete, id: store.id)]))
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .add:
                NameForm("New category") {
                    larder.failureSaving([Op(.categoryCreate, id: newID(), storeId: store.id, name: $0)])
                }
            case let .rename(category):
                NameForm("Rename category", current: category.name) {
                    larder.failureSaving([Op(.categoryRename, id: category.id, name: $0)])
                }
            }
        }
        // A delete here or a sync can take the store away.
        .onChange(of: larder.view) {
            if larder.view?.store(store.id) == nil { dismiss() }
        }
    }

    /// A name equal to the current one only ends the editing.
    private func rename() {
        nameFocused = false
        guard let cleanName, cleanName != current.name else { return }
        saveFailure = announced(larder.failureSaving([Op(.storeRename, id: store.id, name: cleanName)]))
        if saveFailure == nil { name = cleanName }
    }
}
