import UIKit
import XCTest

@MainActor
final class MainTests: ScreenshotTestCase {
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
}
