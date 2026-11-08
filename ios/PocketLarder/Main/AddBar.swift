import PocketLarderKit
import SwiftUI

struct AddBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let view: Snapshot?
    /// Nil while the bar is disabled.
    let target: ListInfo?
    let readOnlyText: String?
    @Binding var text: String
    let focused: FocusState<Bool>.Binding
    /// Return and the target's name both add through here.
    let onAdd: (String) -> Void

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
                // A multi-line field, because Return in a single-line one closes the keyboard, even when focus is set
                // again at once, and adding several things in a row needs it to stay.
                TextField("Add item…", text: $text, axis: .vertical)
                    .lineLimit(1...3)
                    .onChange(of: text) {
                        guard text.contains(where: \.isNewline) else { return }
                        let line = text.split(whereSeparator: \.isNewline).joined(separator: " ")
                        text = line
                        onAdd(line)
                    }
                    .focused(focused)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(minHeight: 44)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                    .disabled(target == nil)
                    .accessibilityIdentifier("main.addField")
                if readOnlyText == nil {
                    targetButton
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

    /// The name adds like Return, and only the arrow opens the list picker.
    private var targetButton: some View {
        let accessibilitySize = dynamicTypeSize.isAccessibilitySize
        return HStack(spacing: 0) {
            Button {
                onAdd(text)
            } label: {
                Text(targetName)
                    .lineLimit(1)
                    .foregroundStyle(Color(.systemBackground))
                    .padding(.horizontal, 10)
                    // Three to four times the arrow's width, so that it's the part a thumb finds, and the field keeps
                    // the rest.
                    .frame(minWidth: accessibilitySize ? nil : 132, maxWidth: accessibilitySize ? .infinity : 176, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Adds what you typed to this list.")
            .accessibilityIdentifier("main.addToTarget")

            Menu {
                if let view {
                    ForEach(addTargets(view), id: \.id) { list in
                        Button(listName(list, in: view)) { model.addTarget = list.id }
                    }
                    // The rest of the bar keeps the keyboard up, but the list picker hides it once it opens.
                    .onAppear { focused.wrappedValue = false }
                }
            } label: {
                Text(verbatim: "▾")
                    .foregroundStyle(Color(.systemBackground))
                    .frame(minWidth: 44, minHeight: 44)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Color(.systemBackground).opacity(0.4)).frame(width: 1).padding(.vertical, 10)
                    }
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Choose list")
            .accessibilityIdentifier("main.chooseTarget")
        }
        .font(.footnote.weight(.semibold))
        // Black in light mode and white in dark mode, so that it stays visible.
        .background(Color.primary, in: RoundedRectangle(cornerRadius: 10))
        .opacity(target == nil ? 0.4 : 1)
        .disabled(target == nil)
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
