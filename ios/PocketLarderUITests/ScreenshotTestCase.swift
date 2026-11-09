import UIKit
import XCTest

/// The helpers of the UI tests. Every test starts in the light appearance, and `attachBoth` switches the simulator.
@MainActor
class ScreenshotTestCase: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
        XCUIDevice.shared.appearance = .light
    }

    let languages = ["en", "de"]

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

    /// The app follows the simulator's appearance, which `setUp` and `attachBoth` set.
    func launch(_ language: String, _ extra: String...) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", language] + extra
        app.launch()
        return app
    }

    func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Attaches the screen in both appearances, named `name("light")` and `name("dark")`. `reopen` brings back a menu or
    /// popover that the switch closed.
    func attachBoth(_ app: XCUIApplication, reopen: (() -> Void)? = nil, _ name: (String) -> String) {
        let appearances: [(XCUIDevice.Appearance, String)] = [(.light, "light"), (.dark, "dark")]
        for (appearance, label) in appearances {
            XCUIDevice.shared.appearance = appearance
            let deadline = Date().addingTimeInterval(10)
            while isDark(app) != (appearance == .dark) && Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
            if isDark(app) != (appearance == .dark) { attach(app, "stuck-\(label)") }
            XCTAssertEqual(isDark(app), appearance == .dark, "The app didn't turn \(label)")
            reopen?()
            attach(app, name(label))
        }
    }

    /// Whether the screen's left edge, halfway down, is dark. The page behind the rows is black or white.
    private func isDark(_ app: XCUIApplication) -> Bool {
        guard let image = app.screenshot().image.cgImage,
              let edge = image.cropping(to: CGRect(x: 2, y: image.height / 2, width: 1, height: 1)) else { return false }
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            context?.draw(edge, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return pixel.prefix(3).map { Int($0) }.reduce(0, +) < 3 * 128
    }
}
