import Darwin
import XCTest
@testable import NetBar

final class NetBarTests: XCTestCase {
    func testBackgroundMonitoringUsesLowFrequencyCadence() {
        XCTAssertEqual(MonitoringCadence.interactiveSampleInterval, 1)
        XCTAssertEqual(MonitoringCadence.interactiveMetadataInterval, 10)
        XCTAssertGreaterThanOrEqual(MonitoringCadence.backgroundRefreshInterval, 30)
        XCTAssertGreaterThanOrEqual(MonitoringCadence.internetProbeInterval, 30)
        XCTAssertGreaterThanOrEqual(MonitoringCadence.backgroundTimerTolerance, 5)
    }

    func testInternetStateSeparatesRouteFromInternetResponse() {
        XCTAssertEqual(InternetState.resolve(pathSatisfied: false, probe: .succeeded), .offline)
        XCTAssertEqual(InternetState.resolve(pathSatisfied: true, probe: .pending), .checking)
        XCTAssertEqual(InternetState.resolve(pathSatisfied: true, probe: .failed), .degraded)
        XCTAssertEqual(InternetState.resolve(pathSatisfied: true, probe: .succeeded), .online)
    }

    func testThroughputUsesCounterDelta() {
        XCTAssertEqual(
            ThroughputCalculator.rate(previous: 1_000, current: 4_000, interval: 2),
            1_500
        )
    }

    func testThroughputRejectsCounterResetAndInvalidInterval() {
        XCTAssertEqual(ThroughputCalculator.rate(previous: 4_000, current: 1_000, interval: 1), 0)
        XCTAssertEqual(ThroughputCalculator.rate(previous: 1_000, current: 4_000, interval: 0), 0)
    }

    func testByteRateFormatting() {
        XCTAssertEqual(ByteRateFormatter.string(0), "0 B/s")
        XCTAssertEqual(ByteRateFormatter.string(1_500), "1.5 KB/s")
        XCTAssertEqual(ByteRateFormatter.string(2_500_000), "2.5 MB/s")
        XCTAssertEqual(ByteRateFormatter.string(2_500_000, compact: true), "2.5M")
    }

    func testWiFiQualityAndSNR() {
        let reading = WiFiReading(rssi: -61, noise: -92, isPowered: true)
        XCTAssertEqual(reading.quality, "Good")
        XCTAssertEqual(reading.snr, 31)
    }

    func testFriendlyWiFiIdentityUsesSSIDWithoutInterfaceName() {
        var reading = NetworkReading()
        reading.state = .online
        reading.transport = .wifi
        reading.interfaceName = "en0"
        reading.wifi = WiFiReading(ssid: "Role", isPowered: true)

        XCTAssertEqual(reading.friendlyTitle, "Role")
        XCTAssertEqual(reading.statusSubtitle, "Online · Wi-Fi")
        XCTAssertFalse(reading.accessibilitySummary.contains("en0"))
    }

    func testFriendlyWiFiIdentityFallsBackWhenNameIsUnavailable() {
        var reading = NetworkReading()
        reading.state = .online
        reading.transport = .wifi
        reading.wifi = WiFiReading(isPowered: true)

        XCTAssertEqual(reading.friendlyTitle, "Wi-Fi")
    }

    func testFriendlyEthernetIdentityIncludesNegotiatedSpeed() {
        var reading = NetworkReading()
        reading.state = .online
        reading.transport = .ethernet
        reading.ethernetLinkSpeedBitsPerSecond = 10_000_000_000

        XCTAssertEqual(reading.friendlyTitle, "Ethernet · 10 Gbps")
        XCTAssertEqual(reading.statusSubtitle, "Online")
    }

    func testOfflineIdentityDoesNotClaimAStaleNetwork() {
        var reading = NetworkReading()
        reading.state = .offline
        reading.transport = .wifi
        reading.wifi = WiFiReading(ssid: "Role", isPowered: true)

        XCTAssertEqual(reading.friendlyTitle, "No connection")
    }

    func testLinkSpeedFormatting() {
        XCTAssertEqual(LinkSpeedFormatter.string(100_000_000), "100 Mbps")
        XCTAssertEqual(LinkSpeedFormatter.string(1_000_000_000), "1 Gbps")
        XCTAssertEqual(LinkSpeedFormatter.string(2_500_000_000), "2.5 Gbps")
        XCTAssertEqual(LinkSpeedFormatter.string(10_000_000_000), "10 Gbps")
    }

    func testEthernetMediaSpeedMapping() {
        XCTAssertEqual(
            SystemNetworkReader.ethernetLinkSpeed(forMediaWord: IFM_ETHER | IFM_1000_T),
            1_000_000_000
        )
        XCTAssertEqual(
            SystemNetworkReader.ethernetLinkSpeed(forMediaWord: IFM_ETHER | IFM_10G_T),
            10_000_000_000
        )
    }

    func testInactiveEthernetExcludesThePrimaryRoute() {
        var reading = NetworkReading()
        reading.interfaceName = "en8"
        reading.ethernetConnections = [
            EthernetConnection(
                interfaceName: "en8",
                displayName: "Ethernet",
                linkSpeedBitsPerSecond: 10_000_000_000,
                localAddress: "192.168.1.10"
            ),
            EthernetConnection(
                interfaceName: "en9",
                displayName: "Ethernet",
                linkSpeedBitsPerSecond: 1_000_000_000,
                localAddress: nil
            )
        ]

        XCTAssertEqual(reading.inactiveEthernetConnection?.interfaceName, "en9")
    }

    func testThroughputGraphPreservesTrailingTimePosition() {
        XCTAssertEqual(ThroughputGraphMetrics.normalizedX(index: 0, sampleCount: 1), 1)
        XCTAssertEqual(ThroughputGraphMetrics.normalizedX(index: 0, sampleCount: 30), 30.0 / 59.0)
        XCTAssertEqual(ThroughputGraphMetrics.normalizedX(index: 29, sampleCount: 30), 1)
    }

    func testThroughputGraphScaleIncludesHeadroom() {
        XCTAssertEqual(ThroughputGraphMetrics.scaleMaximum(for: []), 1)
        XCTAssertEqual(ThroughputGraphMetrics.scaleMaximum(for: [10, 20]), 22, accuracy: 0.0001)
    }
}
