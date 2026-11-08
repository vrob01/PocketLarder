import PocketLarderKit
import SwiftUI

struct MainView: View {
    let larder: Larder

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("layout") private var layout = "rows"
    @State private var filter = StoreFilter.all
    @State private var addText = ""
    @State private var saveFailure: String?
    @State private var editing: Entry?
    @State private var highlighted: String?
    @State private var showingAccount = false
    @FocusState private var addFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                topBar
                NoticeBanner(larder: larder, saveFailure: $saveFailure)
                StoreChips(stores: larder.view.map { chipStores($0, scope: model.scope) } ?? [], filter: $filter)
            }
            // So that the gaps between the controls take a tap too.
            .contentShape(Rectangle())
            .simultaneousGesture(hidesKeyboard)
            list
            AddBar(
                view: larder.view,
                target: target,
                readOnlyText: readOnlyText,
                text: $addText,
                focused: $addFocused,
                onAdd: { submit($0) }
            )
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingAccount) { AccountView() }
        .sheet(item: $editing) { EditEntrySheet(larder: larder, entry: $0) }
        .onChange(of: larder.view) {
            guard let view = larder.view else { return }
            model.scope = validScope(model.scope, in: view)
            keepFilterValid()
            if let editing, !view.entries.contains(where: { $0.id == editing.id }) {
                self.editing = nil
            }
        }
        .onChange(of: model.scope) { keepFilterValid() }
    }

    // MARK: Top

    private var topBar: some View {
        HStack(spacing: 8) {
            ListSwitcher(view: larder.view, onOpen: { addFocused = false })
            Spacer(minLength: 0)
            OfflineBadge(larder: larder, host: model.account?.server.host() ?? "")
            Button {
                showingAccount = true
            } label: {
                Text(verbatim: model.memberName.prefix(1).uppercased())
                    .font(.headline)
                    .foregroundStyle(Color(.systemBackground))
                    .frame(minWidth: 44, minHeight: 44)
                    .background(Color.accentColor, in: Circle())
            }
            .accessibilityLabel("My account")
            .accessibilityIdentifier("main.account")
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
    }

    private func keepFilterValid() {
        guard case let .store(id) = filter, let view = larder.view else { return }
        if !chipStores(view, scope: model.scope).contains(where: { $0.id == id }) {
            filter = .all
        }
    }

    /// Any tap above the add bar hides the keyboard and still does what it does. The suggestions and the bar keep it.
    private var hidesKeyboard: some Gesture {
        TapGesture().onEnded { addFocused = false }
    }

    // MARK: List

    private var list: some View {
        ScrollViewReader { proxy in
            Group {
                if layout == "tiles" {
                    tiles
                } else {
                    rows
                }
            }
            .refreshable { await larder.sync() }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: highlighted) {
                guard let highlighted else { return }
                // On the next turn, so that the list has taken in a scope or filter that just changed.
                Task {
                    withAnimation(reduceMotion ? nil : .default) {
                        proxy.scrollTo(highlighted, anchor: .center)
                    }
                }
            }
            .task(id: highlighted) {
                guard highlighted != nil else { return }
                try? await Task.sleep(for: .seconds(2))
                if !Task.isCancelled { highlighted = nil }
            }
        }
        .opacity(suggested.isEmpty ? 1 : 0.35)
        .simultaneousGesture(hidesKeyboard)
        .overlay(alignment: .bottom) {
            if !suggested.isEmpty {
                SuggestionList(suggestions: suggested, onPick: { pick($0) })
            }
        }
    }

    private var rows: some View {
        List {
            if let view = larder.view {
                let contents = shelf(view, scope: model.scope, filter: filter)
                if !contents.notFiled.isEmpty {
                    Section {
                        ForEach(contents.notFiled) { row($0, in: view) }
                    } header: {
                        notFiledHeader
                    }
                }
                ForEach(contents.stores, id: \.store.id) { section in
                    Section {
                        ForEach(section.groups, id: \.category.id) { group in
                            categoryHeader(group.category.name)
                                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 2, trailing: 16))
                                .listRowSeparator(.hidden)
                            ForEach(group.entries) { row($0, in: view) }
                        }
                    } header: {
                        storeHeader(section)
                    }
                }
                recentlyBought(contents, in: view)
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(0)
        .environment(\.defaultMinListRowHeight, 24)
    }

    private var tiles: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if let view = larder.view {
                    let contents = shelf(view, scope: model.scope, filter: filter)
                    if !contents.notFiled.isEmpty {
                        notFiledHeader
                        grid(contents.notFiled, in: view)
                    }
                    ForEach(contents.stores, id: \.store.id) { section in
                        storeHeader(section)
                        ForEach(section.groups, id: \.category.id) { group in
                            categoryHeader(group.category.name)
                            grid(group.entries, in: view)
                        }
                    }
                    recentlyBought(contents, in: view)
                }
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func grid(_ entries: [Entry], in view: Snapshot) -> some View {
        let columns = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6, alignment: .top), count: columns), spacing: 6) {
            ForEach(entries) { entry in
                EntryTile(
                    entry: entry,
                    tag: PocketLarderKit.tag(for: entry, in: view),
                    actions: actions(entry, in: view),
                    highlighted: highlighted == entry.id
                )
            }
        }
    }

    private func row(_ entry: Entry, in view: Snapshot) -> some View {
        EntryRow(
            entry: entry,
            tag: PocketLarderKit.tag(for: entry, in: view),
            actions: actions(entry, in: view),
            highlighted: highlighted == entry.id
        )
    }

    private func actions(_ entry: Entry, in view: Snapshot) -> EntryActions? {
        guard view.list(entry.listId)?.writable == true else { return nil }
        // Here too, because swipe actions and context menu items are out of `hidesKeyboard`'s reach.
        return EntryActions(
            crossOff: { addFocused = false; change(Op(.entryBuy, id: entry.id)) },
            edit: { addFocused = false; editing = entry },
            delete: { addFocused = false; change(Op(.entryDelete, id: entry.id)) }
        )
    }

    private func recentlyBought(_ contents: Shelf, in view: Snapshot) -> some View {
        RecentlyBought(entries: contents.recentlyBought, view: view) { change(Op(.entryUnbuy, id: $0.id)) }
    }

    private var notFiledHeader: some View {
        Text("Not filed yet")
            .font(.subheadline.bold())
            .textCase(nil)
            .foregroundStyle(Color(ListColor.orange))
            .padding(.top, 8)
            .accessibilityAddTraits(.isHeader)
    }

    private func storeHeader(_ section: StoreSection) -> some View {
        let count = section.groups.reduce(0) { $0 + $1.entries.count }
        return HStack(alignment: .firstTextBaseline) {
            Text(section.store.name)
                .font(.subheadline.bold())
                // Colors, not `.primary` and `.secondary`, which a section header would dim one step further.
                .foregroundStyle(Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(count) items")
                .font(.caption)
                .foregroundStyle(Color.secondary)
        }
        .textCase(nil)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("main.storeHeader")
    }

    private func categoryHeader(_ name: String) -> some View {
        Text(name)
            .font(.caption)
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(.secondary)
            .padding(.top, 6)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Changes

    /// False when the change couldn't be saved, and then the banner says why.
    @discardableResult private func change(_ op: Op) -> Bool {
        saveFailure = larder.failureSaving([op])
        return saveFailure == nil
    }

    private var readOnlyText: String? {
        guard case let .list(id) = model.scope, let view = larder.view, let list = view.list(id), !list.writable else {
            return nil
        }
        return String(localized: "\(view.member(list.ownerId)?.name ?? "")'s list is read-only.")
    }

    /// The list new items go to. Nil while there's no view yet or a read-only list is on screen.
    private var target: ListInfo? {
        guard let view = larder.view, readOnlyText == nil else { return nil }
        return validTarget(model.addTarget, in: view)
    }

    /// Only while the field has focus, so that no dimmed list stays under suggestions nobody is typing into.
    private var suggested: [Suggestion] {
        guard addFocused, let view = larder.view, target != nil else { return [] }
        return suggestions(view, for: addText)
    }

    private func submit(_ text: String) {
        guard let view = larder.view, let target else { return }
        finishAdding(add(text: text, to: target.id, in: view))
    }

    private func pick(_ item: Item) {
        guard let view = larder.view, let target else { return }
        finishAdding(add(item, to: target.id, in: view))
    }

    private func finishAdding(_ outcome: AddOutcome?) {
        guard let outcome else { return }
        switch outcome {
        case let .add(op):
            if change(op) { addText = "" }
        case let .existing(entry):
            addText = ""
            reveal(entry)
        }
    }

    /// Brings an entry into view, because the filter or scope may be hiding it. The add target stays what it was.
    private func reveal(_ entry: Entry) {
        filter = .all
        if let view = larder.view, !inScope(entry.listId, model.scope, in: view) {
            let addTarget = model.addTarget
            model.scope = inScope(entry.listId, .myView, in: view) ? .myView : .list(entry.listId)
            model.addTarget = addTarget
        }
        highlighted = entry.id
        AccessibilityNotification.Announcement(String(localized: "\(entry.text) is already on this list.")).post()
    }
}
