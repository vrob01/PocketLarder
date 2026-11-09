import PocketLarderKit
import SwiftUI

/// Every member with their devices, for admins, from My account's "Members & devices".
struct MembersView: View {
    /// Back to My account.
    let leave: @MainActor () -> Void
    @State private var household: Household
    @State private var inviting = false

    init(model: AppModel, leave: @escaping @MainActor () -> Void) {
        self.leave = leave
        _household = State(initialValue: Household(model: model))
    }

    var body: some View {
        List {
            if let loadFailure = household.loadFailure {
                Section {
                    Text(loadFailure).accessibilityIdentifier("members.loadFailure")
                }
            }
            Section {
                ForEach(household.members, id: \.id) { member in
                    NavigationLink {
                        MemberDetailView(household: household, member: member, leave: leave)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(member.name)
                                if member.isAdmin {
                                    AdminBadge()
                                }
                            }
                            Group {
                                if member.devices.isEmpty {
                                    Text("Invited, not signed in yet")
                                } else {
                                    ForEach(member.devices, id: \.id) { Text(deviceText($0)) }
                                }
                            }
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("members.member")
                }
            }
            Section {
                Button("Invite a new member…") { inviting = true }
                    .accessibilityIdentifier("members.invite")
            }
        }
        .navigationTitle("Members")
        .navigationBarTitleDisplayMode(.inline)
        .task { await household.load() }
        .refreshable { await household.load() }
        .sheet(isPresented: $inviting) { InviteMemberSheet(household: household) }
    }
}

/// The members as the server last listed them, shared by the members list and each member's page.
@MainActor @Observable
final class Household {
    private(set) var members: [AdminMember] = []
    private(set) var loadFailure: String?
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    private var host: String { model.account?.server.host() ?? "" }

    func member(_ id: String) -> AdminMember? {
        members.first { $0.id == id }
    }

    /// The members of the last load stay when this one fails.
    func load() async {
        guard let client = model.client else { return }
        do throws(APIError) {
            members = try await client.members().sorted { (fold($0.name), $0.id) < (fold($1.name), $1.id) }
            loadFailure = nil
        } catch {
            if error == .server(code: "unauthorized") {
                await model.larder?.sync()
            } else {
                loadFailure = announced(String(localized: "Couldn't load the members.") + " " + connectionFailureText(error, host: host))
            }
        }
    }

    /// Reloads the members and syncs after an admin request, so that the screens show the server's state, a refused
    /// change included. Returns the text for the request's failure. `unauthorized` shows nothing and skips the reload:
    /// the sync's own 401 then signs this iPhone out through `onSignedOut`, which is how removing this iPhone or its
    /// member ends.
    func refresh(after failure: APIError?) async -> String? {
        if failure == .server(code: "unauthorized") {
            await model.larder?.sync()
            return nil
        }
        await load()
        await model.larder?.sync()
        return failure.map { adminFailureText($0, host: host) }
    }
}

/// "iPhone · 2 hours ago". Under a minute reads "now", because the server records a device as seen at each request,
/// so this iPhone would otherwise show as seen seconds ago.
func deviceText(_ device: AdminDevice) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.dateTimeStyle = .named
    let seconds = Date.now.timeIntervalSince(device.lastSeenAt)
    return String(localized: "\(device.name) · \(formatter.localizedString(fromTimeInterval: seconds < 60 ? 0 : -seconds))")
}

/// Why an admin request to `host` failed. The two refusals a user can act on get their own words.
func adminFailureText(_ failure: APIError, host: String) -> String {
    switch failure {
    case .server(code: "conflict"): String(localized: "Someone in the household already has that name.")
    case .server(code: "last_admin"): String(localized: "The household needs at least one admin.")
    default: connectionFailureText(failure, host: host)
    }
}
