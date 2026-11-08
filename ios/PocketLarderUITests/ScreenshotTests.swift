import UIKit
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

    /// Every tap above the add bar hides the keyboard and still does its job.
    func testKeyboardHides() {
        // Each step stands alone, so that one failure doesn't hide the others.
        continueAfterFailure = true
        let app = launch("en", "light", "-fixture", "household", "-layout", "rows")
        let field = addField(app)

        let market = app.buttons["chip.Market"]
        hidesKeyboard(app, field, "the Market chip") { market.tap() }
        wait(for: [expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: market)], timeout: 5)
        app.buttons["chip.all"].tap()

        hidesKeyboard(app, field, "the top bar") { topBarMiddle(app).tap() }
        hidesKeyboard(app, field, "a store header") {
            app.descendants(matching: .any).matching(identifier: "main.storeHeader").firstMatch.tap()
        }

        let crossOff = app.buttons.matching(identifier: "entry.crossOff").firstMatch
        let crossedOff = crossOff.value as? String ?? ""
        hidesKeyboard(app, field, "a cross-off circle") { crossOff.tap() }
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier == 'entry.crossOff' AND value == %@", crossedOff))
            .firstMatch.waitForNonExistence(timeout: 5), "\(crossedOff) is still open")

        let save = app.buttons["entry.save"]
        hidesKeyboard(app, field, "a row") { app.buttons.matching(identifier: "entry.row").firstMatch.tap() }
        XCTAssertTrue(save.waitForExistence(timeout: 5), "The row opened no sheet")
        app.buttons["entry.cancel"].tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 5))

        hidesKeyboard(app, field, "the switcher") { app.buttons["main.switcher"].tap() }
        let myView = app.buttons.matching(NSPredicate(format: "label == 'My view' AND identifier != 'main.switcher'")).firstMatch
        XCTAssertTrue(myView.waitForExistence(timeout: 5), "The switcher's menu didn't open")
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        myView.tap()
        XCTAssertTrue(myView.waitForNonExistence(timeout: 5))

        hidesKeyboard(app, field, "the list picker") { app.buttons["main.chooseTarget"].tap() }
        let shared = app.buttons["Shared"]
        XCTAssertTrue(shared.waitForExistence(timeout: 5), "The list picker didn't open")
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        app.buttons.matching(NSPredicate(format: "label == 'My list' AND identifier != 'main.addToTarget'")).firstMatch.tap()
        XCTAssertTrue(shared.waitForNonExistence(timeout: 5))

        // The text stays, and the suggestions go and come back with the keyboard.
        let suggestion = app.buttons.matching(identifier: "main.suggestion").firstMatch
        field.tap()
        field.typeText("mi")
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5))
        topBarMiddle(app).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "The keyboard stayed up with text typed")
        XCTAssertEqual(field.value as? String, "mi")
        XCTAssertTrue(suggestion.waitForNonExistence(timeout: 5))
        field.tap()
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5))
        app.terminate()

        let tiles = launch("en", "light", "-fixture", "household", "-layout", "tiles")
        let tilesField = addField(tiles)
        let tile = tiles.buttons.matching(identifier: "entry.tile").firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 10))
        let tileLabel = tile.label
        hidesKeyboard(tiles, tilesField, "a tile") { tile.tap() }
        XCTAssertTrue(tiles.buttons.matching(NSPredicate(format: "identifier == 'entry.tile' AND label == %@", tileLabel))
            .firstMatch.waitForNonExistence(timeout: 5), "\(tileLabel) is still open")
        tiles.terminate()
    }

    /// The list's name adds like Return, and only the arrow opens the list picker.
    func testSplitAddButton() {
        let app = launch("en", "light", "-fixture", "household", "-layout", "rows")
        let field = addField(app)
        let add = app.buttons["main.addToTarget"]
        let choose = app.buttons["main.chooseTarget"]
        XCTAssertGreaterThanOrEqual(choose.frame.width, 44)
        XCTAssertGreaterThanOrEqual(choose.frame.height, 44)
        XCTAssertGreaterThanOrEqual(add.frame.height, 44)
        XCTAssertGreaterThanOrEqual(add.frame.width, 3 * choose.frame.width)
        XCTAssertEqual(add.label, "My list")

        field.tap()
        field.typeText("Birthday hats")
        add.tap()
        assertEmpty(field)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertTrue(entry(app, "entry.row", "Birthday hats").waitForExistence(timeout: 5))

        choose.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        let shared = app.buttons["Shared"]
        XCTAssertTrue(shared.waitForExistence(timeout: 5))
        shared.tap()
        wait(for: [expectation(for: NSPredicate(format: "label == 'Shared'"), evaluatedWith: add)], timeout: 5)

        field.tap()
        field.typeText("Party cups")
        add.tap()
        let onShared = NSPredicate(format: "identifier == 'entry.row' AND label BEGINSWITH 'Party cups' AND label CONTAINS 'Shared'")
        XCTAssertTrue(app.buttons.matching(onShared).firstMatch.waitForExistence(timeout: 5))
        app.terminate()
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

    /// Archives BBQ Sat for the screenshot. In English light it also restores it and adds a list.
    func testLists() {
        for (language, appearance) in variants {
            let app = launch(language, appearance, "-fixture", "household")
            openSetup(app, language == "en" ? "Lists…" : "Listen…")
            let bbq = entry(app, "lists.list", "BBQ Sat")
            XCTAssertTrue(bbq.waitForExistence(timeout: 10))
            bbq.tap()
            let archive = app.buttons["list.archive"]
            XCTAssertTrue(archive.waitForExistence(timeout: 5))
            archive.tap()
            XCTAssertTrue(archive.waitForNonExistence(timeout: 5), "Archiving didn't close the form")

            let restore = app.buttons["lists.restore"]
            XCTAssertTrue(restore.waitForExistence(timeout: 5))
            let archived = app.staticTexts["lists.archived"]
            XCTAssertTrue(archived.exists)
            XCTAssertGreaterThan(restore.frame.minY, archived.frame.maxY)
            let archivedBBQ = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'BBQ Sat'")).firstMatch
            XCTAssertGreaterThan(archivedBBQ.frame.minY, archived.frame.maxY)
            XCTAssertFalse(bbq.exists)
            XCTAssertTrue(entry(app, "lists.list", "Shared").exists)
            XCTAssertTrue(app.buttons["lists.add"].exists)
            attach(app, "lists-\(language)-\(appearance)")

            if language == "en" && appearance == "light" {
                restore.tap()
                XCTAssertTrue(bbq.waitForExistence(timeout: 5))
                XCTAssertFalse(archived.exists)

                app.buttons["lists.add"].tap()
                let save = app.buttons["list.save"]
                XCTAssertTrue(save.waitForExistence(timeout: 5))
                XCTAssertFalse(save.isEnabled)
                let name = app.textFields["list.name"]
                name.tap()
                name.typeText("Picnic")
                XCTAssertTrue(save.isEnabled)
                save.tap()
                XCTAssertTrue(entry(app, "lists.list", "Picnic").waitForExistence(timeout: 5))
            }
            app.terminate()
        }
    }

    /// Files Apples in a second store for the item screenshots. In English light it also searches and cancels deletes.
    func testStoresAndItems() {
        let alsoAt = ["en": ", also at 1 other store", "de": ", auch in 1 anderen Laden"]
        for (language, appearance) in variants {
            let checks = language == "en" && appearance == "light"
            let app = launch(language, appearance, "-fixture", "household")
            openSetup(app, language == "en" ? "Stores & items…" : "Läden & Artikel…")
            let market = entry(app, "stores.store", "Market")
            XCTAssertTrue(market.waitForExistence(timeout: 10))
            let stores = app.buttons.matching(identifier: "stores.store")
            XCTAssertEqual(stores.count, 3)
            for (index, name) in ["Market", "Drugstore", "Bakery"].enumerated() {
                XCTAssertTrue(stores.element(boundBy: index).label.hasPrefix(name), "Store \(index) isn't \(name)")
            }
            attach(app, "stores-\(language)-\(appearance)")

            market.tap()
            let storeName = app.textFields["store.name"]
            XCTAssertTrue(storeName.waitForExistence(timeout: 5))
            attach(app, "store-detail-\(language)-\(appearance)")
            if checks {
                app.buttons["store.delete"].tap()
                cancelDelete(app, "Delete Market? Its categories go too. Entries filed there move to Not filed yet.")
                XCTAssertEqual(storeName.value as? String, "Market")
            }
            app.navigationBars["Market"].buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.navigationBars["Market"].waitForNonExistence(timeout: 5))
            XCTAssertTrue(market.exists)

            app.segmentedControls.firstMatch.buttons.element(boundBy: 1).tap()
            let apples = entry(app, "items.item", "Apples")
            XCTAssertTrue(apples.waitForExistence(timeout: 5))
            apples.tap()
            let bakery = app.descendants(matching: .any).matching(identifier: "item.category.Bakery").firstMatch
            XCTAssertTrue(bakery.waitForExistence(timeout: 5))
            bakery.tap()
            let bread = app.buttons["Bread"]
            XCTAssertTrue(bread.waitForExistence(timeout: 5))
            bread.tap()
            // The menu is still closing.
            Thread.sleep(forTimeInterval: 1)
            attach(app, "item-detail-\(language)-\(appearance)")
            if checks {
                app.buttons["item.delete"].tap()
                cancelDelete(app, "Delete Apples? Entries keep their name and move to Not filed yet.")
                XCTAssertEqual(app.textFields["item.name"].value as? String, "Apples")
            }
            app.navigationBars["Apples"].buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.navigationBars["Apples"].waitForNonExistence(timeout: 5))

            let placed = NSPredicate(format: "identifier == 'items.item' AND label BEGINSWITH 'Apples' AND label CONTAINS %@", alsoAt[language]!)
            XCTAssertTrue(app.buttons.matching(placed).firstMatch.waitForExistence(timeout: 5))
            attach(app, "items-\(language)-\(appearance)")
            if checks {
                let search = app.textFields["items.search"]
                search.tap()
                search.typeText("mil")
                XCTAssertTrue(entry(app, "items.item", "Milk").waitForExistence(timeout: 5))
                XCTAssertTrue(entry(app, "items.item", "Oat milk").exists)
                XCTAssertFalse(apples.exists)
            }
            app.terminate()
        }
    }

    private let variants = [("en", "light"), ("en", "dark"), ("de", "light"), ("de", "dark")]

    /// Opens "Lists…" or "Stores & items…" from the switcher's menu.
    private func openSetup(_ app: XCUIApplication, _ label: String) {
        let switcher = app.buttons["main.switcher"]
        XCTAssertTrue(switcher.waitForExistence(timeout: 10))
        switcher.tap()
        let item = app.buttons[label]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()
    }

    /// Expects the delete question with exactly `text`, and cancels it.
    private func cancelDelete(_ app: XCUIApplication, _ text: String) {
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts[text].exists, "No alert reads \(text)")
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
    }

    /// Gives the add field focus, taps, and expects the keyboard gone.
    private func hidesKeyboard(_ app: XCUIApplication, _ field: XCUIElement, _ name: String, by tap: () -> Void) {
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "No keyboard before tapping \(name)")
        tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "The keyboard stayed up after tapping \(name)")
    }

    /// The empty middle of the top bar, between the capsule and the account circle.
    private func topBarMiddle(_ app: XCUIApplication) -> XCUICoordinate {
        let switcher = app.buttons["main.switcher"].frame
        let account = app.buttons["main.account"].frame
        return app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: (switcher.maxX + account.minX) / 2, dy: account.midY))
    }

    private func offlinePopover(_ app: XCUIApplication, _ language: String, _ name: String) {
        let badge = app.buttons["main.offline"]
        XCTAssertTrue(badge.waitForExistence(timeout: 10))
        badge.tap()
        let text = app.staticTexts["main.offlineText"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        XCTAssertEqual(text.label, language == "en"
            ? "Can't reach fixture.invalid. No changes are waiting to be sent."
            : "fixture.invalid ist nicht erreichbar. Es warten keine Änderungen darauf, gesendet zu werden.")
        // The bubble is still growing.
        Thread.sleep(forTimeInterval: 0.5)
        attach(app, name)
        app.terminate()
    }

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
