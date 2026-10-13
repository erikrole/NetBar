import CoreWLAN
import Foundation

enum InternetState: String, Sendable {
    case checking
    case online
    case degraded
    case offline

    var title: String {
        switch self {
        case .checking: "Checking"
        case .online: "Online"
        case .degraded: "No internet response"
        case .offline: "Offline"
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .checking: "Checking internet connection"
        case .online: "Connected to the internet"
        case .degraded: "Connected to a local network, but the internet is not responding"
        case .offline: "No network connection"
        }
    }

    static func resolve(pathSatisfied: Bool, probe: ProbeResult) -> InternetState {
        guard pathSatisfied else { return .offline }
        return switch probe {
        case .pending: .checking
        case .succeeded: .online
        case .failed: .degraded
        }
    }
}

enum ProbeResult: Sendable {
    case pending
    case succeeded
    case failed
}

enum MonitoringCadence {
    static let throughputSampleInterval: TimeInterval = 1
    static let throughputMinimumInterval: TimeInterval = 0.5
    static let throughputMaximumInterval: TimeInterval = 5
    static let throughputTimerToleranceInteractive: TimeInterval = 0.1
    static let throughputTimerToleranceIdle: TimeInterval = 0.25
    static let interactiveMetadataInterval: TimeInterval = 10
    static let interactiveTimerTolerance: TimeInterval = 1
    static let backgroundRefreshInterval: TimeInterval = 30
    static let backgroundTimerTolerance: TimeInterval = 5
    static let internetProbeInterval: TimeInterval = 30
    static let globalProtectProcessInterval: TimeInterval = 60
}

enum TransportKind: String, Sendable {
    case wifi = "Wi-Fi"
    case ethernet = "Ethernet"
    case other = "Network"
    case none = "No route"
}

struct WiFiReading: Equatable, Sendable {
    var interfaceName: String?
    var ssid: String?
    var rssi: Int?
    var noise: Int?
    var transmitRate: Double?
    var channelNumber: Int?
    var channelBand: CWChannelBand?
    var channelWidth: CWChannelWidth?
    var isPowered: Bool
    var isAssociated = false

    var snr: Int? {
        guard let rssi, let noise else { return nil }
        return rssi - noise
    }

    var quality: String? {
        guard let rssi, rssi < 0 else { return nil }
        if rssi >= -55 { return "Excellent" }
        if rssi >= -67 { return "Good" }
        if rssi >= -75 { return "Fair" }
        return "Weak"
    }

    var channelDescription: String? {
        guard let channelNumber else { return nil }
        let band: String? = switch channelBand {
        case .band2GHz: "2.4 GHz"
        case .band5GHz: "5 GHz"
        case .band6GHz: "6 GHz"
        default: nil
        }
        return ["Channel \(channelNumber)", band].compactMap(\ .self).joined(separator: " · ")
    }

    func networkName(permissionDenied: Bool) -> String {
        if let ssid = ssid?.trimmingCharacters(in: .whitespacesAndNewlines), !ssid.isEmpty {
            return ssid
        }
        return permissionDenied ? "Name hidden" : "Unavailable"
    }
}

struct ActiveRoute: Equatable, Sendable {
    var interfaceName: String?
    var routerAddress: String?
}

struct EthernetConnection: Equatable, Sendable {
    let interfaceName: String
    let displayName: String
    let linkSpeedBitsPerSecond: UInt64?
    let localAddress: String?
}

struct NetworkReading: Equatable, Sendable {
    var state: InternetState = .checking
    var transport: TransportKind = .none
    var interfaceName: String?
    var interfaceDisplayName: String?
    var localAddress: String?
    var routerAddress: String?
    var ethernetLinkSpeedBitsPerSecond: UInt64?
    var ethernetConnections: [EthernetConnection] = []
    var globalProtectConnected = false
    var vpnInterfaceName: String?
    var wifi = WiFiReading(isPowered: false)
    var lastUpdated = Date()

    var friendlyTitle: String {
        switch transport {
        case .wifi:
            guard let ssid = wifi.ssid?.trimmingCharacters(in: .whitespacesAndNewlines), !ssid.isEmpty else {
                return "Wi-Fi"
            }
            return ssid
        case .ethernet:
            guard let ethernetLinkSpeedBitsPerSecond, ethernetLinkSpeedBitsPerSecond > 0 else {
                return "Ethernet"
            }
            return "Ethernet · \(LinkSpeedFormatter.string(ethernetLinkSpeedBitsPerSecond))"
        case .other:
            return interfaceDisplayName ?? "Network"
        case .none:
            return "No connection"
        }
    }

    var statusSubtitle: String {
        if transport == .wifi, state != .offline {
            return "\(state.title) · Wi-Fi"
        }
        return state.title
    }

    var inactiveEthernetConnection: EthernetConnection? {
        ethernetConnections.first { $0.interfaceName != interfaceName }
    }

    var accessibilitySummary: String {
        "\(state.accessibilityDescription). Using \(friendlyTitle)."
    }
}

enum LinkSpeedFormatter {
    static func string(_ bitsPerSecond: UInt64) -> String {
        if bitsPerSecond >= 1_000_000_000 {
            let gigabits = Double(bitsPerSecond) / 1_000_000_000
            let number = gigabits.rounded() == gigabits
                ? String(format: "%.0f", gigabits)
                : String(format: "%.1f", gigabits)
            return "\(number) Gbps"
        }
        let megabits = Double(bitsPerSecond) / 1_000_000
        return "\(String(format: "%.0f", megabits)) Mbps"
    }
}

enum ByteRateFormatter {
    static func string(_ bytesPerSecond: Double, compact: Bool = false) -> String {
        let value = max(0, bytesPerSecond)
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var scaled = value
        var unitIndex = 0
        while scaled >= 1_000, unitIndex < units.count - 1 {
            scaled /= 1_000
            unitIndex += 1
        }

        let number: String
        if compact {
            number = scaled >= 100 || unitIndex == 0
                ? String(format: "%.0f", scaled)
                : String(format: "%.1f", scaled)
            let compactUnits = ["B", "K", "M", "G"]
            return number + compactUnits[unitIndex]
        }

        number = scaled >= 100 || unitIndex == 0
            ? String(format: "%.0f", scaled)
            : String(format: "%.1f", scaled)
        return "\(number) \(units[unitIndex])"
    }
}

struct InterfaceCounters: Equatable, Sendable {
    let receivedBytes: UInt64
    let sentBytes: UInt64
}

struct ThroughputSnapshot: Equatable, Sendable {
    var downloadBytesPerSecond: Double = 0
    var uploadBytesPerSecond: Double = 0
    var downloadHistory: [Double] = []
    var uploadHistory: [Double] = []
}

struct RouteServiceCandidate: Equatable, Sendable {
    var interfaceName: String
    var routerAddress: String?
    var hasLocalAddress: Bool
}

enum ActiveRouteResolver {
    static func resolve(
        primaryInterface: String?,
        primaryRouter: String?,
        services: [RouteServiceCandidate] = []
    ) -> ActiveRoute {
        let primary = ActiveRoute(interfaceName: primaryInterface, routerAddress: primaryRouter)
        guard let primaryInterface, isTunnelInterface(primaryInterface) else { return primary }
        if let physical = services.first(where: { service in
            service.hasLocalAddress && !isTunnelInterface(service.interfaceName)
        }) {
            return ActiveRoute(
                interfaceName: physical.interfaceName,
                routerAddress: physical.routerAddress
            )
        }
        return primary
    }

    static func isTunnelInterface(_ name: String) -> Bool {
        ["utun", "ipsec", "ppp", "gif", "stf", "tun"].contains { name.hasPrefix($0) }
    }
}

struct ThroughputSessionTracker: Sendable {
    private(set) var interfaceName: String?
    private(set) var transport: TransportKind = .none
    private(set) var confirmedSSID: String?
    private var hasIdentity = false

    mutating func update(
        interfaceName: String?,
        transport: TransportKind,
        currentSSID: String?
    ) -> Bool {
        let normalizedSSID = Self.normalizedSSID(currentSSID)
        let interfaceChanged = self.interfaceName != interfaceName
        let transportChanged = self.transport != transport
        let ssidChanged = transport == .wifi
            && confirmedSSID != nil
            && normalizedSSID != nil
            && confirmedSSID != normalizedSSID
        let changed = !hasIdentity || interfaceChanged || transportChanged || ssidChanged

        hasIdentity = true
        self.interfaceName = interfaceName
        self.transport = transport
        if transport != .wifi {
            confirmedSSID = nil
        } else if interfaceChanged || transportChanged {
            confirmedSSID = normalizedSSID
        } else if let normalizedSSID {
            confirmedSSID = normalizedSSID
        }
        return changed
    }

    private static func normalizedSSID(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

struct ProbeRouteIdentity: Equatable, Sendable {
    let pathSatisfied: Bool
    let transport: TransportKind
    let interfaceName: String?
    let localAddress: String?
    let routerAddress: String?
    let vpnInterfaceName: String?
    let confirmedWiFiSSID: String?
    let wifiRouteGeneration: Int
}

enum ThroughputCalculator {
    static func rate(previous: UInt64, current: UInt64, interval: TimeInterval) -> Double {
        guard interval > 0 else { return 0 }
        guard current >= previous else { return 0 }
        return Double(current - previous) / interval
    }
}

enum ThroughputSampler {
    enum Action: Equatable {
        case record(download: Double, upload: Double)
        case keepBaseline
        case resetBaseline
    }

    static func action(
        previous: InterfaceCounters,
        current: InterfaceCounters,
        interval: TimeInterval
    ) -> Action {
        if interval <= 0 || interval > MonitoringCadence.throughputMaximumInterval {
            return .resetBaseline
        }
        if interval < MonitoringCadence.throughputMinimumInterval {
            return .keepBaseline
        }
        guard current.receivedBytes >= previous.receivedBytes,
              current.sentBytes >= previous.sentBytes
        else { return .resetBaseline }

        return .record(
            download: ThroughputCalculator.rate(
                previous: previous.receivedBytes,
                current: current.receivedBytes,
                interval: interval
            ),
            upload: ThroughputCalculator.rate(
                previous: previous.sentBytes,
                current: current.sentBytes,
                interval: interval
            )
        )
    }
}

enum ThroughputHistory {
    static func appending(_ value: Double, to history: [Double]) -> [Double] {
        var updated = history
        updated.append(value)
        let overflow = updated.count - ThroughputGraphMetrics.sampleCapacity
        if overflow > 0 {
            updated.removeFirst(overflow)
        }
        return updated
    }
}

enum ThroughputGraphMetrics {
    static let sampleCapacity = 60

    static func normalizedX(index: Int, sampleCount: Int) -> Double {
        guard sampleCount > 0 else { return 1 }
        let clampedCount = min(sampleCount, sampleCapacity)
        let clampedIndex = min(max(index, 0), clampedCount - 1)
        let slot = sampleCapacity - clampedCount + clampedIndex
        return Double(slot) / Double(sampleCapacity - 1)
    }

    static func scaleMaximum(for values: [Double]) -> Double {
        max((values.max() ?? 0) * 1.1, 1)
    }
}
