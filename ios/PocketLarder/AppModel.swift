import Foundation
import Observation
import PocketLarderKit

@MainActor @Observable
final class AppModel {
    enum SignInError: Error, Equatable {
        case invalidInvite, rateLimited, unreachable(host: String), alreadySignedIn(name: String), other
    }

    enum SignOutResult: Equatable {
        case done, unsentChanges(Int), unreachable
    }

    var pendingInvite: Invite?
    /// Shown once on the welcome screen, then cleared.
    var signedOutLostChanges: Int?
    /// Set when an invite link opens while signed in. The root shows the message and clears it.
    var alreadySignedInAs: String?
    private(set) var account: Account?
    private(set) var larder: Larder?

    private let transport: any Transport
    private let files: LocalFiles

    /// The member's name, or the server's host until the first snapshot arrives.
    var memberName: String {
        guard let account else { return "" }
        return larder?.view?.member(account.memberId)?.name ?? account.server.host() ?? ""
    }

    nonisolated static var defaultDataDirectory: URL {
        var directory = URL.applicationSupportDirectory.appending(path: "Larder")
        // `LocalFiles` never creates it, and iOS doesn't create Application Support itself.
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
        return directory
    }

    init(transport: any Transport = URLSessionTransport(), dataDirectory: URL = AppModel.defaultDataDirectory) {
        self.transport = transport
        files = LocalFiles(directory: dataDirectory)
        account = Keychain.load()
        larder = account.map(makeLarder)
        #if DEBUG
        signedOutLostChanges = UserDefaults.standard.string(forKey: "signedOutLostChanges").flatMap { Int($0) }
        #endif
    }

    func open(_ url: URL) {
        guard let invite = parseInvite(url.absoluteString) else { return }
        if account == nil {
            pendingInvite = invite
        } else {
            alreadySignedInAs = memberName
        }
    }

    func signIn(_ invite: Invite, deviceName: String) async -> SignInError? {
        if account != nil { return .alreadySignedIn(name: memberName) }
        let redemption: Redemption
        do {
            redemption = try await APIClient(server: invite.server, token: nil, transport: transport)
                .redeem(code: invite.code, deviceName: deviceName)
        } catch {
            switch error {
            case .server(code: "invalid_invite"): return .invalidInvite
            case .server(code: "rate_limited"): return .rateLimited
            case .offline: return .unreachable(host: invite.server.host() ?? "")
            default: return .other
            }
        }
        let account = Account(server: invite.server, token: redemption.token, memberId: redemption.memberId, deviceId: redemption.deviceId)
        do {
            try Keychain.save(account)
        } catch {
            return .other
        }
        // Files left by a failed wipe must never reach the new account.
        files.wipe()
        let larder = makeLarder(account)
        self.account = account
        self.larder = larder
        // A failed first sync leaves the phone signed in, and a 401 goes through `onSignedOut`.
        await larder.sync()
        return nil
    }

    func signOut(force: Bool) async -> SignOutResult {
        guard let account, let larder else { return .done }
        if force {
            wipe()
            return .done
        }
        await larder.sync()
        // A 401 or a forced sign-out during the wait has wiped already, and a new account may have signed in since.
        guard self.larder === larder else { return .done }
        if larder.isOffline { return .unreachable }
        if !larder.pending.isEmpty { return .unsentChanges(larder.pending.count) }
        var failure: APIError?
        do {
            try await APIClient(server: account.server, token: account.token, transport: transport).signOut()
        } catch {
            failure = error
        }
        guard self.larder === larder else { return .done }
        // `unauthorized` means the server already treats this device as signed out.
        if let failure, failure != .server(code: "unauthorized") { return .unreachable }
        wipe()
        return .done
    }

    private func makeLarder(_ account: Account) -> Larder {
        let larder = Larder(files: files, client: APIClient(server: account.server, token: account.token, transport: transport))
        larder.onSignedOut = { [weak self] lostChanges in
            self?.wipe()
            self?.signedOutLostChanges = lostChanges
        }
        return larder
    }

    /// One step on the main actor, so that nothing can be queued or written between the parts.
    private func wipe() {
        larder?.close()
        larder = nil
        account = nil
        Keychain.delete()
        files.wipe()
    }
}
