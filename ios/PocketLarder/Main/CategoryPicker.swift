import PocketLarderKit
import SwiftUI

/// The sheet that asks which category of a store an entry goes under, or makes a new one.
struct CategoryPicker: View {
    @Environment(\.dismiss) private var dismiss
    let larder: Larder
    let entry: Entry
    let store: Store
    @State private var addingCategory = false
    @State private var saveFailure: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(larder.view.map { categoriesInOrder(of: store.id, in: $0) } ?? [], id: \.id) { category in
                        Button(category.name) { choose(category) }
                            .accessibilityIdentifier("picker.category")
                    }
                    Button("New category…") { addingCategory = true }
                        .accessibilityIdentifier("picker.newCategory")
                }
                if let saveFailure {
                    Section {
                        Text(saveFailure).accessibilityIdentifier("picker.saveFailure")
                    }
                }
            }
            .navigationTitle("Where in \(store.name)?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("picker.cancel")
                }
            }
            .sheet(isPresented: $addingCategory) {
                NameForm("New category") { name in
                    guard let view = larder.view else { return nil }
                    let id = newID()
                    guard case let .place(place) = move(entry, to: store.id, category: id, in: view) else { return nil }
                    let failure = larder.failureSaving([Op(.categoryCreate, id: id, storeId: store.id, name: name), place])
                    if failure == nil { dismiss() }
                    return failure
                }
            }
        }
        .onChange(of: larder.view?.store(store.id) == nil) { _, gone in
            if gone { dismiss() }
        }
    }

    private func choose(_ category: PocketLarderKit.Category) {
        guard let view = larder.view, case let .place(op) = move(entry, to: store.id, category: category.id, in: view) else { return }
        saveFailure = announced(larder.failureSaving([op]))
        if saveFailure == nil { dismiss() }
    }
}
