import Darwin
import Foundation
import SystemConfiguration
import XCTest
@testable import NetBar

final class NetBarTests: XCTestCase {
    func testBackgroundMonitoringUsesLowFrequencyCadence() {
        XCTAssertEqual(MonitoringCadence.throughputSampleInterval, 1)
        XCTAssertEqual(MonitoringCadence.throughputMinimumInterval, 0.5)
        XCTAssertEqual(MonitoringCadence.throughputMaximumInterval, 5)
        XCTAssertEqual(MonitoringCadence.throughputTimerToleranceInteractive, 0.1)
        XCTAssertEqual(MonitoringCadence.throughputTimerToleranceIdle, 0.25)
        XCTAssertEqual(MonitoringCadence.interactiveMetadataInterval, 10)
        XCTAssertEqual(MonitoringCadence.interactiveTimerTolerance, 1)
        XCTAssertGreaterThanOrEqual(MonitoringCadence.backgroundRefreshInterval, 30)
        XCTAssertGreaterThanOrEqual(MonitoringCadence.internetProbeInterval, 30)
        XCTAssertGreaterThanOrEqual(MonitoringCadence.backgroundTimerTolerance, 5)
        XCTAssertGreaterThanOrEqual(MonitoringCadence.globalProtectProcessInterval, 60)
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

    func testWiFiNetworkNameDistinguishesHiddenPermissionFromMissingData() {
        let unnamed = WiFiReading(isPowered: true, isAssociated: true)
        XCTAssertEqual(unnamed.networkName(permissionDenied: true), "Name hidden")
        XCTAssertEqual(unnamed.networkName(permissionDenied: false), "Unavailable")

        let named = WiFiReading(ssid: " Role ", isPowered: true, isAssociated: true)
        XCTAssertEqual(named.networkName(permissionDenied: true), "Role")
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
        XCTAssertEqual(ThroughputGraphMetrics.normalizedX(index: 0, sampleCount: 60), 0)
        XCTAssertEqual(ThroughputGraphMetrics.normalizedX(index: 59, sampleCount: 60), 1)
        XCTAssertEqual(
            ThroughputGraphMetrics.normalizedX(index: -4, sampleCount: 10),
            ThroughputGraphMetrics.normalizedX(index: 0, sampleCount: 10)
        )
        XCTAssertEqual(ThroughputGraphMetrics.normalizedX(index: 80, sampleCount: 60), 1)
        XCTAssertEqual(ThroughputGraphMetrics.normalizedX(index: 0, sampleCount: 0), 1)
    }

    func testThroughputSamplerSkipsSpikesAndCounterRewinds() {
        let previous = InterfaceCounters(receivedBytes: 1_000, sentBytes: 2_000)
        let current = InterfaceCounters(receivedBytes: 4_000, sentBytes: 2_500)

        XCTAssertEqual(
            ThroughputSampler.action(previous: previous, current: current, interval: 1),
            .record(download: 3_000, upload: 500)
        )
        XCTAssertEqual(
            ThroughputSampler.action(previous: previous, current: current, interval: 2),
            .record(download: 1_500, upload: 250)
        )
        XCTAssertEqual(
            ThroughputSampler.action(previous: previous, current: current, interval: 0.2),
            .keepBaseline
        )
        XCTAssertEqual(
            ThroughputSampler.action(previous: previous, current: current, interval: 0),
            .resetBaseline
        )
        XCTAssertEqual(
            ThroughputSampler.action(previous: previous, current: current, interval: -1),
            .resetBaseline
        )
        XCTAssertEqual(
            ThroughputSampler.action(previous: previous, current: current, interval: 8),
            .resetBaseline
        )
        XCTAssertEqual(
            ThroughputSampler.action(
                previous: previous,
                current: InterfaceCounters(receivedBytes: 100, sentBytes: 9_000),
                interval: 1
            ),
            .resetBaseline
        )
    }

    func testThroughputHistoryKeepsTheNewestMinute() {
        let history = ThroughputHistory.appending(60, to: Array(0..<60).map(Double.init))
        XCTAssertEqual(history.count, 60)
        XCTAssertEqual(history.first, 1)
        XCTAssertEqual(history.last, 60)
        XCTAssertEqual(ThroughputHistory.appending(5, to: []), [5])
    }

    func testFriendlyEthernetOmitsUnknownOrZeroSpeed() {
        var reading = NetworkReading()
        reading.state = .online
        reading.transport = .ethernet
        XCTAssertEqual(reading.friendlyTitle, "Ethernet")
        reading.ethernetLinkSpeedBitsPerSecond = 0
        XCTAssertEqual(reading.friendlyTitle, "Ethernet")
    }

    func testRouteResolverKeepsPhysicalPrimaryAndSkipsTunnels() {
        let services = [
            RouteServiceCandidate(interfaceName: "utun4", routerAddress: "10.0.0.1", hasLocalAddress: true),
            RouteServiceCandidate(interfaceName: "en0", routerAddress: "192.168.1.1", hasLocalAddress: false),
            RouteServiceCandidate(interfaceName: "en7", routerAddress: "10.1.1.1", hasLocalAddress: true),
        ]

        XCTAssertEqual(
            ActiveRouteResolver.resolve(
                primaryInterface: "en0",
                primaryRouter: "192.168.1.1",
                services: services
            ),
            ActiveRoute(interfaceName: "en0", routerAddress: "192.168.1.1")
        )
        XCTAssertEqual(
            ActiveRouteResolver.resolve(
                primaryInterface: "utun3",
                primaryRouter: "10.8.0.1",
                services: services
            ),
            ActiveRoute(interfaceName: "en7", routerAddress: "10.1.1.1")
        )
        XCTAssertEqual(
            ActiveRouteResolver.resolve(
                primaryInterface: "ipsec0",
                primaryRouter: "172.16.0.1",
                services: [
                    RouteServiceCandidate(interfaceName: "en0", routerAddress: "192.168.0.1", hasLocalAddress: true)
                ]
            ),
            ActiveRoute(interfaceName: "en0", routerAddress: "192.168.0.1")
        )
        XCTAssertEqual(
            ActiveRouteResolver.resolve(
                primaryInterface: "utun3",
                primaryRouter: "10.8.0.1",
                services: [
                    RouteServiceCandidate(interfaceName: "en0", routerAddress: "192.168.1.1", hasLocalAddress: false)
                ]
            ),
            ActiveRoute(interfaceName: "utun3", routerAddress: "10.8.0.1")
        )
        XCTAssertEqual(
            ActiveRouteResolver.resolve(primaryInterface: nil, primaryRouter: nil, services: services),
            ActiveRoute()
        )
        XCTAssertTrue(ActiveRouteResolver.isTunnelInterface("utun12"))
        XCTAssertTrue(ActiveRouteResolver.isTunnelInterface("ipsec0"))
        XCTAssertTrue(ActiveRouteResolver.isTunnelInterface("ppp0"))
        XCTAssertTrue(ActiveRouteResolver.isTunnelInterface("tun0"))
        XCTAssertFalse(ActiveRouteResolver.isTunnelInterface("en0"))
        XCTAssertFalse(ActiveRouteResolver.isTunnelInterface("bridge0"))
    }

    func testInterfaceTypeParsing() {
        XCTAssertEqual(
            SystemNetworkReader.transport(forInterfaceType: kSCNetworkInterfaceTypeIEEE80211 as String),
            .wifi
        )
        XCTAssertEqual(
            SystemNetworkReader.transport(forInterfaceType: kSCNetworkInterfaceTypeEthernet as String),
            .ethernet
        )
        XCTAssertEqual(SystemNetworkReader.transport(forInterfaceType: "Bridge"), .other)
        XCTAssertNil(SystemNetworkReader.transport(forInterfaceType: nil))
    }

    func testEthernetMediaSpeedIgnoresOptionBitsAndExtendedSubtypes() {
        XCTAssertEqual(SystemNetworkReader.extendedEthernetSubtype(33), 0x1_0001)
        XCTAssertEqual(SystemNetworkReader.extendedEthernetSubtype(52), 0x1_0014)
        XCTAssertEqual(SystemNetworkReader.extendedEthernetSubtype(65), 0x2_0001)
        XCTAssertEqual(
            SystemNetworkReader.ethernetLinkSpeed(forMediaWord: IFM_ETHER | IFM_FDX | IFM_FLOW | IFM_1000_T),
            1_000_000_000
        )
        XCTAssertEqual(
            SystemNetworkReader.ethernetLinkSpeed(
                forMediaWord: IFM_ETHER | SystemNetworkReader.extendedEthernetSubtype(52)
            ),
            100_000_000
        )
        XCTAssertEqual(
            SystemNetworkReader.ethernetLinkSpeed(
                forMediaWord: IFM_ETHER | SystemNetworkReader.extendedEthernetSubtype(62)
            ),
            100_000_000
        )
        XCTAssertEqual(
            SystemNetworkReader.ethernetLinkSpeed(
                forMediaWord: IFM_ETHER | SystemNetworkReader.extendedEthernetSubtype(33)
            ),
            10_000_000_000
        )
        XCTAssertEqual(
            SystemNetworkReader.ethernetLinkSpeed(
                forMediaWord: IFM_ETHER | IFM_FDX | SystemNetworkReader.extendedEthernetSubtype(65)
            ),
            25_000_000_000
        )
        XCTAssertEqual(
            SystemNetworkReader.ethernetLinkSpeed(
                forMediaWord: IFM_ETHER | SystemNetworkReader.extendedEthernetSubtype(38)
            ),
            40_000_000_000
        )
        XCTAssertEqual(
            SystemNetworkReader.ethernetLinkSpeed(
                forMediaWord: IFM_ETHER | SystemNetworkReader.extendedEthernetSubtype(47)
            ),
            100_000_000_000
        )
        XCTAssertNil(SystemNetworkReader.ethernetLinkSpeed(forMediaWord: IFM_ETHER | IFM_AUTO))
        XCTAssertNil(SystemNetworkReader.ethernetLinkSpeed(forMediaWord: IFM_ETHER | IFM_HPNA_1))
        XCTAssertEqual(LinkSpeedFormatter.string(25_000_000_000), "25 Gbps")
        XCTAssertEqual(LinkSpeedFormatter.string(40_000_000_000), "40 Gbps")
        XCTAssertEqual(LinkSpeedFormatter.string(100_000_000_000), "100 Gbps")
    }

    func testInterfaceCounterParsingSkipsUnrelatedMessages() {
        let noise = routeMessage(if_msghdr()) { message in
            message.ifm_type = UInt8(RTM_IFINFO)
            message.ifm_index = 1
        }
        let info = routeMessage(if_msghdr2()) { message in
            message.ifm_type = UInt8(RTM_IFINFO2)
            message.ifm_index = 7
            message.ifm_data.ifi_ibytes = 4_096
            message.ifm_data.ifi_obytes = 512
        }
        var buffer = Data()
        buffer.append(noise)
        buffer.append(info)

        let matched = buffer.withUnsafeBytes { raw in
            SystemNetworkReader.interfaceCounters(
                in: raw,
                interfaceName: "en0",
                nameAtIndex: { $0 == 7 ? "en0" : "en1" }
            )
        }
        XCTAssertEqual(matched, InterfaceCounters(receivedBytes: 4_096, sentBytes: 512))

        let mismatch = buffer.withUnsafeBytes { raw in
            SystemNetworkReader.interfaceCounters(
                in: raw,
                interfaceName: "en0",
                nameAtIndex: { _ in "en1" }
            )
        }
        XCTAssertNil(mismatch)
    }

    func testInterfaceCounterParsingStopsOnTruncatedOrEmptyMessages() {
        var empty = if_msghdr2()
        empty.ifm_msglen = 0
        empty.ifm_type = UInt8(RTM_IFINFO2)
        let emptyCounters = withUnsafeBytes(of: empty) { raw in
            SystemNetworkReader.interfaceCounters(
                in: raw,
                interfaceName: "en0",
                nameAtIndex: { _ in "en0" }
            )
        }
        XCTAssertNil(emptyCounters)

        var truncated = if_msghdr()
        truncated.ifm_msglen = 4_096
        truncated.ifm_type = UInt8(RTM_IFINFO2)
        let truncatedCounters = withUnsafeBytes(of: truncated) { raw in
            SystemNetworkReader.interfaceCounters(
                in: raw,
                interfaceName: "en0",
                nameAtIndex: { _ in "en0" }
            )
        }
        XCTAssertNil(truncatedCounters)
        XCTAssertNil(SystemNetworkReader.interfaceCounters(
            in: UnsafeRawBufferPointer(start: nil, count: 0),
            interfaceName: "en0",
            nameAtIndex: { _ in "en0" }
        ))
    }

    private func routeMessage<T>(_ initial: T, configure: (inout T) -> Void) -> Data {
        var message = initial
        configure(&message)
        let size = MemoryLayout<T>.size
        var bytes = Data(count: size)
        bytes.withUnsafeMutableBytes { destination in
            withUnsafeBytes(of: &message) { source in
                destination.copyBytes(from: source.prefix(size))
            }
        }
        var length = UInt16(size)
        withUnsafeBytes(of: &length) { lengthBytes in
            bytes.replaceSubrange(0..<MemoryLayout<UInt16>.size, with: lengthBytes)
        }
        return bytes
    }
}
