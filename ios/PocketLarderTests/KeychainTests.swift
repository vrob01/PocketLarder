import Foundation
import Security
import Testing
@testable import PocketLarder

/// Everything that touches the Keychain or builds an `AppModel` is a member, here or in `AppModelTests.swift`: there
/// is one global item, and Swift Testing otherwise runs tests in parallel. No item may outlive a test either, because
/// the UI tests run next on the same simulator and would launch signed in.
@Suite(.serialized) struct KeychainSuite {
    init() {
        Keychain.delete()
    }
}

extension KeychainSuite {
    @Test func keychainItemIsThisDeviceOnly() throws {
        defer { Keychain.delete() }
        let server = try #require(URL(string: "https://lists.example.test"))
        try Keychain.save(Account(server: server, token: "old", memberId: "m", deviceId: "d"))
        let account = Account(server: server, token: "new", memberId: "m", deviceId: "d")
        try Keychain.save(account)
        #expect(Keychain.load() == account)

        var result: CFTypeRef?
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "org.pocketlarder.account",
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        #expect(SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess)
        let items = try #require(result as? [[String: Any]])
        #expect(items.count == 1)
        let attributes = try #require(items.first)
        #expect(attributes[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        #expect(attributes[kSecAttrSynchronizable as String] as? Bool != true)

        Keychain.delete()
        #expect(Keychain.load() == nil)
    }

    /// An account as `Keychain.save` wrote it before `acceptsAnyCertificate` existed.
    @Test func accountWithoutCertificateKeyLoads() throws {
        defer { Keychain.delete() }
        let json = #"{"device_id":"d","member_id":"m","server":"https:\/\/lists.example.test","token":"old"}"#
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "org.pocketlarder.account",
            kSecAttrSynchronizable as String: false,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: Data(json.utf8),
        ]
        #expect(SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess)
        let server = try #require(URL(string: "https://lists.example.test"))
        let old = try #require(Keychain.load())
        #expect(old == Account(server: server, token: "old", memberId: "m", deviceId: "d"))
        #expect(!old.acceptsAnyCertificate)

        let trusting = Account(server: server, token: "new", memberId: "m", deviceId: "d", acceptsAnyCertificate: true)
        try Keychain.save(trusting)
        #expect(Keychain.load() == trusting)
    }
}

@Test func dataDirectoryIsExcludedFromBackup() throws {
    let directory = AppModel.defaultDataDirectory
    #expect(FileManager.default.fileExists(atPath: directory.path))
    // A new URL, because the one returned may hold the values it set.
    let values = try URL(filePath: directory.path).resourceValues(forKeys: [.isExcludedFromBackupKey])
    #expect(values.isExcludedFromBackup == true)
}
