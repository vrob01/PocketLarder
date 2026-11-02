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
    /// What the main screen shows. A different scope also sets `addTarget`, and assigning the same one changes nothing,
    /// so that re-checking it after a sync can't drop a target the user picked.
    var scope: Scope = .myView {
        didSet {
            guard scope != oldValue else { return }
            switch scope {
            case let .list(id): addTarget = id
            case .myView: addTarget = nil
            }
        }
    }
    /// The list new items go to. Nil means my list.
    var addTarget: String?

    private let transport: any Transport
    private let files: LocalFiles
    /// False for a fixture run, so that it can't read, replace or delete a real account.
    private let usesKeychain: Bool
    private var signInAttempts = 0
    private var enteredBackground: Date?

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
        usesKeychain = true
        account = Keychain.load()
        larder = account.map(makeLarder)
        #if DEBUG
        signedOutLostChanges = UserDefaults.standard.string(forKey: "signedOutLostChanges").flatMap { Int($0) }
        #endif
    }

    #if DEBUG
    /// Signed in on sample data, on a fake server and a new empty directory, so that nothing of a real account is touched.
    static func fixture() -> AppModel {
        let url = Bundle.main.url(forResource: "household", withExtension: "json")!
        let snapshot = try! JSON.decoder.decode(Snapshot.self, from: Data(contentsOf: url))
        let directory = FileManager.default.temporaryDirectory.appending(path: newID())
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let account = Account(
            server: URL(string: "https://fixture.invalid")!,
            token: "fixture",
            memberId: snapshot.me.memberId,
            deviceId: snapshot.me.deviceId
        )
        return AppModel(fixture: account, transport: FixtureTransport(snapshot), dataDirectory: directory)
    }

    private init(fixture account: Account, transport: any Transport, dataDirectory: URL) {
        self.transport = transport
        files = LocalFiles(directory: dataDirectory)
        usesKeychain = false
        self.account = account
        larder = makeLarder(account)
    }
    #endif

    /// `init` reads no account while the phone is locked, so the root asks again on becoming active. The files stay,
    /// because they may hold unsent changes, and the root's loop does the first sync.
    func restoreFromKeychain() {
        guard usesKeychain, account == nil, let restored = Keychain.load() else { return }
        // So that an open redeem can't replace this account.
        signInAttempts += 1
        larder = makeLarder(restored)
        account = restored
        if pendingInvite != nil {
            pendingInvite = nil
            alreadySignedInAs = memberName
        }
    }

    func didEnterBackground(now: Date = .now) {
        enteredBackground = now
    }

    /// More than five minutes away brings the main screen back to My view and my list.
    func didBecomeActive(now: Date = .now) {
        if let enteredBackground, now.timeIntervalSince(enteredBackground) > 300 {
            resetScope()
        }
        enteredBackground = nil
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
        signInAttempts += 1
        let attempt = signInAttempts
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
        // A newer attempt or a restore took over while this request was open. This answer must not replace that account
        // or sign the phone back in after it signed out, so the device it created stays unused on its server.
        guard attempt == signInAttempts else {
            return account == nil ? .other : .alreadySignedIn(name: memberName)
        }
        let account = Account(server: invite.server, token: redemption.token, memberId: redemption.memberId, deviceId: redemption.deviceId)
        do {
            if usesKeychain { try Keychain.save(account) }
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
            // One try, so that no device row is left for an admin when the server can be reached. A plain client can't
            // reach `onSignedOut` and the task holds no `self`, so the answer can't touch this or a later account.
            let client = APIClient(server: account.server, token: account.token, transport: transport)
            Task { try? await client.signOut() }
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
        resetScope()
        if usesKeychain { Keychain.delete() }
        files.wipe()
    }

    private func resetScope() {
        scope = .myView
        addTarget = nil
    }
}
