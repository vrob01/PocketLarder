import PocketLarderKit
import SwiftUI

/// The app's version and build, and the server's version, asked for each time the page opens. It never blocks or
/// unblocks the app.
struct AboutView: View {
    @Environment(AppModel.self) private var model
    @State private var outcome: ServerCompatibility?

    private var host: String { model.account?.server.host() ?? "" }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "") (\(info?["CFBundleVersion"] as? String ?? ""))"
    }

    var body: some View {
        List {
            Section("App") {
                row("Version", appVersion)
                    .accessibilityIdentifier("about.app")
            }
            Section("Server") {
                row("Address", host)
                    .accessibilityIdentifier("about.server")
                serverVersion
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .task { outcome = await model.client?.serverVersion() }
    }

    /// The version whenever the answer had one, compatible or not, and otherwise why there is none.
    @ViewBuilder private var serverVersion: some View {
        switch outcome {
        case nil:
            HStack {
                Text("Version")
                Spacer()
                ProgressView()
            }
            .accessibilityElement(children: .combine)
        case let .compatible(version), let .incompatible(.serverTooOld(version?)), let .incompatible(.appTooOld(version)):
            row("Version", version.description)
                .accessibilityIdentifier("about.serverVersion")
        case .incompatible(.serverTooOld(nil)):
            Text(oldServerText(host: host))
                .accessibilityIdentifier("about.serverVersion")
        case let .couldNotCheck(cause):
            Text(versionCheckFailureText(cause, host: host))
                .accessibilityIdentifier("about.serverVersion")
        }
    }

    private func row(_ title: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(verbatim: value).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
