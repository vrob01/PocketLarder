import PocketLarderKit
import SwiftUI

struct AccountView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage("layout") private var layout = "rows"
    @AppStorage("appearance") private var appearance = "system"
    @State private var signingOut = false
    @State private var question: String?
    @State private var creatingInvite = false
    @State private var invite: CreatedInvite?
    @State private var inviteFailure: String?
    @State private var saveFailure: String?
    /// Why turning off "Accept any certificate" wasn't saved.
    @State private var certificateFailure: String?
    /// A path, so that losing one's own admin rights can go back to My account from any page under it.
    @State private var path: [Page] = []

    private enum Page {
        case members, invites, about
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                header
                certificate
                Section("List layout") {
                    Picker("List layout", selection: $layout) {
                        Text("Rows").tag("rows")
                        Text("Tiles").tag("tiles")
                    }
                    .segmentedRow()
                    .accessibilityIdentifier("account.layout")
                }
                Section("Appearance") {
                    Picker("Appearance", selection: $appearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .segmentedRow()
                    .accessibilityIdentifier("account.appearance")
                }
                privacy
                Section("This iPhone") {
                    Button {
                        addDevice()
                    } label: {
                        HStack {
                            Text("Add a device…")
                            if creatingInvite {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(creatingInvite || signingOut)
                    .accessibilityIdentifier("account.addDevice")
                    NavigationLink("Invites", value: Page.invites)
                        .accessibilityIdentifier("account.invites")
                    Button {
                        openURL(URL(string: UIApplication.openSettingsURLString)!)
                    } label: {
                        HStack {
                            Text("Language").foregroundStyle(Color.primary)
                            Spacer()
                            Text(languageName).foregroundStyle(.secondary)
                            Image(systemName: "chevron.forward")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .accessibilityLabel("Language")
                    .accessibilityValue(languageName)
                    .accessibilityIdentifier("account.language")
                    Button(role: .destructive) {
                        signOut(force: false)
                    } label: {
                        HStack {
                            Text("Sign out")
                            if signingOut {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(creatingInvite || signingOut)
                    .accessibilityIdentifier("account.signOut")
                }
                if model.larder?.view?.me.isAdmin == true {
                    Section("Household") {
                        NavigationLink("Members & devices", value: Page.members)
                            .accessibilityIdentifier("account.members")
                    }
                }
                Section {
                    NavigationLink("About", value: Page.about)
                        .accessibilityIdentifier("account.about")
                }
            }
            .navigationDestination(for: Page.self) { page in
                switch page {
                case .members: MembersView(model: model) { path = [] }
                case .invites: InvitesView(memberId: nil, household: nil)
                case .about: AboutView()
                }
            }
            .navigationTitle("My account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .disabled(signingOut)
                }
            }
            .sheet(isPresented: Binding(get: { invite != nil }, set: { if !$0 { invite = nil } })) {
                if let invite {
                    AddDeviceSheet(invite: invite, memberName: model.memberName)
                }
            }
            .alert(
                "Couldn't create an invite.",
                isPresented: Binding(get: { inviteFailure != nil }, set: { if !$0 { inviteFailure = nil } }),
                presenting: inviteFailure
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: {
                Text($0)
            }
        }
        .interactiveDismissDisabled(signingOut)
        .alert(
            question ?? "",
            isPresented: Binding(
                get: { question != nil },
                set: { if !$0 { question = nil } }
            )
        ) {
            Button("Sign out anyway", role: .destructive) { signOut(force: true) }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// The initial, the name, an Admin badge and the server, which VoiceOver reads as one element.
    private var header: some View {
        HStack(spacing: 12) {
            Text(verbatim: model.memberName.prefix(1).uppercased())
                .font(.headline)
                .foregroundStyle(Color(.systemBackground))
                .frame(width: 44, height: 44)
                .background(Color.accentColor, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: model.memberName).font(.headline)
                    if model.larder?.view?.me.isAdmin == true {
                        AdminBadge()
                    }
                }
                Text(verbatim: model.account?.server.host() ?? "")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("account.header")
    }

    /// Only while the account accepts any certificate from its server. It can't be turned back on here.
    @ViewBuilder private var certificate: some View {
        if let account = model.account, account.acceptsAnyCertificate {
            Section {
                Label {
                    Text("Accepting any certificate from \(account.server.host() ?? "")")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color(ListColor.orange))
                }
                .accessibilityIdentifier("account.acceptAnyCertificate")
                Button("Turn off") {
                    do {
                        try model.stopAcceptingAnyCertificate()
                    } catch {
                        certificateFailure = announced(certificateSaveFailureText(error))
                    }
                }
                .accessibilityIdentifier("account.acceptAnyCertificate.off")
            } footer: {
                Text("Anyone on your network could read and change your lists. To turn it on again, sign out and sign in with a new invite.")
            }
        }
        if let certificateFailure {
            Section {
                Text(certificateFailure).accessibilityIdentifier("account.acceptAnyCertificate.saveFailure")
            }
        }
    }

    /// Left out until the first snapshot, because until then the current setting is unknown.
    @ViewBuilder private var privacy: some View {
        if let larder = model.larder, let me = larder.view?.member(model.account?.memberId) {
            Section {
                Picker("Who can see my list", selection: Binding(
                    get: { me.privacy },
                    set: { choice in
                        guard choice != me.privacy else { return }
                        saveFailure = announced(larder.failureSaving([Op(.memberSetPrivacy, privacy: choice)]))
                    }
                )) {
                    Text("Open").tag(Privacy.open)
                    Text("Read-only").tag(Privacy.readonly)
                    Text("Hidden").tag(Privacy.hidden)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Who can see my list")
            } footer: {
                Text("Hidden isn't encryption: whoever runs your server can read every list. Filing an entry puts its name in the shared catalog, where others see it in suggestions. Leave it unfiled to keep it private.")
            }
            if let saveFailure {
                Section {
                    Text(saveFailure).accessibilityIdentifier("account.saveFailure")
                }
            }
        }
    }

    /// The language the app shows, named in that language: "English", "Deutsch".
    private var languageName: String {
        let code = Bundle.main.preferredLocalizations.first ?? ""
        let locale = Locale(identifier: code)
        let name = locale.localizedString(forLanguageCode: code) ?? code
        return name.prefix(1).uppercased(with: locale) + name.dropFirst()
    }

    private func addDevice() {
        guard let client = model.client else { return }
        let host = model.account?.server.host() ?? ""
        creatingInvite = true
        Task {
            do throws(APIError) {
                invite = try await client.createInvite()
            } catch {
                inviteFailure = connectionFailureText(error, host: host)
            }
            creatingInvite = false
        }
    }

    private func signOut(force: Bool) {
        let host = model.account?.server.host() ?? ""
        signingOut = true
        Task {
            switch await model.signOut(force: force) {
            case .done: break // The root swaps to the welcome screen.
            case let .unsentChanges(count): question = unsentChangesText(count)
            case .unreachable: question = String(localized: "Can't reach your server. Sign out anyway? This deletes everything on this iPhone. Ask an admin to remove this device from the household.")
            case .rateLimited: question = rateLimitedSignOutText(host: host)
            }
            signingOut = false
        }
    }
}

/// The tag after an admin's name, in the header and the members list.
struct AdminBadge: View {
    var body: some View {
        Text("Admin")
            .font(.caption2)
            .foregroundStyle(Color(ListColor.teal))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Color(ListColor.teal).opacity(0.15), in: Capsule())
    }
}

private extension View {
    /// A segmented control on the list's background, as in the mockup, with options at least 44 points high.
    func segmentedRow() -> some View {
        pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.large)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
    }
}

/// Turning it off still holds until the app quits, but the Keychain keeps the old account.
func certificateSaveFailureText(_ error: any Error) -> String {
    let failure = if let error = error as? Keychain.SaveError {
        // A String, because a number would be grouped: -25,308.
        String(localized: "Couldn't save the change in the Keychain on this iPhone: status \(String(error.status)).")
    } else {
        String(localized: "Couldn't save the change in the Keychain on this iPhone: \(error.localizedDescription)")
    }
    return failure + " " + String(localized: "Accepting any certificate is off now, but on again the next time the app starts.")
}

func unsentChangesText(_ count: Int) -> String {
    String(localized: "\(count) changes haven't been sent yet. Sign out and lose them?")
}

func rateLimitedSignOutText(host: String) -> String {
    failureText(.server(code: "rate_limited"), host: host) + " " + String(localized: "Sign out anyway? This deletes everything on this iPhone. Ask an admin to remove this device from the household.")
}

/// Why a request to `host` failed. Only a failed connection says that the action needs one: otherwise the server answered.
func connectionFailureText(_ failure: APIError, host: String) -> String {
    let cause = failureText(failure, host: host)
    return failure == .offline ? String(localized: "Needs a connection to your server.") + " " + cause : cause
}
