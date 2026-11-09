import UIKit
import XCTest

private let example = "pocketlarder://invite?server=https%3A%2F%2Flists.example.com&code=fdd4efb3-cf5b-44e7-bec4-94df8e478f5f.ArBLMeKiOpJu5jbcasIRDr8-zlqlbdWCoIfZ9EsLPio"

@MainActor
final class SignedOutTests: ScreenshotTestCase {
    func testWelcome() {
        for language in languages {
            let app = launch(language)
            XCTAssertTrue(app.buttons["welcome.enterInvite"].waitForExistence(timeout: 10))
            attachBoth(app) { "welcome-\(language)-\($0)" }
            app.terminate()
        }
    }

    func testEnterInvite() {
        for language in languages {
            let app = launch(language)
            app.buttons["welcome.enterInvite"].tap()
            let signIn = app.buttons["invite.signIn"]
            XCTAssertTrue(signIn.waitForExistence(timeout: 10))
            XCTAssertFalse(signIn.isEnabled)
            attachBoth(app) { "enter-invite-\(language)-\($0)" }

            app.textFields["invite.code"].tap()
            app.textFields["invite.code"].typeText(example)
            XCTAssertEqual(app.textFields["invite.server"].value as? String, "lists.example.com")
            let done = app.buttons["invite.keyboardDone"]
            if done.waitForExistence(timeout: 2) { done.tap() }
            XCTAssertTrue(signIn.isEnabled)
            attachBoth(app) { "enter-invite-filled-\(language)-\($0)" }
            app.terminate()
        }
    }

    func testWelcomeSignedOut() {
        for language in languages {
            let app = launch(language, "-signedOutLostChanges", "2")
            XCTAssertTrue(app.staticTexts["welcome.signedOut"].waitForExistence(timeout: 10))
            attachBoth(app) { "welcome-signed-out-\(language)-\($0)" }
            app.terminate()
        }
    }

    func testEnterInviteError() {
        for language in languages {
            let app = launch(language, "-inviteError", "invalidInvite")
            app.buttons["welcome.enterInvite"].tap()
            XCTAssertTrue(app.staticTexts["invite.error"].waitForExistence(timeout: 10))
            attachBoth(app) { "enter-invite-error-\(language)-\($0)" }
            app.terminate()
        }
    }

    /// The bubble shows the whole text, also in German at a large text size.
    func testOfflinePopover() {
        for language in languages {
            let app = launch(language, "-fixture", "offline")
            XCTAssertTrue(app.buttons["main.offline"].waitForExistence(timeout: 10))
            showPopover(app, language)
            // The switch of the appearance closes the bubble.
            attachBoth(app, reopen: { self.showPopover(app, language) }) { "offline-\(language)-\($0)" }
            app.terminate()
        }
        let large = launch(
            "de", "-fixture", "offline",
            "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityMedium.rawValue
        )
        XCTAssertTrue(large.buttons["main.offline"].waitForExistence(timeout: 10))
        showPopover(large, "de")
        attach(large, "offline-de-light-large")
        large.terminate()
    }

    /// Opens the bubble unless it is open, and expects its text.
    private func showPopover(_ app: XCUIApplication, _ language: String) {
        let text = app.staticTexts["main.offlineText"]
        if !text.exists { app.buttons["main.offline"].tap() }
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        XCTAssertEqual(text.label, language == "en"
            ? "Can't reach fixture.invalid. No changes are waiting to be sent."
            : "fixture.invalid ist nicht erreichbar. Es warten keine Änderungen darauf, gesendet zu werden.")
        // The bubble is still growing.
        Thread.sleep(forTimeInterval: 0.5)
    }
}
