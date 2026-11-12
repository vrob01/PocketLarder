import PocketLarderKit
import SwiftUI

struct OfflineBadge: View {
    let larder: Larder
    let host: String
    @State private var showingDetails = false

    var body: some View {
        if larder.isOffline, let failure = larder.lastSyncFailure {
            Button {
                showingDetails = true
            } label: {
                Image(systemName: "icloud.slash")
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Can't sync")
            .accessibilityIdentifier("main.offline")
            .popover(isPresented: $showingDetails) {
                let text = offlineText(failure: failure, host: host, pending: larder.pending.count)
                // The bubble takes the text's height at this width, and scrolls only when the screen is too short for it.
                ViewThatFits(in: .vertical) {
                    details(text)
                    ScrollView { details(text) }
                }
                .presentationCompactAdaptation(.popover)
            }
        }
    }

    private func details(_ text: String) -> some View {
        Text(text)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: 280, alignment: .leading)
            .padding()
            .accessibilityIdentifier("main.offlineText")
    }
}

/// What failed and how many changes are waiting. It advises no fix, because the failure doesn't say which one applies.
func offlineText(failure: APIError, host: String, pending: Int) -> String {
    let waiting = pending == 0
        ? String(localized: "No changes are waiting to be sent.")
        : String(localized: "\(pending) changes are waiting to be sent.")
    return failureText(failure, host: host) + " " + waiting
}

/// What failed when the app asked `host` for something.
func failureText(_ failure: APIError, host: String) -> String {
    switch failure {
    case .offline: String(localized: "Can't reach \(host).")
    case .server(code: "rate_limited"): String(localized: "\(host) limited this iPhone's requests: too many in the past minute.")
    case .server(code: "too_many_invites"): String(localized: "This member already has the most open invites \(host) allows. An invite stops counting once it's used, cancelled or 24 hours old.")
    case let .server(code): String(localized: "\(host) answered with error code \(code).")
    case let .unexpected(status): String(localized: "\(host) answered with HTTP status \(status).")
    }
}
