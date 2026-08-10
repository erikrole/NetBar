import XCTest

final class NetBarUITests: XCTestCase {
    @MainActor
    func testMenuBarPopoverShowsCoreNetworkStatus() throws {
        let app = XCUIApplication()
        app.launchEnvironment["NETBAR_SKIP_LOCATION_PERMISSION_REQUEST"] = "1"
        app.launch()

        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5), "NetBar status item did not appear")
        let statusDescriptions = [
            "Connected to the internet",
            "Checking internet access",
            "Connected to a local network",
            "No network connection",
        ]
        XCTAssertTrue(statusDescriptions.contains { statusItem.label.contains($0) })
        XCTAssertFalse(statusItem.label.contains("↓"))
        XCTAssertFalse(statusItem.label.contains("↑"))
        XCTAssertFalse(statusItem.label.contains("en0"))
        statusItem.click()
        XCTAssertTrue(app.staticTexts["LIVE THROUGHPUT"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Live while open"].exists)
        XCTAssertTrue(app.staticTexts["Connection"].exists)
        XCTAssertTrue(app.staticTexts["Router"].exists)
        XCTAssertTrue(app.staticTexts["Local address"].exists)
        XCTAssertTrue(app.staticTexts["GlobalProtect"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["GlobalProtectConnectionButton"].exists)
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
