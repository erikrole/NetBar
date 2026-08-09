import XCTest

final class NetBarUITests: XCTestCase {
    @MainActor
    func testMenuBarPopoverShowsCoreNetworkStatus() throws {
        let app = XCUIApplication()
        app.launchEnvironment["NETBAR_SKIP_LOCATION_PERMISSION_REQUEST"] = "1"
        app.launchEnvironment["NETBAR_OPEN_POPOVER_FOR_UI_TESTS"] = "1"
        app.launch()

        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5), "NetBar status item did not appear")
        XCTAssertFalse(statusItem.label.contains("↓"))
        XCTAssertFalse(statusItem.label.contains("↑"))
        XCTAssertFalse(statusItem.label.contains("en0"))
        XCTAssertTrue(app.staticTexts["LIVE THROUGHPUT"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Live while open"].exists)
        XCTAssertTrue(app.staticTexts["Connection"].exists)
        XCTAssertTrue(app.staticTexts["Router"].exists)
        XCTAssertTrue(app.staticTexts["Local address"].exists)
        XCTAssertTrue(app.staticTexts["GlobalProtect"].exists)
        XCTAssertTrue(app.staticTexts["Wi-Fi"].exists)
        XCTAssertFalse(app.staticTexts["en0"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["LaunchAtLoginToggle"].exists)
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "NetBar menu bar popover"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
