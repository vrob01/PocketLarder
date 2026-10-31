import Foundation
import Testing
@testable import PocketLarderKit

let example = "pocketlarder://invite?server=https%3A%2F%2Flists.example.com&code=fdd4efb3-cf5b-44e7-bec4-94df8e478f5f.ArBLMeKiOpJu5jbcasIRDr8-zlqlbdWCoIfZ9EsLPio"
let exampleCode = "fdd4efb3-cf5b-44e7-bec4-94df8e478f5f.ArBLMeKiOpJu5jbcasIRDr8-zlqlbdWCoIfZ9EsLPio"
let exampleInvite = Invite(server: URL(string: "https://lists.example.com")!, code: exampleCode)

@Test func parsesInviteURL() {
    #expect(parseInvite(example) == exampleInvite)
}

@Test func findsInviteInsideText() {
    #expect(parseInvite("Here's your invite:\n\n" + example + "\nSee you!") == exampleInvite)
    #expect(parseInvite("  " + example + "\n") == exampleInvite)
    #expect(parseInvite("iPhone" + example) == exampleInvite)
}

@Test func rejectsBadInvites() {
    let noCode = "pocketlarder://invite?server=https%3A%2F%2Flists.example.com"
    #expect(parseInvite("https://lists.example.com") == nil)
    #expect(parseInvite("pocketlarder://other?server=https%3A%2F%2Flists.example.com&code=x") == nil)
    #expect(parseInvite(noCode) == nil)
    #expect(parseInvite(noCode + "&code=") == nil)
    #expect(parseInvite(noCode + "&code=a%20b") == nil)
    #expect(parseInvite(noCode + "&code=a%0Ab") == nil)
    #expect(parseInvite(noCode + "&code=%20") == nil)
    #expect(parseInvite("pocketlarder://invite?server=http%3A%2F%2Flists.example.com&code=x") == nil)
}

@Test(arguments: [
    ("lists.example.com", "https://lists.example.com"),
    ("HTTPS://Lists.Example.com/", "https://lists.example.com"),
    ("https://lists.example.com:8443", "https://lists.example.com:8443"),
    (" http://localhost:5100 ", "http://localhost:5100"),
    ("http://127.0.0.1:5100", "http://127.0.0.1:5100"),
    ("http://lists.example.com", nil),
    ("https://lists.example.com/app", nil),
    ("https://lists.example.com?x=1", nil),
    ("https://lists.example.com#x", nil),
    ("https://u:p@lists.example.com", nil),
    ("ftp://lists.example.com", nil),
    ("", nil),
] as [(String, String?)])
func normalizesServer(input: String, expected: String?) {
    #expect(normalizeServer(input)?.absoluteString == expected)
}
