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
    #expect(offlineText(failure: .offline, host: host, pending: 3) == "Can't reach lists.example.test. 3 changes are waiting to be sent.")
    #expect(offlineText(failure: .unexpected(status: 502), host: host, pending: 1) == "lists.example.test answered with HTTP status 502. 1 change is waiting to be sent.")
    #expect(offlineText(failure: .server(code: "missing_token"), host: host, pending: 0) == "lists.example.test answered with error code missing_token. No changes are waiting to be sent.")
    #expect(offlineText(failure: .server(code: "rate_limited"), host: host, pending: 2) == "lists.example.test limited this iPhone's requests: too many in the past minute. 2 changes are waiting to be sent.")
}

@Test func connectionFailureTexts() {
    let host = "lists.example.test"
    #expect(connectionFailureText(.offline, host: host) == "Needs a connection to your server. Can't reach lists.example.test.")
    #expect(connectionFailureText(.server(code: "internal"), host: host) == "lists.example.test answered with error code internal.")
    #expect(connectionFailureText(.unexpected(status: 502), host: host) == "lists.example.test answered with HTTP status 502.")
    #expect(connectionFailureText(.server(code: "rate_limited"), host: host) == "lists.example.test limited this iPhone's requests: too many in the past minute.")
    #expect(adminFailureText(.server(code: "rate_limited"), host: host) == "lists.example.test limited this iPhone's requests: too many in the past minute.")
    #expect(connectionFailureText(.server(code: "too_many_invites"), host: host) == "This member already has the most open invites lists.example.test allows. An invite stops counting once it's used, cancelled or 24 hours old.")
    #expect(adminFailureText(.server(code: "too_many_invites"), host: host) == "This member already has the most open invites lists.example.test allows. An invite stops counting once it's used, cancelled or 24 hours old.")
}

@Test func saveFailedTexts() {
    #expect(saveFailedText(CocoaError(.fileWriteOutOfSpace)).hasPrefix("Couldn't save this change on this iPhone: "))
}
