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
    private var wifiEventMonitor: WiFiEventMonitor?
    private var backgroundTimer: Timer?
    private var interactiveTimer: Timer?
    private var throughputTimer: Timer?
    private var isInteractive = false
    private var pathSatisfied = false
    private var pathTransport: TransportKind = .none
    private var probeResult: ProbeResult = .pending
    private var previousCounters: InterfaceCounters?
    private var previousSampleDate: Date?
    private var throughputSession = ThroughputSessionTracker()
    private var probeInFlight = false
    private var lastProbeDate = Date.distantPast
    private var probeGeneration = 0
    private var probeRouteIdentity: ProbeRouteIdentity?
    private var wifiRouteGeneration = 0

    init() {
        guard !Self.isRunningTests else { return }
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let transport = Self.transport(for: path)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.pathSatisfied = path.status == .satisfied
                self.pathTransport = transport
                self.refreshMetadata()
                self.runProbeIfNeeded()
            }
        }
        pathMonitor.start(queue: pathQueue)
        wifiEventMonitor = WiFiEventMonitor { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.reading.transport == .wifi {
                    self.wifiRouteGeneration &+= 1
                }
                self.refreshMetadata()
                self.runProbeIfNeeded()
            }
        }

        refreshMetadata()
        startThroughputTimer()
        startBackgroundTimer()
    }

    func startInteractiveMonitoring() {
        guard !isInteractive else { return }
        isInteractive = true
        refreshMetadata()
        runProbeIfNeeded()

        let timer = Timer(
            timeInterval: MonitoringCadence.interactiveMetadataInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refreshMetadata()
                self.runProbeIfNeeded()
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
    }

    func checkNow() {
        refreshMetadata()
        guard !probeInFlight else { return }
        probeResult = .pending
        reading.state = InternetState.resolve(pathSatisfied: pathSatisfied, probe: probeResult)
        runProbe()
    }

    func refreshNetworkDetails() {
        refreshMetadata()
        runProbeIfNeeded()
    }

    private func startBackgroundTimer() {
        let timer = Timer(
            timeInterval: MonitoringCadence.backgroundRefreshInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard !self.isInteractive else { return }
                self.refreshMetadata()
                self.runProbeIfNeeded()
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
        let tunnel = reader.globalProtectTunnel()
        let ethernetConnections = reader.activeEthernetConnections()
        let wifi = reader.wifiReading()
        let localAddress = interfaceName.flatMap(reader.localIPv4Address)
        var updated = reading
        updated.state = InternetState.resolve(pathSatisfied: pathSatisfied, probe: probeResult)
        updated.transport = if let interfaceName {
            reader.transport(forBSDName: interfaceName) ?? pathTransport
        } else if pathSatisfied {
            pathTransport
        } else {
            .none
        }
        let throughputSessionChanged = throughputSession.update(
            interfaceName: interfaceName,
            transport: updated.transport,
            currentSSID: wifi.isAssociated ? wifi.ssid : nil
        )
        updated.interfaceName = interfaceName
        updated.interfaceDisplayName = interfaceName.flatMap(reader.displayName)
        updated.localAddress = localAddress
        updated.routerAddress = route.routerAddress
        updated.ethernetConnections = ethernetConnections
        updated.ethernetLinkSpeedBitsPerSecond = ethernetConnections
            .first { $0.interfaceName == interfaceName }?
            .linkSpeedBitsPerSecond
        updated.globalProtectConnected = tunnel != nil
        updated.vpnInterfaceName = tunnel
        updated.wifi = wifi
        updated.lastUpdated = now
        let probeRouteIdentity = ProbeRouteIdentity(
            pathSatisfied: pathSatisfied,
            transport: updated.transport,
            interfaceName: interfaceName,
            localAddress: localAddress,
            routerAddress: route.routerAddress,
            vpnInterfaceName: tunnel,
            confirmedWiFiSSID: updated.transport == .wifi ? throughputSession.confirmedSSID : nil,
            wifiRouteGeneration: wifiRouteGeneration
        )
        let probeRouteChanged = self.probeRouteIdentity != probeRouteIdentity
        self.probeRouteIdentity = probeRouteIdentity
        reading = updated

        if throughputSessionChanged {
            beginThroughputSession()
        }
        if probeRouteChanged {
            invalidateProbeForRouteChange()
        }
    }

    private func startThroughputTimer() {
        let timer = Timer(
            timeInterval: MonitoringCadence.throughputSampleInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sampleThroughput()
            }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        throughputTimer = timer
    }

    private func beginThroughputSession() {
        let interfaceName = reading.interfaceName
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
              interfaceName == throughputSession.interfaceName,
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

    private func runProbeIfNeeded() {
        guard pathSatisfied, !probeInFlight else { return }
        guard Date().timeIntervalSince(lastProbeDate) >= MonitoringCadence.internetProbeInterval else {
            return
        }
        runProbe()
    }

    private func runProbe() {
        guard pathSatisfied else { return }
        let generation = probeGeneration
        probeInFlight = true
        lastProbeDate = Date()
        Task {
            let succeeded = await probe.check()
            guard Self.shouldApplyProbeResult(
                startedGeneration: generation,
                currentGeneration: probeGeneration
            ) else { return }
            probeResult = succeeded ? .succeeded : .failed
            probeInFlight = false
            reading.state = InternetState.resolve(pathSatisfied: pathSatisfied, probe: probeResult)
        }
    }

    private func invalidateProbeForRouteChange() {
        probeGeneration &+= 1
        probeInFlight = false
        probeResult = .pending
        lastProbeDate = .distantPast
        reading.state = InternetState.resolve(pathSatisfied: pathSatisfied, probe: probeResult)
    }

    nonisolated static func shouldApplyProbeResult(
        startedGeneration: Int,
        currentGeneration: Int
    ) -> Bool {
        startedGeneration == currentGeneration
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
