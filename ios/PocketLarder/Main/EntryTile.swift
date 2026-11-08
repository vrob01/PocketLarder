import PocketLarderKit
import SwiftUI

struct EntryTile: View {
    @Environment(AppModel.self) private var model
    let entry: Entry
    let tag: ListInfo?
    let actions: EntryActions?
    let highlighted: Bool

    private var detail: String {
        [entry.quantity, entry.note].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        if let actions {
            ZStack(alignment: .topTrailing) {
                Button(action: actions.crossOff) {
                    content
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Edit", action: actions.edit)
                    Button("Delete", role: .destructive, action: actions.delete)
                }
                .accessibilityHint("Cross off")
                .accessibilityAction(named: "Cross off", actions.crossOff)
                .accessibilityAction(named: "Edit", actions.edit)
                .accessibilityAction(named: "Delete", actions.delete)
                .accessibilityIdentifier("entry.tile")

                MoveMenu(entry: entry, asking: .constant(false))
            }
        } else {
            content
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("entry.readOnly")
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 2) {
            EntryTitle(entry: entry, tag: tag)
            if !detail.isEmpty {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 9)
        .padding(.trailing, actions != nil && model.hasStores ? 44 : 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(highlighted ? Color.accentColor.opacity(0.2) : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}
