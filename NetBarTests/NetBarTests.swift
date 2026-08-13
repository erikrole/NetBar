import Darwin
import Foundation
import XCTest
@testable import NetBar

final class NetBarTests: XCTestCase {
    func testBackgroundMonitoringUsesLowFrequencyCadence() {
        XCTAssertEqual(MonitoringCadence.throughputSampleInterval, 1)
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

    func testInternetProbeRequiresAppleSuccessResponse() throws {
        let url = try XCTUnwrap(URL(string: "https://captive.apple.com/hotspot-detect.html"))
        let response = try XCTUnwrap(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        ))
        let data = Data("<HTML><BODY>Success</BODY></HTML>".utf8)

        XCTAssertTrue(InternetProbeValidator.isSuccessful(data: data, response: response))
    }

    func testInternetProbeRejectsCaptivePortalAndRedirectedResponses() throws {
        let appleURL = try XCTUnwrap(URL(string: "https://captive.apple.com/hotspot-detect.html"))
        let portalURL = try XCTUnwrap(URL(string: "https://login.example.com/portal"))
        let appleResponse = try XCTUnwrap(HTTPURLResponse(
            url: appleURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        ))
        let portalResponse = try XCTUnwrap(HTTPURLResponse(
            url: portalURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        ))

        XCTAssertFalse(InternetProbeValidator.isSuccessful(
            data: Data("<HTML><BODY>Sign in</BODY></HTML>".utf8),
            response: appleResponse
        ))
        XCTAssertFalse(InternetProbeValidator.isSuccessful(
            data: Data("<HTML><BODY>Success</BODY></HTML>".utf8),
            response: portalResponse
        ))
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

    func testProbeResultOnlyAppliesToTheRouteThatStartedIt() {
        XCTAssertTrue(NetworkMonitor.shouldApplyProbeResult(
            startedGeneration: 4,
            currentGeneration: 4
        ))
        XCTAssertFalse(NetworkMonitor.shouldApplyProbeResult(
            startedGeneration: 4,
            currentGeneration: 5
        ))
    }

    func testByteRateFormatting() {
        XCTAssertEqual(ByteRateFormatter.string(0), "0 B/s")
        XCTAssertEqual(ByteRateFormatter.string(1_500), "1.5 KB/s")
        XCTAssertEqual(ByteRateFormatter.string(2_500_000), "2.5 MB/s")
        XCTAssertEqual(ByteRateFormatter.string(2_500_000, compact: true), "2.5M")
    }

    func testWiFiQualityAndSNR() {
        let reading = WiFiReading(rssi: -61, noise: -92, isPowered: true, isAssociated: true)
        XCTAssertEqual(reading.quality, "Good")
        XCTAssertEqual(reading.snr, 31)
        XCTAssertNil(WiFiReading(rssi: 0, isPowered: true).quality)
    }

    func testWiFiAssociationRejectsCoreWLANErrorSentinels() {
        XCTAssertFalse(SystemNetworkReader.wifiAssociationIsActive(
            rssi: 0,
            noise: 0,
            transmitRate: 0,
            hasChannel: false
        ))
        XCTAssertTrue(SystemNetworkReader.wifiAssociationIsActive(
            rssi: -61,
            noise: -92,
            transmitRate: 173,
            hasChannel: true
        ))
        XCTAssertNil(SystemNetworkReader.validWiFiMeasurement(0))
        XCTAssertEqual(SystemNetworkReader.validWiFiMeasurement(-61), -61)
        XCTAssertNil(SystemNetworkReader.validWiFiTransmitRate(0))
        XCTAssertEqual(SystemNetworkReader.validWiFiTransmitRate(173), 173)
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

    func testOfflineWiFiIdentityKeepsTheAssociatedNetworkName() {
        var reading = NetworkReading()
        reading.state = .offline
        reading.transport = .wifi
        reading.wifi = WiFiReading(ssid: "Role", isPowered: true)

        XCTAssertEqual(reading.friendlyTitle, "Role")
    }

    func testThroughputSessionPreservesConfirmedSSIDAcrossUnknownReadings() {
        var tracker = ThroughputSessionTracker()

        XCTAssertTrue(tracker.update(interfaceName: "en0", transport: .wifi, currentSSID: "Home"))
        XCTAssertFalse(tracker.update(interfaceName: "en0", transport: .wifi, currentSSID: nil))
        XCTAssertEqual(tracker.confirmedSSID, "Home")
        XCTAssertTrue(tracker.update(interfaceName: "en0", transport: .wifi, currentSSID: "Office"))
        XCTAssertEqual(tracker.confirmedSSID, "Office")
    }

    func testThroughputSessionIgnoresPermissionRoundTripAndResetsForRouteChanges() {
        var tracker = ThroughputSessionTracker()

        XCTAssertTrue(tracker.update(interfaceName: "en0", transport: .wifi, currentSSID: "Home"))
        XCTAssertFalse(tracker.update(interfaceName: "en0", transport: .wifi, currentSSID: nil))
        XCTAssertFalse(tracker.update(interfaceName: "en0", transport: .wifi, currentSSID: "Home"))
        XCTAssertTrue(tracker.update(interfaceName: "en10", transport: .ethernet, currentSSID: "Office"))
        XCTAssertNil(tracker.confirmedSSID)
        XCTAssertFalse(tracker.update(interfaceName: "en10", transport: .ethernet, currentSSID: "Other"))
    }

    func testProbeRouteIdentityIncludesGatewayVPNAndWiFiEvents() {
        let baseline = ProbeRouteIdentity(
            pathSatisfied: true,
            transport: .wifi,
            interfaceName: "en0",
            localAddress: "192.168.1.10",
            routerAddress: "192.168.1.1",
            vpnInterfaceName: nil,
            confirmedWiFiSSID: "Home",
            wifiRouteGeneration: 4
        )

        XCTAssertNotEqual(baseline, ProbeRouteIdentity(
            pathSatisfied: true,
            transport: .wifi,
            interfaceName: "en0",
            localAddress: "192.168.1.10",
            routerAddress: "192.168.2.1",
            vpnInterfaceName: nil,
            confirmedWiFiSSID: "Home",
            wifiRouteGeneration: 4
        ))
        XCTAssertNotEqual(baseline, ProbeRouteIdentity(
            pathSatisfied: true,
            transport: .wifi,
            interfaceName: "en0",
            localAddress: "192.168.1.10",
            routerAddress: "192.168.1.1",
            vpnInterfaceName: "utun9",
            confirmedWiFiSSID: "Home",
            wifiRouteGeneration: 4
        ))
        XCTAssertNotEqual(baseline, ProbeRouteIdentity(
            pathSatisfied: true,
            transport: .wifi,
            interfaceName: "en0",
            localAddress: "192.168.1.10",
            routerAddress: "192.168.1.1",
            vpnInterfaceName: nil,
            confirmedWiFiSSID: "Home",
            wifiRouteGeneration: 5
        ))
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

    func testActiveIPv4TunnelRequiresAllRuntimeFlags() {
        let activeFlags = UInt32(IFF_UP | IFF_RUNNING | IFF_POINTOPOINT)

        XCTAssertTrue(SystemNetworkReader.isActiveIPv4Tunnel(
            flags: activeFlags,
            addressFamily: UInt8(AF_INET)
        ))
        XCTAssertFalse(SystemNetworkReader.isActiveIPv4Tunnel(
            flags: UInt32(IFF_UP | IFF_POINTOPOINT),
            addressFamily: UInt8(AF_INET)
        ))
        XCTAssertFalse(SystemNetworkReader.isActiveIPv4Tunnel(
            flags: activeFlags,
            addressFamily: UInt8(AF_INET6)
        ))
    }

    func testGlobalProtectServiceRequiresExpectedExecutablePath() {
        XCTAssertTrue(SystemNetworkReader.isGlobalProtectService(
            executableName: "PanGPS",
            executablePath: "/Applications/GlobalProtect.app/Contents/Resources/PanGPS"
        ))
        XCTAssertFalse(SystemNetworkReader.isGlobalProtectService(
            executableName: "PanGPS",
            executablePath: "/tmp/PanGPS"
        ))
        XCTAssertFalse(SystemNetworkReader.isGlobalProtectService(
            executableName: "OtherVPN",
            executablePath: "/Applications/GlobalProtect.app/Contents/Resources/PanGPS"
        ))
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
