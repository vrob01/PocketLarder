import PocketLarderKit
import SwiftUI

/// The full screen for a server too old or too new for this app: the message, Refresh, and `exit` under them. Signed in
/// it replaces the whole app, and during sign-in the form.
struct IncompatibleView<Exit: View>: View {
    let incompatibility: Incompatibility
    let host: String
    /// Checks again. A compatible outcome makes the caller take this screen away.
    let refresh: @MainActor () async -> ServerCompatibility?
    @ViewBuilder let exit: () -> Exit
    @State private var refreshing = false
    /// Why the last Refresh got no outcome.
    @State private var failure: String?
    @ScaledMetric private var logoSize = 72.0

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: logoSize, height: logoSize)
                    .accessibilityHidden(true)
                Text(incompatibleText(incompatibility, host: host))
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("incompatible.message")
                if let failure {
                    Text(failure)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("incompatible.failure")
                }
                Button {
                    checkAgain()
                } label: {
                    HStack(spacing: 8) {
                        if refreshing {
                            ProgressView().tint(Color(.systemBackground))
                        }
                        Text("Refresh")
                    }
                }
                .buttonStyle(AccentButtonStyle())
                .disabled(refreshing)
                .accessibilityIdentifier("incompatible.refresh")
                exit()
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }

    private func checkAgain() {
        refreshing = true
        Task {
            let outcome = await refresh()
            failure = nil
            switch outcome {
            case let .incompatible(incompatibility):
                AccessibilityNotification.Announcement(incompatibleText(incompatibility, host: host)).post()
            case let .couldNotCheck(cause):
                let text = versionCheckFailureText(cause, host: host)
                failure = text
                AccessibilityNotification.Announcement(text).post()
            case .compatible, nil:
                break
            }
            refreshing = false
        }
    }
}

/// A full-width button of at least 44 points under the blocking screen's Refresh.
struct IncompatibleExitLabel: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
    }
}

/// The blocking screen's way out. It never syncs first, because the server can't be trusted to read this app's changes.
struct BlockedSignOutButton: View {
    @Environment(AppModel.self) private var model
    /// The number of unsent changes when the question was asked.
    @State private var confirming: Int?

    var body: some View {
        Button(role: .destructive) {
            confirming = model.larder?.pending.count ?? 0
        } label: {
            IncompatibleExitLabel(title: "Sign out of this iPhone")
        }
        .accessibilityIdentifier("incompatible.signOut")
        .alert(
            blockedSignOutText(confirming ?? 0),
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            presenting: confirming
        ) { count in
            if count > 0 {
                Button("Sign out anyway", role: .destructive) { signOut() }
            } else {
                Button("Sign out", role: .destructive) { signOut() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// The root swaps to the welcome screen.
    private func signOut() {
        Task { _ = await model.signOut(force: true) }
    }
}

/// What the blocking screen says. 0.1.0 in the 404 text is the version that added the route, whatever the minimum is.
func incompatibleText(_ incompatibility: Incompatibility, host: String) -> String {
    let update = String(localized: "Ask your admin to update the server.")
    switch incompatibility {
    case let .serverTooOld(version?):
        return String(localized: "The server at \(host) runs PocketLarder \(version.description). This app needs \(minimumServerVersion.description) or newer.") + " " + update
    case .serverTooOld(nil):
        return oldServerText(host: host) + " " + update
    case let .appTooOld(version):
        return String(localized: "The server at \(host) runs PocketLarder \(version.description), which this app doesn't support yet. Update PocketLarder from the App Store.")
    }
}

/// The 404 sentence of the blocking screen, which About shows on its own.
func oldServerText(host: String) -> String {
    String(localized: "The server at \(host) answered 404 to GET /v1/version, so it runs a PocketLarder version older than 0.1.0.")
}

/// Why a version check of `host` had no outcome: nil is a 2xx without a version.
func versionCheckFailureText(_ failure: APIError?, host: String) -> String {
    guard let failure else {
        return String(localized: "\(host) answered GET /v1/version, but not with a version of the form MAJOR.MINOR.PATCH.")
    }
    return failureText(failure, host: host)
}

/// The blocking screen's sign-out question.
func blockedSignOutText(_ unsentChanges: Int) -> String {
    unsentChanges > 0 ? unsentChangesText(unsentChanges) : String(localized: "Sign out of this iPhone? This deletes everything on this iPhone.")
}
