import UIKit
import XCTest

/// The helpers of the UI tests.
@MainActor
class ScreenshotTestCase: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    let variants = [("en", "light"), ("en", "dark"), ("de", "light"), ("de", "dark")]

    /// Opens My account from the circle and returns its header.
    func openAccount(_ app: XCUIApplication) -> XCUIElement {
        let circle = app.buttons["main.account"]
        XCTAssertTrue(circle.waitForExistence(timeout: 10))
        circle.tap()
        let header = withID(app.staticTexts, "account.header")
        XCTAssertTrue(header.waitForExistence(timeout: 20))
        return header
    }

    /// The first element whose identifier is `identifier`. A subscript also compares its label, title, value and
    /// placeholder, and each of those is one more request to the app for every element in the query.
    func withID(_ query: XCUIElementQuery, _ identifier: String) -> XCUIElement {
        query.matching(NSPredicate(format: "identifier == %@", identifier)).firstMatch
    }

    /// The ⇄ button of the entry that starts with `text`.
    func moveButton(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == 'entry.move' AND label CONTAINS %@", text)).firstMatch
    }

    /// A store in the open menu, not the store's chip.
    func storeItem(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@ AND NOT identifier BEGINSWITH 'chip.'", name)).firstMatch
    }

    /// Expects the row below the category header `header` and above the one named `before`, ignoring case.
    func assertUnder(_ app: XCUIApplication, _ row: XCUIElement, _ header: String, before next: String?) {
        let top = app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", header)).firstMatch
        XCTAssertTrue(top.waitForExistence(timeout: 5), "No \(header) header")
        XCTAssertGreaterThan(row.frame.minY, top.frame.minY, "The row isn't under \(header)")
        if let next {
            let after = app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", next)).firstMatch
            if after.exists { XCTAssertLessThan(row.frame.minY, after.frame.minY, "The row is past \(next)") }
        }
    }

    /// Opens "Lists…" or "Stores & items…" from the switcher's menu.
    func openSetup(_ app: XCUIApplication, _ label: String) {
        let switcher = app.buttons["main.switcher"]
        XCTAssertTrue(switcher.waitForExistence(timeout: 10))
        switcher.tap()
        let item = app.buttons[label]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()
    }

    /// Expects an alert with exactly `text`, and taps `button`. It may follow a request to the fixture.
    func answer(_ app: XCUIApplication, _ text: String, with button: String) {
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 20))
        XCTAssertTrue(alert.staticTexts[text].exists, "No alert reads \(text)")
        alert.buttons[button].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
    }

    /// A member's page hides its back button while a request is open.
    func goBack(_ app: XCUIApplication) {
        let back = app.buttons["BackButton"]
        XCTAssertTrue(back.waitForExistence(timeout: 20))
        back.tap()
    }

    /// Gives the add field focus, taps, and expects the keyboard gone.
    func hidesKeyboard(_ app: XCUIApplication, _ field: XCUIElement, _ name: String, by tap: () -> Void) {
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "No keyboard before tapping \(name)")
        tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "The keyboard stayed up after tapping \(name)")
    }

    /// The empty middle of the top bar, between the capsule and the account circle.
    func topBarMiddle(_ app: XCUIApplication) -> XCUICoordinate {
        let switcher = app.buttons["main.switcher"].frame
        let account = app.buttons["main.account"].frame
        return app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: (switcher.maxX + account.minX) / 2, dy: account.midY))
    }

    func offlinePopover(_ app: XCUIApplication, _ language: String, _ name: String) {
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
    func addField(_ app: XCUIApplication) -> XCUIElement {
        let field = addFieldElement(app)
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        wait(for: [expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: field)], timeout: 10)
        return field
    }

    /// Any type, because a multi-line text field is a text view to XCUITest.
    func addFieldElement(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "main.addField").firstMatch
    }

    func entry(_ app: XCUIApplication, _ identifier: String, _ text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == %@ AND label BEGINSWITH %@", identifier, text)).firstMatch
    }

    /// An empty field reports its placeholder as its value.
    func assertEmpty(_ field: XCUIElement) {
        let value = field.value as? String ?? ""
        XCTAssertTrue(value.isEmpty || value == field.placeholderValue, "The add field still holds \(value)")
    }

    /// Short drags on the list without momentum, because a swipe can carry a row past the screen, and then it's out of
    /// the query. On a sheet, `in: app` drags on the screen, because a list found by its rows is lost once they scroll away.
    func scrollUp(_ app: XCUIApplication, in list: XCUIElement? = nil, until element: XCUIElement) {
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

    func launch(_ language: String, _ appearance: String, _ extra: String...) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", language, "-appearance", appearance] + extra
        app.launch()
        return app
    }

    func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
