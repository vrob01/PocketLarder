import PocketLarderKit
import SwiftUI

struct EnterInviteView: View {
    @Environment(AppModel.self) private var model
    @State private var server = ""
    @State private var code = ""
    @State private var deviceName = "iPhone"
    @FocusState private var focused: Field?

    private enum Field { case server, code, deviceName }

    private var trimmedCode: String { code.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var signInURL: URL? { normalizeServer(server) }

    var body: some View {
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

                Button("Sign in") {
                    guard let url = signInURL else { return }
                    let invite = Invite(server: url, code: trimmedCode)
                    Task { await model.signIn(invite, deviceName: deviceName) }
                }
                .buttonStyle(AccentButtonStyle())
                .disabled(signInURL == nil || trimmedCode.isEmpty)
                .padding(.top, 16)
                .accessibilityIdentifier("invite.signIn")
            }
            .padding(24)
        }
        .navigationTitle("Enter invite")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                PasteButton(payloadType: String.self) { strings in
                    take(strings.joined(separator: "\n"))
                }
                .labelStyle(.titleAndIcon)
                .accessibilityIdentifier("invite.paste")
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

private extension View {
    func fieldStyle() -> some View {
        padding(12)
            .frame(minHeight: 44)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}
