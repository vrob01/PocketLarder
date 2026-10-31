import Foundation
import Observation
import PocketLarderKit

@MainActor @Observable
final class AppModel {
    var pendingInvite: Invite?

    func open(_ url: URL) {
        if let invite = parseInvite(url.absoluteString) {
            pendingInvite = invite
        }
    }

    func signIn(_ invite: Invite, deviceName: String) async {}
}
