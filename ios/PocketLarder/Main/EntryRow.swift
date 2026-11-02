import PocketLarderKit
import SwiftUI

/// What a row or tile can do. Nil on a list that isn't writable, because the server would refuse all of it.
struct EntryActions {
    let crossOff: () -> Void
    let edit: () -> Void
    let delete: () -> Void
}

struct EntryRow: View {
    let entry: Entry
    let tag: ListInfo?
    let actions: EntryActions?
    let highlighted: Bool

    var body: some View {
        HStack(spacing: 0) {
            if let actions {
                Button(action: actions.crossOff) {
                    Image(systemName: "circle")
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cross off")
                .accessibilityValue(entry.text)
                .accessibilityIdentifier("entry.crossOff")

                Button(action: actions.edit) {
                    EntryLabel(entry: entry, tag: tag)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Edit")
                .accessibilityAction(named: "Cross off", actions.crossOff)
                .accessibilityAction(named: "Delete", actions.delete)
                .accessibilityIdentifier("entry.row")
            } else {
                EntryLabel(entry: entry, tag: tag)
                    .padding(.leading, 16)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("entry.readOnly")
            }
        }
        .swipeActions(edge: .trailing) {
            if let actions {
                Button("Delete", role: .destructive, action: actions.delete)
            }
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 16))
        .listRowBackground(highlighted ? Color.accentColor.opacity(0.2) : nil)
    }
}

/// An entry's text, tag, note and quantity on one row. Stacked at accessibility text sizes, so that nothing is squeezed.
struct EntryLabel: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let entry: Entry
    let tag: ListInfo?

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(spacing: 8))
        layout {
            VStack(alignment: .leading, spacing: 2) {
                EntryTitle(entry: entry, tag: tag)
                if !entry.note.isEmpty {
                    Text(entry.note).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !entry.quantity.isEmpty {
                Text(entry.quantity).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// An entry's text with its list's tag beside it, or under it when they don't fit on one line.
struct EntryTitle: View {
    let entry: Entry
    let tag: ListInfo?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { content }
            VStack(alignment: .leading, spacing: 2) { content }
        }
    }

    @ViewBuilder private var content: some View {
        Text(entry.text)
        if let tag {
            ListTag(list: tag)
        }
    }
}

/// The list's name in its color, so that the color is never the only signal.
struct ListTag: View {
    let list: ListInfo

    private var color: Color {
        list.color.map { Color($0) } ?? Color.secondary
    }

    var body: some View {
        Text(list.name ?? "")
            .font(.caption2)
            .lineLimit(1)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(color.opacity(0.15), in: Capsule())
    }
}
