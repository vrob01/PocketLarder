import PocketLarderKit
import SwiftUI

struct EnterInviteView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var server = ""
    @State private var code = ""
    @State private var deviceName = "iPhone"
    @State private var signingIn = false
    @State private var signInError: AppModel.SignInError? = {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "inviteError") {
        case "invalidInvite": return .invalidInvite
        case "outdated": return .incompatible(.serverTooOld(nil), server: URL(string: "https://lists.example.com")!)
        default: break
        }
        #endif
        return nil
    }()
    @FocusState private var focused: Field?

    private enum Field { case server, code, deviceName }

    private var trimmedCode: String { code.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var signInURL: URL? { normalizeServer(server) }

    var body: some View {
        Group {
            // In place of the form, whose fields stay filled for when Refresh finds the server compatible.
            if case let .incompatible(incompatibility, invited) = signInError {
                IncompatibleView(incompatibility: incompatibility, host: invited.host() ?? "", refresh: { await recheck(invited) }) {
                    Button { dismiss() } label: {
                        IncompatibleExitLabel(title: "Back to the welcome screen")
                    }
                    .accessibilityIdentifier("incompatible.back")
                }
            } else {
                form
            }
        }
        .navigationTitle("Enter invite")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // Gone without the form, which it would fill out of sight.
                if !isIncompatible {
                    PasteButton(payloadType: String.self) { strings in
                        take(strings.joined(separator: "\n"))
                    }
                    .labelStyle(.titleAndIcon)
                    .accessibilityIdentifier("invite.paste")
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = nil }
                    .accessibilityIdentifier("invite.keyboardDone")
            }
        }
        .onChange(of: server) { take(server) }
        .onChange(of: code) { take(code) }
        .onChange(of: deviceName) { old, _ in take(deviceName, keepingDeviceName: old) }
        .onChange(of: model.pendingInvite, initial: true) {
            guard let invite = model.pendingInvite else { return }
            fill(invite)
            model.pendingInvite = nil
        }
    }

    private var isIncompatible: Bool {
        if case .incompatible = signInError { true } else { false }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if server.isEmpty && code.isEmpty {
                    Text("Got the invite as one link? Tap Paste and the fields fill themselves.")
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 8)
                }

                label("Server")
                HStack(spacing: 0) {
                    if !server.contains("://") {
                        Text(verbatim: "https://").foregroundStyle(.secondary).accessibilityHidden(true)
                    }
                    TextField("Server", text: $server, prompt: Text("lists.example.com"))
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused, equals: .server)
                        .accessibilityIdentifier("invite.server")
                }
                .fieldStyle()

                label("Invite code")
                TextField("Invite code", text: $code, prompt: Text("from your invite"))
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused, equals: .code)
                    .fieldStyle()
                    .accessibilityIdentifier("invite.code")

                label("Device name")
                TextField("Device name", text: $deviceName)
                    .focused($focused, equals: .deviceName)
                    .fieldStyle()
                    .accessibilityIdentifier("invite.deviceName")
                Text("Shows in your household's device list, e.g. \"Sam's iPhone\".")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button {
                    guard let url = signInURL else { return }
                    focused = nil
                    signInError = nil
                    signingIn = true
                    let invite = Invite(server: url, code: trimmedCode)
                    Task {
                        let error = await model.signIn(invite, deviceName: deviceName)
                        signingIn = false
                        signInError = error
                        if let error {
                            AccessibilityNotification.Announcement(signInErrorText(error)).post()
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if signingIn {
                            ProgressView().tint(Color(.systemBackground))
                        }
                        Text("Sign in")
                    }
                }
                .buttonStyle(AccentButtonStyle())
                .disabled(signingIn || signInURL == nil || trimmedCode.isEmpty)
                .padding(.top, 16)
                .accessibilityIdentifier("invite.signIn")

                if let signInError {
                    Text(signInErrorText(signInError))
                        .padding(.top, 8)
                        .accessibilityIdentifier("invite.error")
                }
            }
            .padding(24)
        }
    }

    /// Refresh checks only. Sign in signs in.
    private func recheck(_ invited: URL) async -> ServerCompatibility {
        let outcome = await model.checkServer(at: invited)
        switch outcome {
        case let .incompatible(incompatibility): signInError = .incompatible(incompatibility, server: invited)
        case .compatible: signInError = nil
        case .couldNotCheck: break
        }
        return outcome
    }

    private func label(_ key: LocalizedStringKey) -> some View {
        Text(key).font(.caption).textCase(.uppercase).tracking(0.6).foregroundStyle(.secondary).accessibilityHidden(true).padding(.top, 8)
    }

    /// Fills the form when `text` holds an invite link. Other text changes nothing.
    private func take(_ text: String, keepingDeviceName name: String? = nil) {
        guard let invite = parseInvite(text) else { return }
        fill(invite)
        if let name { deviceName = name }
    }

    private func fill(_ invite: Invite) {
        let text = invite.server.absoluteString
        server = text.hasPrefix("https://") ? String(text.dropFirst("https://".count)) : text
        code = invite.code
    }
}

func signInErrorText(_ error: AppModel.SignInError) -> String {
    switch error {
    case .invalidInvite: String(localized: "This invite can't be used. It may have expired or been used already. Ask for a new one.")
    case .rateLimited: String(localized: "Too many sign-in attempts on this server. Try again in a minute.")
    case let .unreachable(host): String(localized: "Can't reach \(host).")
    case let .alreadySignedIn(name): String(localized: "This iPhone is already signed in as \(name). Sign out first to use this invite.")
    case .other: String(localized: "Couldn't sign in. Try again, or ask for a new invite.")
    case let .incompatible(incompatibility, server): incompatibleText(incompatibility, host: server.host() ?? "")
    }
}

private extension View {
    func fieldStyle() -> some View {
        padding(12)
            .frame(minHeight: 44)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}
