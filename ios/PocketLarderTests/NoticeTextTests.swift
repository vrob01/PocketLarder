import Foundation
import PocketLarderKit
import Testing
@testable import PocketLarder

/// A missing catalog key would otherwise show "1 changes" with no failure.
@Test func noticeTexts() {
    #expect(noticeText(.listHidden(ownerName: "Sam", lostChanges: false)) == "Sam's list is now hidden, so it's no longer on this iPhone.")
    #expect(noticeText(.listHidden(ownerName: "Sam", lostChanges: true)) == "Sam's list is now hidden, so it's no longer on this iPhone. Your recent changes to it weren't saved.")
    #expect(noticeText(.listReadOnly(ownerName: "Sam")) == "Sam's list is now read-only. Your recent changes to it weren't saved.")
    #expect(noticeText(.renameConflict(from: "Milk", to: "Bread")) == "Couldn't rename \"Milk\" to \"Bread\": that item already exists.")
}

@Test func offlineTexts() {
    let host = "lists.example.test"
    #expect(offlineText(failure: .offline(.refused), host: host, pending: 3) == "lists.example.test refused the connection. 3 changes are waiting to be sent.")
    #expect(offlineText(failure: .unexpected(status: 502), host: host, pending: 1) == "lists.example.test answered with HTTP status 502. 1 change is waiting to be sent.")
    #expect(offlineText(failure: .server(code: "missing_token"), host: host, pending: 0) == "lists.example.test answered with error code missing_token. No changes are waiting to be sent.")
    #expect(offlineText(failure: .server(code: "rate_limited"), host: host, pending: 2) == "lists.example.test limited this iPhone's requests: too many in the past minute. 2 changes are waiting to be sent.")
}

@Test func failureTexts() {
    let host = "lists.example.test"
    #expect(failureText(.offline(.hostNotFound), host: host) == "Can't find lists.example.test: looking up its name (DNS) failed.")
    #expect(failureText(.offline(.refused), host: host) == "lists.example.test refused the connection.")
    #expect(failureText(.offline(.timedOut), host: host) == "The request to lists.example.test timed out.")
    #expect(failureText(.offline(.noNetwork), host: host) == "This iPhone has no network connection, so it can't reach lists.example.test.")
    #expect(failureText(.offline(.connectionLost), host: host) == "The connection to lists.example.test broke off.")
    #expect(failureText(.offline(.tlsFailed), host: host) == "The secure connection (TLS) to lists.example.test failed, for a reason other than its certificate.")
    #expect(failureText(.offline(.other(code: -1022)), host: host) == "Can't reach lists.example.test (URLError -1022).")
    #expect(failureText(.notPocketLarder(status: 200), host: host) == "lists.example.test answered with HTTP status 200, but the answer isn't PocketLarder's. It may be a captive portal's or a proxy's page.")
}

@Test func connectionFailureTexts() {
    let host = "lists.example.test"
    let reasons: [ConnectionFailure] = [.hostNotFound, .refused, .timedOut, .noNetwork, .connectionLost, .tlsFailed, .other(code: -1)]
    for reason in reasons {
        #expect(connectionFailureText(.offline(reason), host: host) == "Needs a connection to your server. " + failureText(.offline(reason), host: host))
    }
    #expect(connectionFailureText(.offline(.refused), host: host) == "Needs a connection to your server. lists.example.test refused the connection.")
    #expect(connectionFailureText(.notPocketLarder(status: 200), host: host) == failureText(.notPocketLarder(status: 200), host: host))
    #expect(connectionFailureText(.certificateRefused(reason: nil), host: host) == "This iPhone refused the certificate of lists.example.test.")
    #expect(connectionFailureText(.server(code: "internal"), host: host) == "lists.example.test answered with error code internal.")
    #expect(connectionFailureText(.unexpected(status: 502), host: host) == "lists.example.test answered with HTTP status 502.")
    #expect(connectionFailureText(.server(code: "rate_limited"), host: host) == "lists.example.test limited this iPhone's requests: too many in the past minute.")
    #expect(adminFailureText(.server(code: "rate_limited"), host: host) == "lists.example.test limited this iPhone's requests: too many in the past minute.")
    let full = "Maximum number of open invites reached. Cancel one under Invites, or wait until one is used or expires."
    #expect(connectionFailureText(.server(code: "too_many_invites"), host: host) == full)
    #expect(adminFailureText(.server(code: "too_many_invites"), host: host) == full)
    #expect(connectionFailureText(.server(code: "invite_redeemed"), host: host) == "This invite was already used.")
    #expect(adminFailureText(.server(code: "invite_redeemed"), host: host) == "This invite was already used.")
}

@Test func saveFailedTexts() {
    #expect(saveFailedText(CocoaError(.fileWriteOutOfSpace)).hasPrefix("Couldn't save this change on this iPhone: "))
}
