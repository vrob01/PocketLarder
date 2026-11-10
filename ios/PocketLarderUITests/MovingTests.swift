import UIKit
import XCTest

@MainActor
final class MovingTests: ScreenshotTestCase {
    /// Files Bell peppers at Market for the screenshots. In English light it also checks the no-op, a new category and the tile.
    func testMoving() {
        for (language, appearance) in variants {
            let app = launch(language, appearance, "-fixture", "household", "-layout", "rows")
            let field = addField(app)
            field.tap()
            field.typeText("Bell peppers\n")
            let peppers = entry(app, "entry.row", "Bell peppers")
            scrollUp(app, until: peppers)
            let move = moveButton(app, "Bell peppers")
            if language == "en" {
                XCTAssertEqual(move.label, "Move Bell peppers to another store")
            }
            XCTAssertGreaterThanOrEqual(move.frame.width, 44)
            XCTAssertGreaterThanOrEqual(move.frame.height, 44)
            XCTAssertTrue(app.keyboards.firstMatch.exists)
            move.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "The keyboard stayed up")
            for name in ["Market", "Drugstore", "Bakery"] {
                XCTAssertTrue(storeItem(app, name).waitForExistence(timeout: 5), "The menu has no \(name)")
            }
            storeItem(app, "Market").tap()

            let cancel = app.buttons["picker.cancel"]
            XCTAssertTrue(cancel.waitForExistence(timeout: 5))
            let categories = app.buttons.matching(identifier: "picker.category")
            XCTAssertTrue(categories.firstMatch.waitForExistence(timeout: 5))
            XCTAssertEqual((0..<categories.count).map { categories.element(boundBy: $0).label }, ["Produce", "Dairy", "Spices", "Beverages"])
            XCTAssertTrue(app.buttons["picker.newCategory"].exists)
            attach(app, "category-picker-\(language)-\(appearance)")
            categories.element(boundBy: 0).tap()
            XCTAssertTrue(cancel.waitForNonExistence(timeout: 5), "The picker stayed open")
            scrollUp(app, until: peppers)
            assertUnder(app, peppers, "Produce", before: "Dairy")

            moveButton(app, "Bell peppers").tap()
            XCTAssertTrue(storeItem(app, "Market").waitForExistence(timeout: 5))
            // The menu is still opening.
            Thread.sleep(forTimeInterval: 0.5)
            attach(app, "move-menu-\(language)-\(appearance)")

            if language == "en" && appearance == "light" {
                // Market is checked: nothing happens.
                storeItem(app, "Market").tap()
                XCTAssertTrue(storeItem(app, "Market").waitForNonExistence(timeout: 5))
                XCTAssertFalse(cancel.waitForExistence(timeout: 2), "The checked store opened the picker")
                XCTAssertFalse(app.buttons["entry.save"].exists)

                moveButton(app, "Bell peppers").tap()
                storeItem(app, "Drugstore").tap()
                app.buttons["picker.newCategory"].tap()
                let name = app.textFields["name.field"]
                XCTAssertTrue(name.waitForExistence(timeout: 5))
                name.tap()
                name.typeText("Vegetables")
                app.buttons["name.save"].tap()
                XCTAssertTrue(cancel.waitForNonExistence(timeout: 5), "The picker stayed open")
                XCTAssertTrue(name.waitForNonExistence(timeout: 5), "The form stayed open")
                // Drugstore is far down the list, so its chip brings Bell peppers to the top.
                app.buttons["chip.Drugstore"].tap()
                XCTAssertTrue(peppers.waitForExistence(timeout: 5))
                assertUnder(app, peppers, "Vegetables", before: nil)

                moveButton(app, "Bell peppers").tap()
                storeItem(app, "Market").tap()
                XCTAssertFalse(cancel.waitForExistence(timeout: 2), "Market has a placement, so nothing is asked")
                app.buttons["chip.Market"].tap()
                XCTAssertTrue(peppers.waitForExistence(timeout: 5))
                assertUnder(app, peppers, "Produce", before: "Dairy")
                XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ==[c] 'Vegetables'")).firstMatch.waitForNonExistence(timeout: 5))
            }
            app.terminate()

            if language == "en" && appearance == "light" {
                let tiles = launch(language, appearance, "-fixture", "household", "-layout", "tiles")
                let bananas = entry(tiles, "entry.tile", "Bananas")
                XCTAssertTrue(bananas.waitForExistence(timeout: 10))
                let tileMove = moveButton(tiles, "Bananas")
                XCTAssertGreaterThanOrEqual(tileMove.frame.width, 44)
                XCTAssertGreaterThanOrEqual(tileMove.frame.height, 44)
                tileMove.tap()
                storeItem(tiles, "Market").tap()
                XCTAssertFalse(tiles.buttons["picker.cancel"].waitForExistence(timeout: 2))
                XCTAssertTrue(bananas.exists, "Bananas was crossed off")
                tiles.terminate()
            }
        }
    }
}
