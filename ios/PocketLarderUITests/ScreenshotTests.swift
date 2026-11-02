import XCTest

private let example = "pocketlarder://invite?server=https%3A%2F%2Flists.example.com&code=fdd4efb3-cf5b-44e7-bec4-94df8e478f5f.ArBLMeKiOpJu5jbcasIRDr8-zlqlbdWCoIfZ9EsLPio"

@MainActor
final class ScreenshotTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

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

    private let variants = [("en", "light"), ("en", "dark"), ("de", "light"), ("de", "dark")]

    private func launch(_ language: String, _ appearance: String, _ extra: String...) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", language, "-appearance", appearance] + extra
        app.launch()
        return app
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
