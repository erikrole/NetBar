import Foundation
import Network
import Observation

@MainActor
@Observable
final class NetworkMonitor {
    private(set) var reading = NetworkReading()

    private let reader = SystemNetworkReader()
    private let pathMonitor = NWPathMonitor()
    private let pathQueue = DispatchQueue(label: "com.erole.NetBar.path")
    private let probe = InternetProbe()
    private var backgroundTimer: Timer?
    private var interactiveTimer: Timer?
    private var interactiveTick = 0
    private var isInteractive = false
    private var pathSatisfied = false
    private var pathTransport: TransportKind = .none
    private var probeResult: ProbeResult = .pending
    private var previousCounters: InterfaceCounters?
    private var previousInterfaceName: String?
    private var previousSampleDate: Date?
    private var probeInFlight = false
    private var lastProbeDate = Date.distantPast

    init() {
        guard !Self.isRunningTests else { return }
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let transport = Self.transport(for: path)
            Task { @MainActor [weak self] in
                guard let self else { return }
                let routeChanged = pathSatisfied != (path.status == .satisfied)
                    || pathTransport != transport
                pathSatisfied = path.status == .satisfied
                pathTransport = transport
                if routeChanged {
                    probeResult = .pending
                    lastProbeDate = .distantPast
                }
                refreshMetadata()
                runProbeIfNeeded(force: routeChanged)
            }
        }
        pathMonitor.start(queue: pathQueue)

        refreshMetadata()
        startBackgroundTimer()
    }

    func startInteractiveMonitoring() {
        guard !isInteractive else { return }
        isInteractive = true
        interactiveTick = 0
        refreshMetadata()
        beginThroughputSession()
        runProbeIfNeeded()

        let timer = Timer(
            timeInterval: MonitoringCadence.interactiveSampleInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                sampleThroughput()
                interactiveTick += 1
                if interactiveTick.isMultiple(of: MonitoringCadence.interactiveMetadataInterval) {
                    refreshMetadata()
                    runProbeIfNeeded()
                }
            }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        interactiveTimer = timer
    }

    func stopInteractiveMonitoring() {
        guard isInteractive else { return }
        isInteractive = false
        interactiveTimer?.invalidate()
        interactiveTimer = nil
        previousCounters = nil
        previousInterfaceName = nil
        previousSampleDate = nil
        reading.downloadBytesPerSecond = 0
        reading.uploadBytesPerSecond = 0
    }

    func checkNow() {
        refreshMetadata()
        guard !probeInFlight else { return }
        probeResult = .pending
        reading.state = InternetState.resolve(pathSatisfied: pathSatisfied, probe: probeResult)
        runProbe()
    }

    private func startBackgroundTimer() {
        let timer = Timer(
            timeInterval: MonitoringCadence.backgroundRefreshInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                refreshMetadata()
                runProbeIfNeeded()
            }
        }
        timer.tolerance = MonitoringCadence.backgroundTimerTolerance
        RunLoop.main.add(timer, forMode: .common)
        backgroundTimer = timer
    }

    private func refreshMetadata() {
        let now = Date()
        let route = reader.activeRoute()
        let interfaceName = route.interfaceName
        let interfaceChanged = interfaceName != reading.interfaceName
        let tunnel = reader.globalProtectTunnel()
        let ethernetConnections = reader.activeEthernetConnections()
        var updated = reading
        updated.state = InternetState.resolve(pathSatisfied: pathSatisfied, probe: probeResult)
        updated.transport = if pathSatisfied, let interfaceName {
            reader.transport(forBSDName: interfaceName) ?? pathTransport
        } else {
            .none
        }
        updated.interfaceName = interfaceName
        updated.interfaceDisplayName = interfaceName.flatMap(reader.displayName)
        updated.localAddress = interfaceName.flatMap(reader.localIPv4Address)
        updated.routerAddress = route.routerAddress
        updated.ethernetConnections = ethernetConnections
        updated.ethernetLinkSpeedBitsPerSecond = ethernetConnections
            .first { $0.interfaceName == interfaceName }?
            .linkSpeedBitsPerSecond
        updated.globalProtectConnected = tunnel != nil
        updated.vpnInterfaceName = tunnel
        updated.wifi = reader.wifiReading()
        updated.lastUpdated = now
        reading = updated

        if interfaceChanged, isInteractive {
            beginThroughputSession()
        }
    }

    private func beginThroughputSession() {
        let interfaceName = reading.interfaceName
        previousInterfaceName = interfaceName
        previousCounters = interfaceName.flatMap(reader.counters)
        previousSampleDate = Date()
        reading.downloadBytesPerSecond = 0
        reading.uploadBytesPerSecond = 0
        reading.downloadHistory = []
        reading.uploadHistory = []
    }

    private func sampleThroughput() {
        let now = Date()
        guard let interfaceName = reading.interfaceName,
              interfaceName == previousInterfaceName,
              let previousCounters,
              let previousSampleDate,
              let counters = reader.counters(for: interfaceName)
        else {
            beginThroughputSession()
            return
        }

        let interval = now.timeIntervalSince(previousSampleDate)
        let downloadRate = ThroughputCalculator.rate(
            previous: previousCounters.receivedBytes,
            current: counters.receivedBytes,
            interval: interval
        )
        let uploadRate = ThroughputCalculator.rate(
            previous: previousCounters.sentBytes,
            current: counters.sentBytes,
            interval: interval
        )
        self.previousCounters = counters
        self.previousSampleDate = now
        reading.downloadBytesPerSecond = downloadRate
        reading.uploadBytesPerSecond = uploadRate
        reading.downloadHistory = Self.appending(downloadRate, to: reading.downloadHistory)
        reading.uploadHistory = Self.appending(uploadRate, to: reading.uploadHistory)
    }

    private func runProbeIfNeeded(force: Bool = false) {
        guard pathSatisfied, !probeInFlight else { return }
        guard force || Date().timeIntervalSince(lastProbeDate) >= MonitoringCadence.internetProbeInterval else {
            return
        }
        runProbe()
    }

    private func runProbe() {
        guard pathSatisfied else { return }
        probeInFlight = true
        lastProbeDate = Date()
        Task {
            let succeeded = await probe.check()
            probeResult = succeeded ? .succeeded : .failed
            probeInFlight = false
            reading.state = InternetState.resolve(pathSatisfied: pathSatisfied, probe: probeResult)
        }
    }

    nonisolated private static func transport(for path: NWPath) -> TransportKind {
        if path.usesInterfaceType(.wiredEthernet) { return .ethernet }
        if path.usesInterfaceType(.wifi) { return .wifi }
        if path.status == .satisfied { return .other }
        return .none
    }

    private static func appending(_ value: Double, to history: [Double]) -> [Double] {
        Array((history + [value]).suffix(ThroughputGraphMetrics.sampleCapacity))
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
