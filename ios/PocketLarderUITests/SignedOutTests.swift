import UIKit
import XCTest

private let example = "pocketlarder://invite?server=https%3A%2F%2Flists.example.com&code=fdd4efb3-cf5b-44e7-bec4-94df8e478f5f.ArBLMeKiOpJu5jbcasIRDr8-zlqlbdWCoIfZ9EsLPio"

@MainActor
final class SignedOutTests: ScreenshotTestCase {
    func testWelcome() {
        for (language, appearance) in variants {
            let app = launch(language, appearance)
            XCTAssertTrue(app.buttons["welcome.enterInvite"].waitForExistence(timeout: 10))
            attach(app, "welcome-\(language)-\(appearance)")
            app.terminate()
        }
    }

    func testEnterInvite() {
        for (language, appearance) in variants {
            let app = launch(language, appearance)
            app.buttons["welcome.enterInvite"].tap()
            let signIn = app.buttons["invite.signIn"]
            XCTAssertTrue(signIn.waitForExistence(timeout: 10))
            XCTAssertFalse(signIn.isEnabled)
            attach(app, "enter-invite-\(language)-\(appearance)")

            app.textFields["invite.code"].tap()
            app.textFields["invite.code"].typeText(example)
            XCTAssertEqual(app.textFields["invite.server"].value as? String, "lists.example.com")
            let done = app.buttons["invite.keyboardDone"]
            if done.waitForExistence(timeout: 2) { done.tap() }
            XCTAssertTrue(signIn.isEnabled)
            attach(app, "enter-invite-filled-\(language)-\(appearance)")
            app.terminate()
        }
    }

    func testWelcomeSignedOut() {
        for (language, appearance) in variants {
            let app = launch(language, appearance, "-signedOutLostChanges", "2")
            XCTAssertTrue(app.staticTexts["welcome.signedOut"].waitForExistence(timeout: 10))
            attach(app, "welcome-signed-out-\(language)-\(appearance)")
            app.terminate()
        }
    }

    func testEnterInviteError() {
        for (language, appearance) in variants {
            let app = launch(language, appearance, "-inviteError", "invalidInvite")
            app.buttons["welcome.enterInvite"].tap()
            XCTAssertTrue(app.staticTexts["invite.error"].waitForExistence(timeout: 10))
            attach(app, "enter-invite-error-\(language)-\(appearance)")
            app.terminate()
        }
    }

    /// The bubble shows the whole text, also in German at a large text size.
    func testOfflinePopover() {
        for (language, appearance) in variants {
            offlinePopover(launch(language, appearance, "-fixture", "offline"), language, "offline-\(language)-\(appearance)")
        }
        let large = launch(
            "de", "light", "-fixture", "offline",
            "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityMedium.rawValue
        )
        offlinePopover(large, "de", "offline-de-light-large")
    }
}
