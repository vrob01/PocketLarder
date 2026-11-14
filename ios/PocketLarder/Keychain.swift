import Foundation
import PocketLarderKit
import Security

struct Account: Codable, Equatable, Sendable {
    var server: URL
    var token: String
    var memberId: String
    var deviceId: String
    /// Set only by the user's choice on Enter invite. The transport then accepts any certificate from `server`'s host.
    var acceptsAnyCertificate = false
}

extension Account {
    /// An account saved before `acceptsAnyCertificate` existed has no key for it, and loads with it off.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        server = try container.decode(URL.self, forKey: .server)
        token = try container.decode(String.self, forKey: .token)
        memberId = try container.decode(String.self, forKey: .memberId)
        deviceId = try container.decode(String.self, forKey: .deviceId)
        acceptsAnyCertificate = try container.decodeIfPresent(Bool.self, forKey: .acceptsAnyCertificate) ?? false
    }
}

/// The one place the device token is stored.
enum Keychain {
    struct SaveError: Error {
        let status: OSStatus
    }

    private static var item: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "org.pocketlarder.account",
            kSecAttrSynchronizable as String: false,
        ]
    }

    /// Nil for a missing or undecodable item, and also while the phone is locked.
    static func load() -> Account? {
        var query = item
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return try? JSON.decoder.decode(Account.self, from: data)
    }

    static func save(_ a: Account) throws {
        var attributes = item
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        attributes[kSecValueData as String] = try JSON.encoder.encode(a)
        delete()
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw SaveError(status: status) }
    }

    static func delete() {
        SecItemDelete(item as CFDictionary)
    }
}
