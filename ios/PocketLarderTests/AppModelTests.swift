import Foundation
import PocketLarderKit
import Testing
@testable import PocketLarder

private let example = "pocketlarder://invite?server=https%3A%2F%2Flists.example.com&code=fdd4efb3-cf5b-44e7-bec4-94df8e478f5f.ArBLMeKiOpJu5jbcasIRDr8-zlqlbdWCoIfZ9EsLPio"

@Test @MainActor func openingInviteLinkSetsPendingInvite() throws {
    let model = AppModel()
    model.open(try #require(URL(string: example)))
    let invite = try #require(parseInvite(example))
    #expect(model.pendingInvite == invite)

    model.open(try #require(URL(string: "https://example.com")))
    #expect(model.pendingInvite == invite)
}
