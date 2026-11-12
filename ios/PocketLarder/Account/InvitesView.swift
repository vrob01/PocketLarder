import PocketLarderKit
import SwiftUI

/// A member's invites as the server lists them: one's own from My account, a member's from their page for admins.
struct InvitesView: View {
    /// Nil for one's own: the server refuses a member who isn't an admin and names anyone, even themselves.
    let memberId: String?
    /// The admin's members, reloaded after a change so that their pending invites match the server. Nil from My account.
    let household: Household?

    @Environment(AppModel.self) private var model
    /// Nil until a load succeeds.
    @State private var invites: [ListedInvite]?
    @State private var loadFailure: String?
    /// A cancel or clear is open, so that a second tap can't send another.
    @State private var busy = false
    @State private var actionFailure: (title: String, message: String)?

    private var host: String { model.account?.server.host() ?? "" }

    var body: some View {
        List {
            if let loadFailure {
                Section {
                    Text(loadFailure).accessibilityIdentifier("invites.loadFailure")
                }
            }
            if let invites {
                Section {
                    if invites.isEmpty {
                        Text("No invites.").accessibilityIdentifier("invites.empty")
                    }
                    ForEach(invites, id: \.id) { row($0) }
                }
            }
            Section {
                Button("Clear used and expired invites") { clear() }
                    .disabled(busy || !(invites ?? []).contains(where: { $0.state != .open }))
                    .accessibilityIdentifier("invites.clear")
            }
        }
        .navigationTitle("Invites")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if busy {
                    ProgressView()
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .alert(
            actionFailure?.title ?? "",
            isPresented: Binding(get: { actionFailure != nil }, set: { if !$0 { actionFailure = nil } }),
            presenting: actionFailure
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: {
            Text($0.message)
        }
    }

    /// The state as the server named it, never by the phone's clock, and the expiry.
    private func row(_ invite: ListedInvite) -> some View {
        let expiry = inviteExpiry(invite.expiresAt)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                switch invite.state {
                case .open: Text("Open")
                case .redeemed: Text("Used")
                case .expired: Text("Expired")
                }
                Text("Expiry: \(expiry)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("invites.invite")
            if invite.state == .open {
                Spacer()
                Button(role: .destructive) {
                    cancel(invite)
                } label: {
                    // 44 points high without making the row taller.
                    Text("Cancel invite").contentShape(Rectangle().inset(by: -11))
                }
                .buttonStyle(.borderless)
                .disabled(busy)
                .accessibilityLabel(Text("Cancel invite, expiry: \(expiry)"))
                .accessibilityIdentifier("invites.cancel")
            }
        }
    }

    /// The rows of the last load stay when this one fails.
    private func load() async {
        guard let client = model.client else { return }
        do throws(APIError) {
            invites = try await client.invites(memberId: memberId)
            loadFailure = nil
        } catch {
            loadFailure = announced(String(localized: "Couldn't load the invites.") + " " + connectionFailureText(error, host: host))
        }
    }

    private func cancel(_ invite: ListedInvite) {
        guard let client = model.client else { return }
        busy = true
        Task {
            var failure: APIError?
            do throws(APIError) {
                try await client.cancelInvite(invite.id)
            } catch {
                failure = error
            }
            await reload(after: failure, String(localized: "Couldn't cancel the invite."))
        }
    }

    private func clear() {
        guard let client = model.client else { return }
        busy = true
        Task {
            var failure: APIError?
            do throws(APIError) {
                _ = try await client.clearInvites(memberId: memberId)
            } catch {
                failure = error
            }
            await reload(after: failure, String(localized: "Couldn't clear the invites."))
        }
    }

    /// After a cancel or clear, whether it worked or not, so that the rows and the admin's members show the server's state.
    private func reload(after failure: APIError?, _ title: String) async {
        await load()
        await household?.load()
        busy = false
        if let failure {
            actionFailure = (title, connectionFailureText(failure, host: host))
        }
    }
}
