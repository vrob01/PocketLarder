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

    /// My account and Add a device. In English light it also sets Read-only and cancels the invite. No test taps a layout
    /// or appearance, because the app would keep that choice for every later launch without `-layout`.
    func testAccount() {
        for (language, appearance) in variants {
            let checks = language == "en" && appearance == "light"
            let app = launch(language, appearance, "-fixture", "household")
            // Once the first sync is in, so that the header has the name.
            _ = addField(app)
            let header = openAccount(app).label
            for part in ["Alex", "Admin", "fixture.invalid"] {
                XCTAssertTrue(header.contains(part), "The header reads \(header)")
            }
            let pickers = app.segmentedControls
            XCTAssertEqual(pickers.count, 2)
            for index in 0..<pickers.count {
                let options = pickers.element(boundBy: index).buttons
                for option in 0..<options.count {
                    let frame = options.element(boundBy: option).frame
                    XCTAssertGreaterThanOrEqual(frame.width, 44)
                    XCTAssertGreaterThanOrEqual(frame.height, 44, "Option \(option) of picker \(index) is too low")
                }
            }
            attach(app, "account-\(language)-\(appearance)")

            if checks {
                let open = app.buttons.matching(NSPredicate(format: "label == 'Open'")).firstMatch
                let readOnly = app.buttons.matching(NSPredicate(format: "label == 'Read-only'")).firstMatch
                XCTAssertTrue(open.isSelected)
                readOnly.tap()
                // Generous, because one query can take seconds on a busy simulator.
                wait(for: [expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: readOnly)], timeout: 20)
                XCTAssertFalse(open.isSelected)
            }

            let languageRow = withID(app.buttons, "account.language")
            scrollUp(app, in: app, until: languageRow)
            XCTAssertEqual(languageRow.value as? String, language == "en" ? "English" : "Deutsch")
            let addDevice = withID(app.buttons, "account.addDevice")
            scrollUp(app, in: app, until: addDevice)
            addDevice.tap()
            let qr = withID(app.images, "addDevice.qr")
            XCTAssertTrue(qr.waitForExistence(timeout: 20))
            // The sheet is still sliding up.
            Thread.sleep(forTimeInterval: 1)
            attach(app, "add-device-\(language)-\(appearance)")

            if checks {
                let cancel = withID(app.buttons, "addDevice.cancel")
                scrollUp(app, in: app, until: cancel)
                cancel.tap()
                XCTAssertTrue(qr.waitForNonExistence(timeout: 20), "Cancel invite didn't close the sheet")
            }
            app.terminate()
        }
    }

    /// Without a connection, Add a device says why and opens no sheet.
    func testAddDeviceOffline() {
        let app = launch("en", "light", "-fixture", "offline")
        _ = openAccount(app)
        let addDevice = withID(app.buttons, "account.addDevice")
        scrollUp(app, in: app, until: addDevice)
        addDevice.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 20))
        XCTAssertTrue(alert.staticTexts["Couldn't create an invite."].exists)
        XCTAssertTrue(alert.staticTexts["Needs a connection to your server. Can't reach fixture.invalid."].exists)
        XCTAssertFalse(withID(app.images, "addDevice.qr").exists)
        app.terminate()
    }

    /// My account > Invites with one invite of each state. In English light it also cancels the open one, clears the
    /// others, and then opens Sam's invites from his page.
    func testInvites() {
        for (language, appearance) in variants {
            let app = launch(language, appearance, "-fixture", "household")
            // Once the first sync is in, so that My account knows that Alex is an admin.
            _ = addField(app)
            _ = openAccount(app)
            let invitesRow = withID(app.buttons, "account.invites")
            scrollUp(app, in: app, until: invitesRow)
            invitesRow.tap()
            let rows = app.staticTexts.matching(NSPredicate(format: "identifier == 'invites.invite'"))
            XCTAssertTrue(rows.element(boundBy: 2).waitForExistence(timeout: 20))
            attach(app, "invites-\(language)-\(appearance)")

            if language == "en" && appearance == "light" {
                XCTAssertEqual(rows.count, 3)
                let cancel = withID(app.buttons, "invites.cancel")
                XCTAssertTrue(cancel.label.hasPrefix("Cancel invite, expiry: "), "The cancel button reads \(cancel.label)")
                cancel.tap()
                XCTAssertTrue(cancel.waitForNonExistence(timeout: 20), "The open invite is still listed")
                XCTAssertTrue(invite(app, "Used").exists, "The used invite is gone")
                XCTAssertTrue(invite(app, "Expired").exists, "The expired invite is gone")
                XCTAssertEqual(rows.count, 2)

                let clear = withID(app.buttons, "invites.clear")
                clear.tap()
                XCTAssertTrue(withID(app.staticTexts, "invites.empty").waitForExistence(timeout: 20))
                XCTAssertEqual(rows.count, 0)
                wait(for: [expectation(for: NSPredicate(format: "isEnabled == false"), evaluatedWith: clear)], timeout: 10)

                goBack(app)
                let membersRow = withID(app.buttons, "account.members")
                scrollUp(app, in: app, until: membersRow)
                membersRow.tap()
                let sam = entry(app, "members.member", "Sam")
                XCTAssertTrue(sam.waitForExistence(timeout: 20))
                sam.tap()
                let samInvites = withID(app.buttons, "member.invites")
                XCTAssertTrue(samInvites.waitForExistence(timeout: 10))
                samInvites.tap()
                XCTAssertTrue(invite(app, "Open").waitForExistence(timeout: 20))
                XCTAssertEqual(rows.count, 1)
            }
            app.terminate()
        }
    }

    /// Without a connection, Invites says why and shows no rows.
    func testInvitesOffline() {
        let app = launch("en", "light", "-fixture", "offline")
        _ = openAccount(app)
        let invitesRow = withID(app.buttons, "account.invites")
        scrollUp(app, in: app, until: invitesRow)
        invitesRow.tap()
        let failure = withID(app.staticTexts, "invites.loadFailure")
        XCTAssertTrue(failure.waitForExistence(timeout: 20))
        XCTAssertEqual(failure.label, "Couldn't load the invites. Needs a connection to your server. Can't reach fixture.invalid.")
        XCTAssertFalse(withID(app.staticTexts, "invites.empty").exists)
        app.terminate()
    }

    /// Members & devices, with Robin invited through the form. In English light it also signs out Sam's iPhone, removes
    /// Robin, and checks the refusals of a taken name and of the only admin's rights.
    func testMembers() {
        let invited = ["en": "Invited, not signed in yet", "de": "Eingeladen, noch nicht angemeldet"]
        for (language, appearance) in variants {
            let app = launch(language, appearance, "-fixture", "household")
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
            attach(app, "invite-member-\(language)-\(appearance)")

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
            attach(app, "members-\(language)-\(appearance)")

            entry(app, "members.member", "Sam").tap()
            let remove = withID(app.buttons, "member.remove")
            XCTAssertTrue(remove.waitForExistence(timeout: 10))
            let admin = withID(app.switches, "member.admin")
            XCTAssertEqual(admin.value as? String, "0")
            attach(app, "member-detail-\(language)-\(appearance)")

            if language == "en" && appearance == "light" {
                let signOut = withID(app.buttons, "member.signOut")
                XCTAssertEqual(signOut.label, "Sign out iPhone")
                signOut.tap()
                answer(app, "Sign out iPhone? Invites created on it are cancelled too.", with: "Sign out")
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

    private let variants = [("en", "light"), ("en", "dark"), ("de", "light"), ("de", "dark")]

    /// Opens My account from the circle and returns its header.
    private func openAccount(_ app: XCUIApplication) -> XCUIElement {
        let circle = app.buttons["main.account"]
        XCTAssertTrue(circle.waitForExistence(timeout: 10))
        circle.tap()
        let header = withID(app.staticTexts, "account.header")
        XCTAssertTrue(header.waitForExistence(timeout: 20))
        return header
    }

    /// The first element whose identifier is `identifier`. A subscript also compares its label, title, value and
    /// placeholder, and each of those is one more request to the app for every element in the query.
    private func withID(_ query: XCUIElementQuery, _ identifier: String) -> XCUIElement {
        query.matching(NSPredicate(format: "identifier == %@", identifier)).firstMatch
    }

    /// The ⇄ button of the entry that starts with `text`.
    private func moveButton(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == 'entry.move' AND label CONTAINS %@", text)).firstMatch
    }

    /// A store in the open menu, not the store's chip.
    private func storeItem(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@ AND NOT identifier BEGINSWITH 'chip.'", name)).firstMatch
    }

    /// Expects the row below the category header `header` and above the one named `before`, ignoring case.
    private func assertUnder(_ app: XCUIApplication, _ row: XCUIElement, _ header: String, before next: String?) {
        let top = app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", header)).firstMatch
        XCTAssertTrue(top.waitForExistence(timeout: 5), "No \(header) header")
        XCTAssertGreaterThan(row.frame.minY, top.frame.minY, "The row isn't under \(header)")
        if let next {
            let after = app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", next)).firstMatch
            if after.exists { XCTAssertLessThan(row.frame.minY, after.frame.minY, "The row is past \(next)") }
        }
    }

    /// Opens "Lists…" or "Stores & items…" from the switcher's menu.
    private func openSetup(_ app: XCUIApplication, _ label: String) {
        let switcher = app.buttons["main.switcher"]
        XCTAssertTrue(switcher.waitForExistence(timeout: 10))
        switcher.tap()
        let item = app.buttons[label]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()
    }

    /// Expects an alert with exactly `text`, and taps `button`. It may follow a request to the fixture.
    private func answer(_ app: XCUIApplication, _ text: String, with button: String) {
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 20))
        XCTAssertTrue(alert.staticTexts[text].exists, "No alert reads \(text)")
        alert.buttons[button].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
    }

    /// A member's page hides its back button while a request is open.
    private func goBack(_ app: XCUIApplication) {
        let back = app.buttons["BackButton"]
        XCTAssertTrue(back.waitForExistence(timeout: 20))
        back.tap()
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

    /// The invite row whose state reads `state`.
    private func invite(_ app: XCUIApplication, _ state: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "identifier == 'invites.invite' AND label BEGINSWITH %@", state)).firstMatch
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
    /// the query. On a sheet, `in: app` drags on the screen, because a list found by its rows is lost once they scroll away.
    private func scrollUp(_ app: XCUIApplication, in list: XCUIElement? = nil, until element: XCUIElement) {
        let list = list ?? app.collectionViews.firstMatch
        let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        // Stops checking once it's there, because every check is a query that can take seconds.
        for _ in 0..<15 {
            if element.exists && element.isHittable { break }
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
