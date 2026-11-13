import PocketLarderKit
import SwiftUI

/// One member, for admins: their admin rights and devices, another device for them, their invites, and removing them.
struct MemberDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let household: Household
    let member: AdminMember
    /// Back to My account.
    let leave: @MainActor () -> Void
    /// A request is open, so that a second tap can't send it again.
    @State private var busy = false
    /// The switch's new position while it is sent.
    @State private var pendingAdmin: Bool?
    @State private var signingOut: AdminDevice?
    @State private var removing = false
    @State private var invite: CreatedInvite?
    @State private var actionFailure: (title: String, message: String)?

    /// The member as last loaded, so that the page shows the server's state.
    private var current: AdminMember { household.member(member.id) ?? member }

    var body: some View {
        Form {
            Section {
                Toggle("Admin", isOn: Binding(get: { pendingAdmin ?? current.isAdmin }, set: { setAdmin($0) }))
                    .accessibilityIdentifier("member.admin")
                ForEach(current.devices, id: \.id) { device in
                    HStack {
                        Text(deviceText(device))
                        Spacer()
                        Button(role: .destructive) {
                            signingOut = device
                        } label: {
                            // 44 points high without making the row taller.
                            Text("Sign out").contentShape(Rectangle().inset(by: -11))
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text("Sign out \(device.name)"))
                        .accessibilityIdentifier("member.signOut")
                    }
                }
                Button("Add a device for \(current.name)…") { addDevice() }
                    .accessibilityIdentifier("member.addDevice")
                NavigationLink("Invites") { InvitesView(memberId: member.id, household: household) }
                    .accessibilityIdentifier("member.invites")
            }
            Section {
                Button("Remove \(current.name)…", role: .destructive) { removing = true }
                    .accessibilityIdentifier("member.remove")
            }
        }
        .disabled(busy)
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(busy)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if busy {
                    ProgressView()
                }
            }
        }
        .alert(
            Text("Sign out \(signingOut?.name ?? "")? Invites created on it are cancelled too."),
            isPresented: Binding(get: { signingOut != nil }, set: { if !$0 { signingOut = nil } }),
            presenting: signingOut
        ) { device in
            Button("Sign out", role: .destructive) { signOut(device) }
            Button("Cancel", role: .cancel) {}
        }
        .alert(Text("Remove \(current.name)? All their devices are signed out and their list is deleted."), isPresented: $removing) {
            Button("Remove", role: .destructive) { remove() }
            Button("Cancel", role: .cancel) {}
        }
        .alert(
            actionFailure?.title ?? "",
            isPresented: Binding(get: { actionFailure != nil }, set: { if !$0 { actionFailure = nil } }),
            presenting: actionFailure
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: {
            Text($0.message)
        }
        .sheet(
            isPresented: Binding(get: { invite != nil }, set: { if !$0 { invite = nil } }),
            onDismiss: { afterInvite() }
        ) {
            if let invite {
                AddDeviceSheet(invite: invite, memberName: current.name)
            }
        }
    }

    private func setAdmin(_ isAdmin: Bool) {
        guard let client = model.client else { return }
        // Without admin rights the reload would be refused, so losing one's own goes back to My account instead.
        let leaving = !isAdmin && member.id == model.account?.memberId
        pendingAdmin = isAdmin
        busy = true
        Task {
            var failure: APIError?
            do throws(APIError) {
                try await client.setAdmin(member.id, isAdmin)
            } catch {
                failure = error
            }
            if failure == nil, leaving {
                await model.larder?.sync()
                leave()
                return
            }
            let shown = await household.refresh(after: failure)
            pendingAdmin = nil
            busy = false
            show(String(localized: "Couldn't change \(current.name)'s admin rights."), shown)
        }
    }

    private func signOut(_ device: AdminDevice) {
        guard let client = model.client else { return }
        busy = true
        Task {
            var failure: APIError?
            do throws(APIError) {
                try await client.removeDevice(device.id)
            } catch {
                failure = error
            }
            let shown = await household.refresh(after: failure)
            busy = false
            show(String(localized: "Couldn't sign out \(device.name)."), shown)
        }
    }

    private func remove() {
        guard let client = model.client else { return }
        busy = true
        Task {
            var failure: APIError?
            do throws(APIError) {
                try await client.removeMember(member.id)
            } catch {
                failure = error
            }
            let shown = await household.refresh(after: failure)
            busy = false
            if failure == nil { dismiss() }
            show(String(localized: "Couldn't remove \(current.name)."), shown)
        }
    }

    private func addDevice() {
        guard let client = model.client else { return }
        busy = true
        Task {
            do throws(APIError) {
                invite = try await client.createInvite(memberId: member.id)
            } catch {
                let shown = await household.refresh(after: error)
                show(String(localized: "Couldn't create an invite."), shown)
            }
            busy = false
        }
    }

    /// Once the invite's sheet closes, whether the invite was cancelled or not.
    private func afterInvite() {
        busy = true
        Task {
            _ = await household.refresh(after: nil)
            busy = false
        }
    }

    private func show(_ title: String, _ message: String?) {
        if let message { actionFailure = (title, message) }
    }
}
