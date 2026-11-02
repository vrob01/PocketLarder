import PocketLarderKit
import SwiftUI

/// The first notice, or a change that couldn't be saved. It sits outside the list, so it never covers an entry.
struct NoticeBanner: View {
    let larder: Larder
    @Binding var saveFailure: String?
    /// Goes up with every dismissal, so that two equal notices in a row each get their own time.
    @State private var dismissals = 0

    private struct Turn: Hashable {
        let dismissals: Int
        let text: String?
    }

    private var text: String? {
        saveFailure ?? larder.notices.first.map(noticeText)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let text {
                Button {
                    dismiss()
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "info.circle").accessibilityHidden(true)
                        Text(text).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.footnote)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .frame(minHeight: 44)
                    .background(Color(.secondarySystemBackground))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("main.notice")
            }
        }
        .task(id: Turn(dismissals: dismissals, text: text)) {
            guard let text else { return }
            AccessibilityNotification.Announcement(text).post()
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled { dismiss() }
        }
    }

    private func dismiss() {
        if saveFailure != nil {
            saveFailure = nil
        } else {
            larder.dismissNotice()
        }
        dismissals += 1
    }
}

func noticeText(_ n: Notice) -> String {
    switch n {
    case let .listHidden(ownerName, lostChanges):
        let hidden = String(localized: "\(ownerName)'s list is now hidden, so it's no longer on this iPhone.")
        return lostChanges ? hidden + String(localized: " Your recent changes to it weren't saved.") : hidden
    case let .listReadOnly(ownerName):
        return String(localized: "\(ownerName)'s list is now read-only. Your recent changes to it weren't saved.")
    case let .renameConflict(from, to):
        return String(localized: "Couldn't rename \"\(from)\" to \"\(to)\": that item already exists.")
    }
}

func saveFailedText(_ error: any Error) -> String {
    String(localized: "Couldn't save this change on this iPhone: \(error.localizedDescription)")
}

extension Larder {
    /// Every change goes through here. Nil when it is saved, otherwise the text to show, and then nothing has changed.
    func failureSaving(_ ops: [Op]) -> String? {
        do {
            try perform(ops)
            return nil
        } catch {
            return saveFailedText(error)
        }
    }
}
