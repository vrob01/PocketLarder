import PocketLarderKit
import SwiftUI

struct AddBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var focused: Bool
    let view: Snapshot?
    /// Nil while the bar is disabled.
    let target: ListInfo?
    let readOnlyText: String?
    @Binding var text: String
    let onReturn: () -> Void

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        VStack(alignment: .leading, spacing: 6) {
            if let readOnlyText {
                Text(readOnlyText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("main.readOnly")
            }
            layout {
                TextField("Add item…", text: $text)
                    .focused($focused)
                    .onSubmit {
                        onReturn()
                        // Return would otherwise close the keyboard, and adding several things in a row needs it.
                        focused = true
                    }
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                    .disabled(target == nil)
                    .accessibilityIdentifier("main.addField")
                if readOnlyText == nil {
                    targetMenu
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Divider() }
    }

    private var targetName: String {
        if let view, let target { return listName(target, in: view) }
        return String(localized: "My list")
    }

    private var targetMenu: some View {
        Menu {
            if let view {
                ForEach(addTargets(view), id: \.id) { list in
                    Button(listName(list, in: view)) { model.addTarget = list.id }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(targetName).lineLimit(1)
                Text(verbatim: "▾").accessibilityHidden(true)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color(.systemBackground))
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            // Black in light mode and white in dark mode, so that it stays visible.
            .background(Color.primary, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
            .opacity(target == nil ? 0.4 : 1)
        }
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? nil : 160)
        .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
        .disabled(target == nil)
        .accessibilityIdentifier("main.addTarget")
    }
}

/// The catalog matches, above the add bar. It scrolls only when they don't fit.
struct SuggestionList: View {
    let suggestions: [Suggestion]
    let onPick: (Item) -> Void

    var body: some View {
        ViewThatFits(in: .vertical) {
            column
            ScrollView { column }
        }
        .background(Color(.secondarySystemBackground))
    }

    private var column: some View {
        VStack(spacing: 0) {
            ForEach(suggestions, id: \.item.id) { suggestion in
                Button {
                    onPick(suggestion.item)
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        Text(suggestion.item.name)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text([suggestion.store?.name, suggestion.category?.name].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("main.suggestion")
                Divider()
            }
        }
    }
}
