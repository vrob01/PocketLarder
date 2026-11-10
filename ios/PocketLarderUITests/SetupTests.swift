import UIKit
import XCTest

@MainActor
final class SetupTests: ScreenshotTestCase {
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

            // Near the top edge, because the whole row is the target.
            market.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
            let storeName = app.textFields["store.name"]
            XCTAssertTrue(storeName.waitForExistence(timeout: 5))
            attach(app, "store-detail-\(language)-\(appearance)")
            if checks {
                app.buttons["store.delete"].tap()
                answer(app, "Delete Market? Its categories go too. Entries filed there move to Not filed yet.", with: "Cancel")
                XCTAssertEqual(storeName.value as? String, "Market")
            }
            app.buttons["BackButton"].tap()
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
                answer(app, "Delete Apples? Entries keep their name and move to Not filed yet.", with: "Cancel")
                XCTAssertEqual(app.textFields["item.name"].value as? String, "Apples")
            }
            app.buttons["BackButton"].tap()
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
}
