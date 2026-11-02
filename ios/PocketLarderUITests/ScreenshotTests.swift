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

    func testMain() {
        for (language, appearance) in variants {
            let app = launch(language, appearance, "-fixture", "household", "-layout", "rows")
            let crossOff = app.buttons.matching(identifier: "entry.crossOff").firstMatch
            XCTAssertTrue(crossOff.waitForExistence(timeout: 10))
            XCTAssertGreaterThanOrEqual(crossOff.frame.width, 44)
            XCTAssertGreaterThanOrEqual(crossOff.frame.height, 44)
            attach(app, "main-\(language)-\(appearance)-rows")

            let market = app.buttons["chip.Market"]
            market.tap()
            wait(for: [expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: market)], timeout: 5)
            // The tap's highlight is still fading, and would show as a dimmed chip.
            Thread.sleep(forTimeInterval: 0.5)
            attach(app, "main-store-\(language)-\(appearance)")

            app.buttons["chip.all"].tap()
            let bought = app.buttons["main.recentlyBought"]
            scrollUp(app, until: bought)
            bought.tap()
            // The rows open below the end of the screen.
            scrollUp(app, until: app.buttons.matching(identifier: "bought.entry").firstMatch)
            app.swipeUp()
            attach(app, "main-bought-\(language)-\(appearance)")
            app.terminate()

            let tiles = launch(language, appearance, "-fixture", "household", "-layout", "tiles")
            XCTAssertTrue(tiles.buttons.matching(identifier: "entry.tile").firstMatch.waitForExistence(timeout: 10))
            attach(tiles, "main-\(language)-\(appearance)-tiles")
            tiles.terminate()
        }
    }

    func testAdding() {
        for (language, appearance) in variants {
            let app = launch(language, appearance, "-fixture", "household")
            let field = addField(app)
            field.tap()
            field.typeText("mi")
            let suggestions = app.buttons.matching(identifier: "main.suggestion")
            XCTAssertTrue(suggestions.firstMatch.waitForExistence(timeout: 5))
            XCTAssertGreaterThanOrEqual(suggestions.count, 2)
            attach(app, "add-suggestions-\(language)-\(appearance)")

            suggestions.matching(NSPredicate(format: "label BEGINSWITH 'Milk'")).firstMatch.tap()
            assertEmpty(field)
            XCTAssertTrue(app.keyboards.firstMatch.exists)
            scrollUp(app, until: entry(app, "entry.row", "Milk"))
            app.terminate()
        }
    }

    /// Return on a name that's on the list clears the field and scrolls to the entry, in both layouts.
    func testAddingExisting() {
        for layout in ["rows", "tiles"] {
            let app = launch("en", "light", "-fixture", "household", "-layout", layout)
            let field = addField(app)
            field.tap()
            field.typeText("Toothpaste\n")
            let toothpaste = entry(app, layout == "rows" ? "entry.row" : "entry.tile", "Toothpaste")
            wait(for: [expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: toothpaste)], timeout: 5)
            assertEmpty(field)
            XCTAssertTrue(app.keyboards.firstMatch.exists)

            field.typeText("Birthday hats\n")
            assertEmpty(field)
            XCTAssertTrue(app.keyboards.firstMatch.exists)
            app.terminate()
        }
    }

    func testEditAndReadOnly() {
        for (language, appearance) in variants {
            let app = launch(language, appearance, "-fixture", "household")
            let row = app.buttons.matching(identifier: "entry.row").firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 10))
            row.tap()
            let save = app.buttons["entry.save"]
            XCTAssertTrue(save.waitForExistence(timeout: 10))
            XCTAssertTrue(app.textFields["entry.quantity"].exists)
            XCTAssertTrue(app.textFields["entry.note"].exists)
            XCTAssertTrue(app.buttons["entry.delete"].exists)
            attach(app, "edit-entry-\(language)-\(appearance)")
            app.buttons["entry.cancel"].tap()

            let switcher = app.buttons["main.switcher"]
            XCTAssertTrue(switcher.waitForExistence(timeout: 10))
            switcher.tap()
            let samsList = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Sam'")).firstMatch
            XCTAssertTrue(samsList.waitForExistence(timeout: 10))
            samsList.tap()

            let readOnly = app.staticTexts["main.readOnly"]
            XCTAssertTrue(readOnly.waitForExistence(timeout: 10))
            XCTAssertEqual(readOnly.label, language == "en" ? "Sam's list is read-only." : "Die Liste von Sam ist schreibgeschützt.")
            XCTAssertFalse(addFieldElement(app).isEnabled)
            XCTAssertFalse(app.buttons["entry.crossOff"].exists)
            attach(app, "readonly-\(language)-\(appearance)")

            app.descendants(matching: .any).matching(identifier: "entry.readOnly").firstMatch.tap()
            XCTAssertFalse(save.waitForExistence(timeout: 2))
            app.terminate()
        }
    }

    private let variants = [("en", "light"), ("en", "dark"), ("de", "light"), ("de", "dark")]

    /// The add field, once the first sync has enabled it.
    private func addField(_ app: XCUIApplication) -> XCUIElement {
        let field = addFieldElement(app)
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        wait(for: [expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: field)], timeout: 10)
        return field
    }

    /// Any type, because a multi-line text field is a text view to XCUITest.
    private func addFieldElement(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "main.addField").firstMatch
    }

    private func entry(_ app: XCUIApplication, _ identifier: String, _ text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == %@ AND label BEGINSWITH %@", identifier, text)).firstMatch
    }

    /// An empty field reports its placeholder as its value.
    private func assertEmpty(_ field: XCUIElement) {
        let value = field.value as? String ?? ""
        XCTAssertTrue(value.isEmpty || value == field.placeholderValue, "The add field still holds \(value)")
    }

    /// Short drags on the list without momentum, because a swipe can carry a row past the screen, and then it's out of
    /// the query.
    private func scrollUp(_ app: XCUIApplication, until element: XCUIElement) {
        let list = app.collectionViews.firstMatch
        let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        for _ in 0..<15 where !(element.exists && element.isHittable) {
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }

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
