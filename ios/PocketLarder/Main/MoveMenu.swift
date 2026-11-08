import PocketLarderKit
import SwiftUI

extension AppModel {
    /// Entries can move once the household has a store to move them to.
    var hasStores: Bool { larder?.view?.stores.isEmpty == false }
}

/// The ⇄ chip at the edge of an entry: a menu of stores to move it to. `asking` opens the same choice as a dialog, for VoiceOver.
struct MoveMenu: View {
    @Environment(AppModel.self) private var model
    let entry: Entry
    @Binding var asking: Bool
    @State private var picking: Store?
    @State private var saveFailure: String?

    var body: some View {
        if let larder = model.larder, let view = larder.view, !view.stores.isEmpty {
            let stores = storesInOrder(view)
            let checked = isFiled(entry, in: view) ? entry.storeId : nil
            Menu {
                ForEach(stores, id: \.id) { store in
                    Button {
                        choose(store, checked: checked, larder: larder, view: view)
                    } label: {
                        if store.id == checked {
                            Label(store.name, systemImage: "checkmark")
                        } else {
                            Text(store.name)
                        }
                    }
                    // A menu passes no tap to the screen's gesture, so the keyboard is hidden from here.
                    .onAppear { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                }
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32, height: 28)
                    .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Move \(entry.text) to another store")
            .accessibilityIdentifier("entry.move")
            .confirmationDialog("Move \(entry.text) to…", isPresented: $asking, titleVisibility: .visible) {
                ForEach(stores, id: \.id) { store in
                    Button(store.id == checked ? "✓ \(store.name)" : store.name) {
                        choose(store, checked: checked, larder: larder, view: view)
                    }
                }
            }
            .sheet(isPresented: Binding(get: { picking != nil }, set: { if !$0 { picking = nil } })) {
                if let picking { CategoryPicker(larder: larder, entry: entry, store: picking) }
            }
            .alert("Couldn't move \(entry.text)", isPresented: Binding(get: { saveFailure != nil }, set: { if !$0 { saveFailure = nil } })) {
                Button("OK") {}
            } message: {
                Text(saveFailure ?? "")
            }
        }
    }

    private func choose(_ store: Store, checked: String?, larder: Larder, view: Snapshot) {
        guard store.id != checked else { return }
        switch move(entry, to: store.id, in: view) {
        case let .place(op): saveFailure = larder.failureSaving([op])
        case .needsCategory: picking = store
        }
    }
}
