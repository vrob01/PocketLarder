import PocketLarderKit
import SwiftUI

/// A name for a new member, then the invite for their first device.
struct InviteMemberSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let household: Household
    @State private var name = ""
    @State private var sending = false
    @State private var invited: (invite: CreatedInvite, name: String)?
    @State private var inviteFailure: String?

    private var cleanName: String? { cleanText(name, max: Limit.name) }

    var body: some View {
        if let invited {
            // In place of the form, so that its Done and Cancel invite close the whole sheet.
            AddDeviceSheet(invite: invited.invite, memberName: invited.name)
        } else {
            NavigationStack {
                Form {
                    Section {
                        HStack {
                            TextField("Name", text: $name)
                                .submitLabel(.done)
                                .onSubmit { send() }
                                .accessibilityIdentifier("inviteMember.name")
                            if sending {
                                ProgressView()
                            }
                        }
                    }
                }
                .disabled(sending)
                .navigationTitle("Invite a new member")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .disabled(sending)
                            .accessibilityIdentifier("inviteMember.cancel")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Invite") { send() }
                            .disabled(cleanName == nil || sending)
                            .accessibilityIdentifier("inviteMember.invite")
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
            .interactiveDismissDisabled(sending)
        }
    }

    /// The members list reloads behind the sheet, also after a failure, so that it shows the server's state.
    private func send() {
        guard let cleanName, !sending, let client = model.client else { return }
        sending = true
        Task {
            var failure: APIError?
            do throws(APIError) {
                let invite = try await client.createInvite(newMemberName: cleanName)
                invited = (invite, cleanName)
            } catch {
                failure = error
            }
            inviteFailure = await household.refresh(after: failure)
            sending = false
        }
    }
}
