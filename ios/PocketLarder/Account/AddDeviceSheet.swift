import PocketLarderKit
import SwiftUI
import UniformTypeIdentifiers

/// A new invite as a QR code for another iPhone, to share or copy. The invite never shows as text.
struct AddDeviceSheet: View {
    let invite: CreatedInvite
    let memberName: String

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var cancelling = false
    @State private var cancelFailure: (title: String, message: String)?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 12) {
                        Text("Scan with the new iPhone's Camera")
                            .font(.headline)
                        if let image = qrImage(invite.url) {
                            Image(uiImage: image)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                // White around the code in dark mode too, so that the Camera finds its edges.
                                .padding(10)
                                .background(Color.white)
                                .frame(maxWidth: 170)
                                .accessibilityLabel("QR code of the invite")
                                .accessibilityIdentifier("addDevice.qr")
                        }
                        Text("Signs in as \(memberName) · one use · valid until \(inviteExpiry(invite.expiresAt))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                Section {
                    if let url = URL(string: invite.url) {
                        ShareLink(item: url) {
                            Text("Share invite…")
                        }
                        .accessibilityIdentifier("addDevice.share")
                    }
                    Button("Copy invite") { copy() }
                        .accessibilityIdentifier("addDevice.copy")
                } footer: {
                    Text("Anyone with this invite can sign in as you until it's used or expires. Only send it to yourself.")
                }
                Section {
                    Button(role: .destructive) {
                        cancel()
                    } label: {
                        HStack {
                            Text("Cancel invite")
                            if cancelling {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .accessibilityIdentifier("addDevice.cancel")
                }
            }
            .listSectionSpacing(.compact)
            .disabled(cancelling)
            .navigationTitle("Add a device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .disabled(cancelling)
                        .accessibilityIdentifier("addDevice.done")
                }
            }
        }
        .interactiveDismissDisabled(cancelling)
        .alert(
            cancelFailure?.title ?? "",
            isPresented: Binding(
                get: { cancelFailure != nil },
                set: { if !$0 { cancelFailure = nil } }
            ),
            presenting: cancelFailure
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: {
            Text($0.message)
        }
    }

    /// Only on this iPhone, not on the user's other devices, and only for ten minutes.
    private func copy() {
        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: invite.url]],
            options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(600)]
        )
    }

    /// Cancels only the invite on screen. One that is already gone closes the sheet, as a cancel does.
    private func cancel() {
        guard let client = model.client else { return }
        let host = model.account?.server.host() ?? ""
        cancelling = true
        Task {
            do throws(APIError) {
                try await client.cancelInvite(invite.id)
                dismiss()
            } catch .server(code: "not_found") {
                dismiss()
            } catch {
                let title = error == .server(code: "invite_redeemed")
                    ? "Couldn't cancel the invite."
                    : "Couldn't cancel the invite. It still works until it's used or expires."
                cancelFailure = (title, connectionFailureText(error, host: host))
            }
            cancelling = false
        }
    }
}

/// "tomorrow at 09:00", for the middle of a sentence. Add a device and Invites both show an invite's expiry with it.
func inviteExpiry(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.doesRelativeDateFormatting = true
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    formatter.formattingContext = .middleOfSentence
    return formatter.string(from: date)
}
