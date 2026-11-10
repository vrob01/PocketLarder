import UIKit
import XCTest

@MainActor
final class EditingTests: ScreenshotTestCase {
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
}
