import PocketLarderKit
import SwiftUI

/// The capsule at the top left: what's on screen, and the menu that changes it.
struct ListSwitcher: View {
    @Environment(AppModel.self) private var model
    let view: Snapshot?
    let onOpen: () -> Void
    @State private var showingLists = false
    @State private var showingStores = false

    private var name: String {
        guard case let .list(id) = model.scope, let view, let list = view.list(id) else {
            return String(localized: "My view")
        }
        return listName(list, in: view)
    }

    var body: some View {
        Menu {
            Button("My view") { model.scope = .myView }
                // A menu passes no tap to the screen's gesture, so the screen learns of the opening from here.
                .onAppear(perform: onOpen)
            if let view {
                ForEach(switcherLists(view), id: \.id) { list in
                    Button {
                        model.scope = .list(list.id)
                    } label: {
                        label(list, in: view)
                    }
                    .accessibilityLabel(list.writable ? listName(list, in: view) : String(localized: "\(listName(list, in: view)), read-only"))
                }
            }
            Section {
                Button("Lists…") { showingLists = true }
                Button("Stores & items…") { showingStores = true }
            }
        } label: {
            HStack(spacing: 6) {
                Text(name).font(.headline).lineLimit(2)
                Text(verbatim: "▼").font(.caption2).accessibilityHidden(true)
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.15), in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("main.switcher")
        .sheet(isPresented: $showingLists) {
            if let larder = model.larder { ListsView(larder: larder) }
        }
        .sheet(isPresented: $showingStores) {
            if let larder = model.larder { StoresView(larder: larder) }
        }
    }

    @ViewBuilder private func label(_ list: ListInfo, in view: Snapshot) -> some View {
        if let color = list.color {
            Label {
                Text(listName(list, in: view))
            } icon: {
                Image(dot: color)
            }
        } else if list.writable {
            Text(listName(list, in: view))
        } else {
            Label(listName(list, in: view), systemImage: "lock.fill")
        }
    }
}

/// "My list", the shared list's name, or "Sam's list".
func listName(_ list: ListInfo, in view: Snapshot) -> String {
    if list.ownerId == view.me.memberId { return String(localized: "My list") }
    guard list.ownerId != nil else { return list.name ?? "" }
    return String(localized: "\(view.member(list.ownerId)?.name ?? "")'s list")
}
