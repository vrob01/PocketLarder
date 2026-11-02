import PocketLarderKit
import SwiftUI

struct EditEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    let larder: Larder
    let entry: Entry
    @State private var quantity: String
    @State private var note: String
    @State private var saveFailure: String?

    init(larder: Larder, entry: Entry) {
        self.larder = larder
        self.entry = entry
        _quantity = State(initialValue: entry.quantity)
        _note = State(initialValue: entry.note)
    }

    private var cleanQuantity: String? { fieldValue(quantity, max: Limit.quantity) }
    private var cleanNote: String? { fieldValue(note, max: Limit.note) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Quantity") {
                        TextField("Quantity", text: $quantity)
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("entry.quantity")
                    }
                    LabeledContent("Note") {
                        TextField("Note", text: $note)
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("entry.note")
                    }
                }
                if let saveFailure {
                    Section {
                        Text(saveFailure).accessibilityIdentifier("entry.saveFailure")
                    }
                }
                Section {
                    Button("Delete", role: .destructive) {
                        finish(Op(.entryDelete, id: entry.id))
                    }
                    .accessibilityIdentifier("entry.delete")
                }
            }
            .navigationTitle(entry.text)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("entry.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(cleanQuantity == nil || cleanNote == nil)
                        .accessibilityIdentifier("entry.save")
                }
            }
        }
    }

    /// Only what changed, so that an edit of one field can't undo another phone's edit of the other.
    private func save() {
        guard let cleanQuantity, let cleanNote else { return }
        let newQuantity = cleanQuantity == entry.quantity ? nil : cleanQuantity
        let newNote = cleanNote == entry.note ? nil : cleanNote
        guard newQuantity != nil || newNote != nil else {
            dismiss()
            return
        }
        finish(Op(.entryUpdate, id: entry.id, quantity: newQuantity, note: newNote))
    }

    private func finish(_ op: Op) {
        saveFailure = larder.failureSaving([op])
        if let saveFailure {
            AccessibilityNotification.Announcement(saveFailure).post()
        } else {
            dismiss()
        }
    }
}

/// What a field sends: `""` for a blank value, otherwise the cleaned text, and nil when that fails cleaning.
private func fieldValue(_ value: String, max: Int) -> String? {
    value.unicodeScalars.allSatisfy(\.properties.isWhitespace) ? "" : cleanText(value, max: max)
}
