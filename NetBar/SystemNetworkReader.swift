import CoreWLAN
import Darwin
import Foundation
import SystemConfiguration

struct SystemNetworkReader: Sendable {
    func activeRoute() -> ActiveRoute {
        guard let store = SCDynamicStoreCreate(nil, "NetBar" as CFString, nil, nil),
              let value = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString)
                as? [String: Any]
        else { return ActiveRoute() }
        let primaryInterface = value["PrimaryInterface"] as? String
        let services: [RouteServiceCandidate]
        if let primaryInterface, ActiveRouteResolver.isTunnelInterface(primaryInterface) {
            services = serviceCandidates(in: store)
        } else {
            services = []
        }
        return ActiveRouteResolver.resolve(
            primaryInterface: primaryInterface,
            primaryRouter: value["Router"] as? String,
            services: services
        )
    }

    private func serviceCandidates(in store: SCDynamicStore) -> [RouteServiceCandidate] {
        guard let setup = SCDynamicStoreCopyValue(store, "Setup:/Network/Global/IPv4" as CFString)
            as? [String: Any],
              let serviceOrder = setup["ServiceOrder"] as? [String]
        else { return [] }

        let addressed = interfaceNamesWithIPv4Address()
        return serviceOrder.compactMap { serviceID in
            let key = "State:/Network/Service/\(serviceID)/IPv4" as CFString
            guard let service = SCDynamicStoreCopyValue(store, key) as? [String: Any],
                  let interfaceName = service["InterfaceName"] as? String
            else { return nil }
            return RouteServiceCandidate(
                interfaceName: interfaceName,
                routerAddress: service["Router"] as? String,
                hasLocalAddress: addressed.contains(interfaceName)
            )
        }
    }

    private func interfaceNamesWithIPv4Address() -> Set<String> {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return [] }
        defer { freeifaddrs(pointer) }

        var names = Set<String>()
        for item in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let address = item.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET)
            else { continue }
            names.insert(String(cString: item.pointee.ifa_name))
        }
        return names
    }

    func interfaceFacts(forBSDName name: String) -> (displayName: String?, transport: TransportKind?) {
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else {
            return (nil, nil)
        }
        for interface in interfaces {
            guard SCNetworkInterfaceGetBSDName(interface) as String? == name else { continue }
            return (
                SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?,
                Self.transport(forInterfaceType: SCNetworkInterfaceGetInterfaceType(interface) as String?)
            )
        }
        return (nil, nil)
    }

    static func transport(forInterfaceType type: String?) -> TransportKind? {
        guard let type else { return nil }
        if type == kSCNetworkInterfaceTypeIEEE80211 as String { return .wifi }
        if type == kSCNetworkInterfaceTypeEthernet as String { return .ethernet }
        return .other
    }

    func localIPv4Address(for interfaceName: String) -> String? {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return nil }
        defer { freeifaddrs(pointer) }

        for item in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard String(cString: item.pointee.ifa_name) == interfaceName,
                  let address = item.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET)
            else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            if result == 0 {
                let bytes = host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
                return String(decoding: bytes, as: UTF8.self)
            }
        }
        return nil
    }

    func counters(for interfaceName: String) -> InterfaceCounters? {
        let interfaceIndex = interfaceName.withCString { if_nametoindex($0) }
        guard interfaceIndex != 0 else { return nil }
        var mib = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, Int32(interfaceIndex)]
        var length = 0
        guard sysctl(&mib, u_int(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return nil }

        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: length,
            alignment: MemoryLayout<if_msghdr2>.alignment
        )
        defer { buffer.deallocate() }
        guard sysctl(&mib, u_int(mib.count), buffer, &length, nil, 0) == 0 else { return nil }

        return Self.interfaceCounters(
            in: UnsafeRawBufferPointer(start: buffer, count: length),
            interfaceName: interfaceName,
            nameAtIndex: Self.interfaceName(at:)
        )
    }

    static func interfaceCounters(
        in buffer: UnsafeRawBufferPointer,
        interfaceName: String,
        nameAtIndex: (UInt32) -> String?
    ) -> InterfaceCounters? {
        let length = buffer.count
        guard let base = buffer.baseAddress else { return nil }
        var offset = 0
        while offset + MemoryLayout<if_msghdr>.size <= length {
            let header = base.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
            let messageLength = Int(header.ifm_msglen)
            guard messageLength > 0, offset + messageLength <= length else { break }

            if header.ifm_type == UInt8(RTM_IFINFO2), messageLength >= MemoryLayout<if_msghdr2>.size {
                let extended = base.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                if nameAtIndex(UInt32(extended.ifm_index)) == interfaceName {
                    return InterfaceCounters(
                        receivedBytes: extended.ifm_data.ifi_ibytes,
                        sentBytes: extended.ifm_data.ifi_obytes
                    )
                }
            }
            offset += messageLength
        }
        return nil
    }

    private static func interfaceName(at index: UInt32) -> String? {
        var nameBuffer = [CChar](repeating: 0, count: Int(IFNAMSIZ))
        guard if_indextoname(index, &nameBuffer) != nil else { return nil }
        return String(
            decoding: nameBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
            as: UTF8.self
        )
    }

    func wifiReading() -> WiFiReading {
#if DEBUG
        let fixtureSSID = ProcessInfo.processInfo.environment["NETBAR_UI_TEST_SSID"]
#endif
        guard let interface = CWWiFiClient.shared().interface() else {
#if DEBUG
            if let fixtureSSID {
                return Self.uiTestWiFiReading(ssid: fixtureSSID)
            }
#endif
            return WiFiReading(isPowered: false)
        }
        let isPowered = interface.powerOn()
        let rawRSSI = isPowered ? interface.rssiValue() : 0
        let rawNoise = isPowered ? interface.noiseMeasurement() : 0
        let rawTransmitRate = isPowered ? interface.transmitRate() : 0
        let channel = isPowered ? interface.wlanChannel() : nil
        let isAssociated = Self.wifiAssociationIsActive(
            rssi: rawRSSI,
            noise: rawNoise,
            transmitRate: rawTransmitRate,
            hasChannel: channel != nil
        )
        var reading = WiFiReading(
            interfaceName: interface.interfaceName,
            ssid: isAssociated ? interface.ssid() : nil,
            rssi: isAssociated ? Self.validWiFiMeasurement(rawRSSI) : nil,
            noise: isAssociated ? Self.validWiFiMeasurement(rawNoise) : nil,
            transmitRate: isAssociated ? Self.validWiFiTransmitRate(rawTransmitRate) : nil,
            channelNumber: isAssociated ? channel?.channelNumber : nil,
            channelBand: isAssociated ? channel?.channelBand : nil,
            channelWidth: isAssociated ? channel?.channelWidth : nil,
            isPowered: isPowered,
            isAssociated: isAssociated
        )
#if DEBUG
        if let fixtureSSID {
            reading = Self.uiTestWiFiReading(ssid: fixtureSSID)
        }
#endif
        return reading
    }

#if DEBUG
    private static func uiTestWiFiReading(ssid: String) -> WiFiReading {
        WiFiReading(
            interfaceName: "en0",
            ssid: ssid,
            rssi: -61,
            noise: -92,
            transmitRate: 173,
            channelNumber: 44,
            channelBand: .band5GHz,
            isPowered: true,
            isAssociated: true
        )
    }
#endif

    static func wifiAssociationIsActive(
        rssi: Int,
        noise: Int,
        transmitRate: Double,
        hasChannel: Bool
    ) -> Bool {
        rssi != 0 || noise != 0 || transmitRate > 0 || hasChannel
    }

    static func validWiFiMeasurement(_ value: Int) -> Int? {
        value == 0 ? nil : value
    }

    static func validWiFiTransmitRate(_ value: Double) -> Double? {
        value > 0 ? value : nil
    }

    func activeEthernetConnections() -> [EthernetConnection] {
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return [] }
        return interfaces.compactMap { interface in
            guard SCNetworkInterfaceGetInterfaceType(interface) as String? == kSCNetworkInterfaceTypeEthernet as String,
                  let name = SCNetworkInterfaceGetBSDName(interface) as String?,
                  let media = ethernetMedia(for: name),
                  media.isActive
            else { return nil }

            return EthernetConnection(
                interfaceName: name,
                displayName: SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? ?? "Ethernet",
                linkSpeedBitsPerSecond: media.linkSpeedBitsPerSecond,
                localAddress: localIPv4Address(for: name)
            )
        }
        .sorted { $0.interfaceName.localizedStandardCompare($1.interfaceName) == .orderedAscending }
    }

    func activeIPv4TunnelNames() -> [String] {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return [] }
        defer { freeifaddrs(pointer) }

        var names: [String] = []
        for item in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let name = String(cString: item.pointee.ifa_name)
            guard name.hasPrefix("utun"),
                  let address = item.pointee.ifa_addr,
                  Self.isActiveIPv4Tunnel(
                      flags: item.pointee.ifa_flags,
                      addressFamily: address.pointee.sa_family
                  ),
                  !names.contains(name)
            else { continue }
            names.append(name)
        }
        return names
    }

    func globalProtectProcessIsRunning() -> Bool {
        globalProtectServiceIsRunning()
    }

    static func isActiveIPv4Tunnel(flags: UInt32, addressFamily: UInt8) -> Bool {
        let requiredFlags = UInt32(IFF_UP | IFF_RUNNING | IFF_POINTOPOINT)
        return flags & requiredFlags == requiredFlags && addressFamily == UInt8(AF_INET)
    }

    private func globalProtectServiceIsRunning() -> Bool {
        var mib = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var length = 0
        guard sysctl(&mib, 4, nil, &length, nil, 0) == 0 else { return false }
        var processes = [kinfo_proc](repeating: kinfo_proc(), count: max(1, length / MemoryLayout<kinfo_proc>.stride))
        guard sysctl(&mib, 4, &processes, &length, nil, 0) == 0 else { return false }
        let count = length / MemoryLayout<kinfo_proc>.stride
        return processes.prefix(count).contains { process in
            let executableName = withUnsafePointer(to: process.kp_proc.p_comm) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN) + 1) {
                    String(cString: $0)
                }
            }
            guard executableName == "PanGPS" else { return false }

            var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            guard proc_pidpath(process.kp_proc.p_pid, &pathBuffer, UInt32(pathBuffer.count)) > 0 else {
                return false
            }
            let executablePath = String(
                decoding: pathBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
                as: UTF8.self
            )
            return Self.isGlobalProtectService(
                executableName: executableName,
                executablePath: executablePath
            )
        }
    }

    static func isGlobalProtectService(executableName: String, executablePath: String) -> Bool {
        executableName == "PanGPS"
            && executablePath.hasSuffix("/GlobalProtect.app/Contents/Resources/PanGPS")
    }

    private func ethernetMedia(for interfaceName: String) -> (isActive: Bool, linkSpeedBitsPerSecond: UInt64?)? {
        var request = ifmediareq()
        withUnsafeMutableBytes(of: &request.ifm_name) { bytes in
            for (index, byte) in interfaceName.utf8.prefix(Int(IFNAMSIZ) - 1).enumerated() {
                bytes[index] = byte
            }
        }

        let descriptor = socket(AF_INET, SOCK_DGRAM, 0)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }

        let command = UInt(0xC000_0000)
            | UInt(MemoryLayout<ifmediareq>.size << 16)
            | UInt(105 << 8)
            | 56
        guard ioctl(descriptor, command, &request) == 0 else { return nil }

        let statusIsValid = request.ifm_status & IFM_AVALID != 0
        let isActive = statusIsValid && request.ifm_status & IFM_ACTIVE != 0
        let isEthernet = request.ifm_active & IFM_NMASK == IFM_ETHER
        guard isEthernet else { return nil }
        return (isActive, Self.ethernetLinkSpeed(forMediaWord: request.ifm_active))
    }

    /// `IFM_X` from `net/if_media.h`. Swift does not import that macro.
    static func extendedEthernetSubtype(_ value: Int32) -> Int32 {
        let lowBits: Int32 = 0x1f
        let highBits: Int32 = 0x1e0
        return (value & lowBits) | ((value & highBits) << 11)
    }

    static func ethernetLinkSpeed(forMediaWord mediaWord: Int32) -> UInt64? {
        let subtype = mediaWord & IFM_TMASK
        if let extended = extendedSubtypeBitsPerSecond[subtype] {
            return extended
        }
        switch subtype {
        case IFM_10_T, IFM_10_2, IFM_10_5, IFM_10_STP, IFM_10_FL:
            return 10_000_000
        case IFM_100_TX, IFM_100_FX, IFM_100_T4, IFM_100_VG, IFM_100_T2:
            return 100_000_000
        case IFM_1000_SX, IFM_1000_LX, IFM_1000_CX, IFM_1000_T,
             IFM_1000_CX_SGMII, IFM_1000_KX:
            return 1_000_000_000
        case IFM_2500_T:
            return 2_500_000_000
        case IFM_5000_T:
            return 5_000_000_000
        case IFM_10G_SR, IFM_10G_LR, IFM_10G_CX4, IFM_10G_T,
             IFM_10G_KX4, IFM_10G_KR, IFM_10G_CR1, IFM_10G_ER:
            return 10_000_000_000
        case IFM_20G_KR2:
            return 20_000_000_000
        default:
            return nil
        }
    }

    /// Arguments are the `IFM_X(n)` values from `net/if_media.h`.
    private static let extendedSubtypeBitsPerSecond: [Int32: UInt64] = {
        let entries: [(Int32, UInt64)] = [
            (52, 100_000_000), // IFM_100_T
            (62, 100_000_000), // IFM_100_SGMII
            (41, 1_000_000_000), // IFM_1000_SGMII
            (32, 2_500_000_000), // IFM_2500_SX
            (36, 2_500_000_000), // IFM_2500_KX
            (63, 2_500_000_000), // IFM_2500_X
            (64, 5_000_000_000), // IFM_5000_KR
            (69, 5_000_000_000), // IFM_5000_KR_S
            (70, 5_000_000_000), // IFM_5000_KR1
            (33, 10_000_000_000), // IFM_10G_TWINAX
            (34, 10_000_000_000), // IFM_10G_TWINAX_LONG
            (35, 10_000_000_000), // IFM_10G_LRM
            (42, 10_000_000_000), // IFM_10G_SFI
            (59, 10_000_000_000), // IFM_10G_AOC
            (40, 25_000_000_000), // IFM_25G_PCIE
            (53, 25_000_000_000), // IFM_25G_CR
            (54, 25_000_000_000), // IFM_25G_KR
            (55, 25_000_000_000), // IFM_25G_SR
            (58, 25_000_000_000), // IFM_25G_LR
            (60, 25_000_000_000), // IFM_25G_ACC
            (61, 25_000_000_000), // IFM_25G_AOC
            (65, 25_000_000_000), // IFM_25G_T
            (66, 25_000_000_000), // IFM_25G_CR_S
            (67, 25_000_000_000), // IFM_25G_CR1
            (68, 25_000_000_000), // IFM_25G_KR_S
            (71, 25_000_000_000), // IFM_25G_AUI
            (86, 25_000_000_000), // IFM_25G_KR1
            (37, 40_000_000_000), // IFM_40G_CR4
            (38, 40_000_000_000), // IFM_40G_SR4
            (43, 40_000_000_000), // IFM_40G_XLPPI
            (44, 40_000_000_000), // IFM_40G_LR4
            (45, 40_000_000_000), // IFM_40G_KR4
            (72, 40_000_000_000), // IFM_40G_XLAUI
            (73, 40_000_000_000), // IFM_40G_XLAUI_AC
            (74, 40_000_000_000), // IFM_40G_ER4
            (47, 100_000_000_000), // IFM_100G_CR4
            (48, 100_000_000_000), // IFM_100G_SR4
            (49, 100_000_000_000), // IFM_100G_KR4
            (50, 100_000_000_000), // IFM_100G_LR4
        ]
        var speeds: [Int32: UInt64] = [:]
        for (rawSubtype, bitsPerSecond) in entries {
            speeds[extendedEthernetSubtype(rawSubtype)] = bitsPerSecond
        }
        return speeds
    }()
}
