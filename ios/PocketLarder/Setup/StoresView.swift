import PocketLarderKit
import SwiftUI

/// Stores in the order you shop, and the catalog of items, from the switcher's "Stores & items…".
struct StoresView: View {
    @Environment(\.dismiss) private var dismiss
    let larder: Larder
    @State private var segment = Segment.stores
    @State private var openStore: Store?
    @State private var addingStore = false
    @State private var saveFailure: String?

    private enum Segment {
        case stores, items
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Stores & items", selection: $segment) {
                    Text("Stores").tag(Segment.stores)
                    Text("Items").tag(Segment.items)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.large)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                switch segment {
                case .stores: storeList
                case .items: ItemsView(larder: larder)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Stores & items")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(item: $openStore) { StoreDetailView(larder: larder, store: $0) }
        }
        .sheet(isPresented: $addingStore) {
            NameForm("New store") { larder.failureSaving([Op(.storeCreate, id: newID(), name: $0)]) }
        }
    }

    private var storeList: some View {
        let view = larder.view
        let stores = view.map(storesInOrder) ?? []
        return List {
            Section {
                ForEach(stores, id: \.id) { store in
                    Button {
                        openStore = store
                    } label: {
                        StoreLabel(name: store.name, count: view.map { categoriesInOrder(of: store.id, in: $0).count } ?? 0)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("stores.store")
                }
                .onMove { from, to in
                    var ids = stores.map(\.id)
                    ids.move(fromOffsets: from, toOffset: to)
                    guard ids != stores.map(\.id) else { return }
                    saveFailure = announced(larder.failureSaving([Op(.storeReorder, ids: ids)]))
                }
                Button {
                    addingStore = true
                } label: {
                    Label("Add store", systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle().inset(by: -11))
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("stores.add")
            } header: {
                Text("In the order you shop")
            } footer: {
                Text("Drag ≡ to match your round trip. Tap a store to rename it, delete it, or sort its categories the way you walk through it. Deleting a store keeps its entries under \"Not filed yet\".")
            }
            if let saveFailure {
                Section {
                    Text(saveFailure).accessibilityIdentifier("stores.saveFailure")
                }
            }
        }
        .listStyle(.insetGrouped)
        // Always editing, so that the drag handles show as in the mockup. Buttons with their own style still take taps.
        .environment(\.editMode, .constant(.active))
    }
}

/// A store's name with its category count beside it, or under it when they don't fit on one line.
private struct StoreLabel: View {
    let name: String
    let count: Int

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 6) { content }
            VStack(alignment: .leading, spacing: 2) { content }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // 44 points high without making the row taller.
        .contentShape(Rectangle().inset(by: -11))
    }

    @ViewBuilder private var content: some View {
        Text(name)
        Text("\(count) categories").font(.footnote).foregroundStyle(.secondary)
    }
}

/// A sheet with one name field. `save` sends the change for the cleaned name and returns `failureSaving`'s text.
struct NameForm: View {
    @Environment(\.dismiss) private var dismiss
    let title: LocalizedStringKey
    let current: String?
    let save: @MainActor (String) -> String?
    @State private var name: String
    @State private var saveFailure: String?

    init(_ title: LocalizedStringKey, current: String? = nil, save: @escaping @MainActor (String) -> String?) {
        self.title = title
        self.current = current
        self.save = save
        _name = State(initialValue: current ?? "")
    }

    private var cleanName: String? { cleanText(name, max: Limit.name) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .submitLabel(.done)
                        .onSubmit { submit() }
                        .accessibilityIdentifier("name.field")
                }
                if let saveFailure {
                    Section {
                        Text(saveFailure).accessibilityIdentifier("name.saveFailure")
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("name.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { submit() }
                        .disabled(cleanName == nil)
                        .accessibilityIdentifier("name.save")
                }
            }
        }
    }

    private func submit() {
        guard let cleanName else { return }
        guard cleanName != current else {
            dismiss()
            return
        }
        saveFailure = announced(save(cleanName))
        if saveFailure == nil { dismiss() }
    }
}

/// Tells VoiceOver about a change that couldn't be saved, and hands the text on to show.
@MainActor func announced(_ failure: String?) -> String? {
    if let failure {
        AccessibilityNotification.Announcement(failure).post()
    }
    return failure
}

/// The stores in the order you shop.
func storesInOrder(_ view: Snapshot) -> [Store] {
    view.stores.sorted { ($0.position, $0.id) < ($1.position, $1.id) }
}

/// A store's categories in the order you walk through it.
func categoriesInOrder(of storeId: String, in view: Snapshot) -> [PocketLarderKit.Category] {
    view.categories.filter { $0.storeId == storeId }.sorted { ($0.position, $0.id) < ($1.position, $1.id) }
}
