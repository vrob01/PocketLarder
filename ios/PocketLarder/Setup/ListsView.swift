import PocketLarderKit
import SwiftUI

/// The shared lists, from the switcher's "Lists…": create, rename, recolor, archive and restore.
struct ListsView: View {
    @Environment(\.dismiss) private var dismiss
    let larder: Larder
    @State private var sheet: ListSheet?
    @State private var saveFailure: String?

    private enum ListSheet: Identifiable {
        case add
        case edit(ListInfo)

        var id: String {
            switch self {
            case .add: ""
            case let .edit(list): list.id
            }
        }
    }

    var body: some View {
        let shared = (larder.view?.lists ?? [])
            .filter { $0.ownerId == nil }
            .sorted { (fold($0.name ?? ""), $0.id) < (fold($1.name ?? ""), $1.id) }
        let archived = shared.filter(\.archived)
        NavigationStack {
            List {
                Section {
                    ForEach(shared.filter { !$0.archived }, id: \.id) { list in
                        Button {
                            sheet = .edit(list)
                        } label: {
                            ListLabel(list: list)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("lists.list")
                    }
                    Button {
                        sheet = .add
                    } label: {
                        Label("Add list", systemImage: "plus")
                    }
                    .accessibilityIdentifier("lists.add")
                }
                if !archived.isEmpty {
                    Section {
                        ForEach(archived, id: \.id) { list in
                            HStack {
                                ListLabel(list: list)
                                Spacer()
                                Button {
                                    saveFailure = announced(larder.failureSaving([Op(.listUpdate, id: list.id, archived: false)]))
                                } label: {
                                    Text("Restore").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                                }
                                .buttonStyle(.borderless)
                                .accessibilityIdentifier("lists.restore")
                            }
                        }
                    } header: {
                        Text("Archived").accessibilityIdentifier("lists.archived")
                    }
                }
                if let saveFailure {
                    Section {
                        Text(saveFailure).accessibilityIdentifier("lists.saveFailure")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Lists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .add: ListForm(larder: larder, list: nil)
            case let .edit(list): ListForm(larder: larder, list: list)
            }
        }
    }
}

/// The list's color dot next to its name, so that the color is never the only signal.
private struct ListLabel: View {
    let list: ListInfo

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "circle.fill")
                .font(.caption)
                .foregroundStyle(list.color.map { Color($0) } ?? Color.secondary)
                .accessibilityHidden(true)
            Text(list.name ?? "")
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(list.color.map(colorName) ?? "")
    }
}

/// A new shared list, or one to rename, recolor or archive.
private struct ListForm: View {
    @Environment(\.dismiss) private var dismiss
    let larder: Larder
    let list: ListInfo?
    @State private var name: String
    @State private var color: ListColor
    @State private var saveFailure: String?

    init(larder: Larder, list: ListInfo?) {
        self.larder = larder
        self.list = list
        _name = State(initialValue: list?.name ?? "")
        _color = State(initialValue: list?.color ?? .teal)
    }

    private var cleanName: String? { cleanText(name, max: Limit.name) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .submitLabel(.done)
                        .onSubmit { save() }
                        .accessibilityIdentifier("list.name")
                }
                Section("Color") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 4)], spacing: 4) {
                        ForEach(ListColor.allCases, id: \.self) { token in
                            swatch(token)
                        }
                    }
                }
                if let saveFailure {
                    Section {
                        Text(saveFailure).accessibilityIdentifier("list.saveFailure")
                    }
                }
                if let list {
                    Section {
                        Button("Archive") {
                            saveFailure = announced(larder.failureSaving([Op(.listUpdate, id: list.id, archived: true)]))
                        }
                        .accessibilityIdentifier("list.archive")
                    }
                }
            }
            .navigationTitle(list?.name ?? String(localized: "New list"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("list.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(cleanName == nil)
                        .accessibilityIdentifier("list.save")
                }
            }
        }
        // Archiving here or a sync takes the list off the active ones.
        .onChange(of: larder.view) {
            if let list, larder.view?.list(list.id)?.archived != false { dismiss() }
        }
    }

    /// The chosen color has a checkmark, so that it doesn't show by color alone.
    private func swatch(_ token: ListColor) -> some View {
        let chosen = token == color
        return Button {
            color = token
        } label: {
            Circle()
                .fill(Color(token))
                .frame(width: 30, height: 30)
                .overlay {
                    if chosen {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(.systemBackground))
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(colorName(token))
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityIdentifier("list.color.\(token.rawValue)")
    }

    /// Only what changed, so that a rename can't undo another phone's recolor.
    private func save() {
        guard let cleanName else { return }
        let failure: String?
        if let list {
            let newName = cleanName == list.name ? nil : cleanName
            let newColor = color == list.color ? nil : color
            guard newName != nil || newColor != nil else {
                dismiss()
                return
            }
            failure = larder.failureSaving([Op(.listUpdate, id: list.id, name: newName, color: newColor)])
        } else {
            failure = larder.failureSaving([Op(.listCreate, id: newID(), name: cleanName, color: color)])
        }
        saveFailure = announced(failure)
        if saveFailure == nil { dismiss() }
    }
}

private func colorName(_ token: ListColor) -> String {
    switch token {
    case .red: String(localized: "Red")
    case .orange: String(localized: "Orange")
    case .yellow: String(localized: "Yellow")
    case .green: String(localized: "Green")
    case .teal: String(localized: "Teal")
    case .blue: String(localized: "Blue")
    case .purple: String(localized: "Purple")
    case .pink: String(localized: "Pink")
    case .gray: String(localized: "Gray")
    }
}
