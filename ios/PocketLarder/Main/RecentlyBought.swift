import PocketLarderKit
import SwiftUI

/// Sits at the end of both layouts, so its rows stay plain views that a `List` or a `VStack` can lay out.
struct RecentlyBought: View {
    let entries: [Entry]
    let view: Snapshot
    let onPutBack: (Entry) -> Void
    @State private var expanded = false

    var body: some View {
        if !entries.isEmpty {
            Button {
                expanded.toggle()
            } label: {
                HStack {
                    Text("Recently bought (\(entries.count))")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").accessibilityHidden(true)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? Text("Expanded") : Text("Collapsed"))
            .accessibilityIdentifier("main.recentlyBought")

            if expanded {
                ForEach(entries) { entry in
                    row(entry)
                }
            }
        }
    }

    @ViewBuilder private func row(_ entry: Entry) -> some View {
        let label = HStack(spacing: 10) {
            Image(systemName: "checkmark.circle").foregroundStyle(.secondary).accessibilityHidden(true)
            EntryLabel(entry: entry, tag: PocketLarderKit.tag(for: entry, in: view))
        }
        // Read-only lists show the entry and offer nothing, because the server would refuse a put-back.
        if view.list(entry.listId)?.writable == true {
            Button {
                onPutBack(entry)
            } label: {
                label
            }
            .buttonStyle(.plain)
            .accessibilityHint("Put back")
            .accessibilityIdentifier("bought.entry")
        } else {
            label
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("bought.readOnly")
        }
    }
}
