import PocketLarderKit
import SwiftUI

struct StoreChips: View {
    let stores: [Store]
    @Binding var filter: StoreFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(Text("All"), .all, identifier: "chip.all")
                ForEach(stores, id: \.id) { store in
                    chip(Text(store.name), .store(store.id), identifier: "chip.\(store.name)")
                }
            }
            .padding(.horizontal, 14)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    private func chip(_ title: Text, _ value: StoreFilter, identifier: String) -> some View {
        let selected = filter == value
        return Button {
            filter = value
        } label: {
            title
                .font(.footnote)
                .foregroundStyle(selected ? Color(.systemBackground) : Color.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(selected ? Color.primary : Color(.secondarySystemBackground), in: Capsule())
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}
