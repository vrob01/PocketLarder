import UIKit
import XCTest

@MainActor
final class MembersTests: ScreenshotTestCase {
    /// Members & devices, with Robin invited through the form. In English light it also signs out Sam's iPhone, removes
    /// Robin, and checks the refusals of a taken name and of the only admin's rights.
    func testMembers() {
        let invited = ["en": "Invited, not signed in yet", "de": "Eingeladen, noch nicht angemeldet"]
        for language in languages {
            let app = launch(language, "-fixture", "household")
            // Once the first sync is in, so that My account knows that Alex is an admin.
            _ = addField(app)
            _ = openAccount(app)
            let membersRow = withID(app.buttons, "account.members")
            scrollUp(app, in: app, until: membersRow)
            membersRow.tap()

            let inviteRow = withID(app.buttons, "members.invite")
            XCTAssertTrue(inviteRow.waitForExistence(timeout: 20))
            inviteRow.tap()
            let name = withID(app.textFields, "inviteMember.name")
            XCTAssertTrue(name.waitForExistence(timeout: 10))
            name.tap()
            name.typeText("Robin")
            attachBoth(app) { "invite-member-\(language)-\($0)" }

            withID(app.buttons, "inviteMember.invite").tap()
            let qr = withID(app.images, "addDevice.qr")
            XCTAssertTrue(qr.waitForExistence(timeout: 20))
            withID(app.buttons, "addDevice.done").tap()
            XCTAssertTrue(qr.waitForNonExistence(timeout: 20), "Done didn't close the sheet")
            let robin = app.buttons.matching(NSPredicate(
                format: "identifier == 'members.member' AND label BEGINSWITH 'Robin' AND label CONTAINS %@", invited[language]!
            )).firstMatch
            XCTAssertTrue(robin.waitForExistence(timeout: 20))
            // The sheet is still sliding down.
            Thread.sleep(forTimeInterval: 1)
            attachBoth(app) { "members-\(language)-\($0)" }

            entry(app, "members.member", "Sam").tap()
            let remove = withID(app.buttons, "member.remove")
            XCTAssertTrue(remove.waitForExistence(timeout: 10))
            let admin = withID(app.switches, "member.admin")
            XCTAssertEqual(admin.value as? String, "0")
            attachBoth(app) { "member-detail-\(language)-\($0)" }

            if language == "en" {
                let signOut = withID(app.buttons, "member.signOut")
                XCTAssertEqual(signOut.label, "Sign out iPhone")
                signOut.tap()
                answer(app, "Sign out iPhone? Their pending invites are cancelled too.", with: "Sign out")
                XCTAssertTrue(signOut.waitForNonExistence(timeout: 20), "Sam still has a device")
                goBack(app)

                entry(app, "members.member", "Alex").tap()
                XCTAssertTrue(admin.waitForExistence(timeout: 10))
                XCTAssertEqual(admin.value as? String, "1")
                // The row's middle is the label, which doesn't flip the switch.
                admin.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
                answer(app, "The household needs at least one admin.", with: "OK")
                wait(for: [expectation(for: NSPredicate(format: "value == '1'"), evaluatedWith: admin)], timeout: 10)
                goBack(app)

                robin.tap()
                XCTAssertTrue(remove.waitForExistence(timeout: 10))
                remove.tap()
                answer(app, "Remove Robin? All their devices are signed out and their list is deleted.", with: "Remove")
                XCTAssertTrue(remove.waitForNonExistence(timeout: 20), "Removing didn't go back to the members")
                XCTAssertTrue(entry(app, "members.member", "Robin").waitForNonExistence(timeout: 20), "Robin is still listed")

                inviteRow.tap()
                XCTAssertTrue(name.waitForExistence(timeout: 10))
                name.tap()
                name.typeText("sam")
                withID(app.buttons, "inviteMember.invite").tap()
                answer(app, "Someone in the household already has that name.", with: "OK")
                XCTAssertEqual(name.value as? String, "sam")
            }
            app.terminate()
        }
    }

    /// A member's page hides its back button while a request is open.
    private func goBack(_ app: XCUIApplication) {
        let back = app.buttons["BackButton"]
        XCTAssertTrue(back.waitForExistence(timeout: 20))
        back.tap()
    }
}
