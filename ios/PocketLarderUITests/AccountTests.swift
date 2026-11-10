import UIKit
import XCTest

@MainActor
final class AccountTests: ScreenshotTestCase {
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
}
