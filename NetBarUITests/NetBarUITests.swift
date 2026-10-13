import XCTest

final class NetBarUITests: XCTestCase {
    @MainActor
    func testMenuBarPopoverShowsCoreNetworkStatus() throws {
        let app = XCUIApplication()
        app.launchEnvironment["NETBAR_SKIP_LOCATION_PERMISSION_REQUEST"] = "1"
        app.launchEnvironment["NETBAR_UI_TEST_SSID"] = "NetBar Test Wi-Fi"
        app.launch()

        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5), "NetBar status item did not appear")
        let statusDescriptions = [
            "Connected to the internet",
            "Checking internet connection",
            "Connected to a local network",
            "No network connection",
        ]
        XCTAssertTrue(statusDescriptions.contains { statusItem.label.contains($0) })
        XCTAssertFalse(statusItem.label.contains("↓"))
        XCTAssertFalse(statusItem.label.contains("↑"))
        XCTAssertFalse(statusItem.label.contains("en0"))
        statusItem.click()
        XCTAssertTrue(app.staticTexts["Live throughput"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Last 60 seconds"].exists)
        XCTAssertTrue(app.staticTexts["Connection"].exists)
        XCTAssertTrue(app.staticTexts["Router"].exists)
        XCTAssertTrue(app.staticTexts["Local address"].exists)
        XCTAssertTrue(app.staticTexts["GlobalProtect"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["GlobalProtectConnectionButton"].exists)
        XCTAssertTrue(app.staticTexts["Wi-Fi"].exists)
        XCTAssertTrue(app.staticTexts["NetBar Test Wi-Fi"].firstMatch.exists)
        if app.staticTexts["Connected, not active"].exists {
            XCTAssertTrue(app.staticTexts["Network"].exists)
        }
        let transmitRate = app.staticTexts["Transmit rate"]
        let channel = app.staticTexts["Channel"]
        XCTAssertTrue(transmitRate.exists)
        XCTAssertTrue(channel.exists)
        XCTAssertFalse(app.buttons["Allow Wi-Fi network name"].exists)
        XCTAssertFalse(app.staticTexts["en0"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["LaunchAtLoginToggle"].exists)
        let popover = app.popovers.firstMatch
        XCTAssertTrue(popover.exists)
        XCTAssertTrue(popover.frame.contains(transmitRate.frame))
        XCTAssertTrue(popover.frame.contains(channel.frame))
        let screenshot = popover.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "NetBar menu bar popover"
        attachment.lifetime = .deleteOnSuccess
        add(attachment)
    }
}
