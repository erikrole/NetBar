import AppKit
import SwiftUI

struct NetBarView: View {
    let monitor: NetworkMonitor
    let launchAtLogin: LaunchAtLoginController
    let locationPermission: LocationPermissionController
    @State private var globalProtectLaunchError: String?

    var body: some View {
        VStack(spacing: 0) {
            StatusHeader(monitor: monitor)
            Divider()
            ScrollView {
                VStack(spacing: 12) {
                    ThroughputSection(monitor: monitor)
                    ConnectionSection(monitor: monitor)
                    VPNSection(monitor: monitor, launchError: $globalProtectLaunchError)
                    WiFiSection(monitor: monitor, locationPermission: locationPermission)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
            Divider()
            footer
        }
        .frame(width: 360, height: 656)
        .background(.regularMaterial)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 12) {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityIdentifier("LaunchAtLoginToggle")

                Spacer()

                Menu {
                    Button("Settings…") {
                        showAppSettings()
                    }
                    Button("Open Network Settings…") {
                        openNetworkSettings()
                    }
                    if locationPermission.isDenied {
                        Button("Open Location Services…") {
                            locationPermission.openSettings()
                        }
                    }
                    if launchAtLogin.requiresApproval {
                        Button("Open Login Item Settings…") {
                            launchAtLogin.openSettings()
                        }
                    }
                    Divider()
                    Button("Quit NetBar") {
                        NSApplication.shared.terminate(nil)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 16, height: 16)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .help("More options")
                .accessibilityLabel("More options")
            }

            if let errorMessage = launchAtLogin.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("LaunchAtLoginError")
            } else if launchAtLogin.requiresApproval {
                HStack(spacing: 4) {
                    Text("Login item approval required.")
                    Button("Open Login Item Settings…") {
                        launchAtLogin.openSettings()
                    }
                    .buttonStyle(.link)
                }
                .font(.caption)
            }

        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func showAppSettings() {
        NSApp.activate()
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    private func openNetworkSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct StatusHeader: View {
    let monitor: NetworkMonitor

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                StatusDot(state: monitor.reading.state)

                VStack(alignment: .leading, spacing: 2) {
                    Text(monitor.reading.friendlyTitle)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(monitor.reading.statusSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(monitor.reading.accessibilitySummary)

            Spacer()

            Button {
                monitor.checkNow()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .frame(width: 24, height: 24)
            .help("Check internet now")
            .accessibilityLabel("Check internet now")
        }
        .padding(16)
    }
}

private struct ThroughputSection: View {
    let monitor: NetworkMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Live throughput")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ThroughputCard(
                downloadValue: monitor.throughput.downloadBytesPerSecond,
                uploadValue: monitor.throughput.uploadBytesPerSecond,
                downloadHistory: monitor.throughput.downloadHistory,
                uploadHistory: monitor.throughput.uploadHistory
            )
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}

private struct ConnectionSection: View {
    let monitor: NetworkMonitor

    var body: some View {
        InfoSection(title: "Connection") {
            InfoRow(label: "Router", value: monitor.reading.routerAddress ?? "Unavailable")
            InfoRow(label: "Local address", value: monitor.reading.localAddress ?? "Unavailable")
            if let ethernet = monitor.reading.inactiveEthernetConnection {
                EthernetNotActiveNotice(connection: ethernet)
            }
        }
    }
}

private struct VPNSection: View {
    let monitor: NetworkMonitor
    @Binding var launchError: String?

    var body: some View {
        InfoSection(title: "GlobalProtect") {
            InfoRow(
                label: "VPN",
                value: monitor.reading.globalProtectConnected ? "Connected" : "Disconnected",
                valueColor: monitor.reading.globalProtectConnected ? .green : .secondary
            )
            Button("Open GlobalProtect…") {
                openGlobalProtect()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Open GlobalProtect with your saved portal ready")
            .accessibilityIdentifier("GlobalProtectConnectionButton")

            if let launchError {
                Label(launchError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("GlobalProtectLaunchError")
            }
        }
    }

    private func openGlobalProtect() {
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.paloaltonetworks.GlobalProtect.client"
        ) else {
            launchError = "GlobalProtect is not installed."
            return
        }

        launchError = nil
        Task { @MainActor in
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            do {
                _ = try await NSWorkspace.shared.openApplication(
                    at: url,
                    configuration: configuration
                )
            } catch {
                launchError = error.localizedDescription
            }
        }
    }
}

private struct WiFiSection: View {
    let monitor: NetworkMonitor
    let locationPermission: LocationPermissionController

    var body: some View {
        let wifi = monitor.reading.wifi
        InfoSection(title: "Wi-Fi") {
            if !wifi.isPowered {
                InfoRow(label: "Radio", value: "Off")
            } else if !wifi.isAssociated {
                InfoRow(label: "Network", value: "Not connected", valueColor: .secondary)
            } else {
                WiFiAssociatedDetails(
                    wifi: wifi,
                    transport: monitor.reading.transport,
                    locationPermission: locationPermission
                )
            }
        }
    }
}

private struct WiFiAssociatedDetails: View {
    let wifi: WiFiReading
    let transport: TransportKind
    let locationPermission: LocationPermissionController

    var body: some View {
        if transport != .wifi || wifi.ssid == nil {
            InfoRow(
                label: "Network",
                value: wifi.networkName(permissionDenied: locationPermission.isDenied),
                valueColor: wifi.ssid == nil ? .secondary : .primary
            )
        }
        if transport != .wifi {
            InfoRow(label: "Usage", value: "Connected, not active", valueColor: .secondary)
        }
        if locationPermission.isDenied, wifi.ssid == nil {
            Button("Open Location Services…") {
                locationPermission.openSettings()
            }
            .buttonStyle(.link)
            .font(.caption)
        }
        if let rssi = wifi.rssi {
            InfoRow(label: "Signal", value: "\(rssi) dBm · \(wifi.quality ?? "Unknown")")
        }
        if let noise = wifi.noise, let snr = wifi.snr {
            InfoRow(label: "Noise / SNR", value: "\(noise) dBm / \(snr) dB")
        }
        if let transmitRate = wifi.transmitRate {
            InfoRow(label: "Transmit rate", value: String(format: "%.0f Mbps", transmitRate))
        }
        if let channel = wifi.channelDescription {
            InfoRow(label: "Channel", value: channel)
        }
    }
}

private struct StatusDot: View {
    let state: InternetState

    var body: some View {
        Circle()
            .fill(state.swiftUIColor)
            .overlay {
                Circle()
                    .strokeBorder(.primary.opacity(0.16), lineWidth: 0.5)
            }
            .frame(width: 9, height: 9)
            .padding(.top, 4)
            .accessibilityHidden(true)
    }
}

private struct EthernetNotActiveNotice: View {
    let connection: EthernetConnection

    private var detail: String {
        if let speed = connection.linkSpeedBitsPerSecond {
            return "Linked, not in use · \(LinkSpeedFormatter.string(speed))"
        }
        return "Linked, not in use"
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Ethernet")
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(detail)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.trailing)
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ethernet, \(detail)")
    }
}

private struct ThroughputCard: View {
    let downloadValue: Double
    let uploadValue: Double
    let downloadHistory: [Double]
    let uploadHistory: [Double]

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 12) {
                TrafficSummary(
                    title: "Download",
                    symbol: "arrow.down",
                    value: downloadValue,
                    color: .blue
                )
                TrafficSummary(
                    title: "Upload",
                    symbol: "arrow.up",
                    value: uploadValue,
                    color: .purple
                )
            }
            CompactTrafficLane(
                title: "Download history",
                symbol: "arrow.down",
                history: downloadHistory,
                color: .blue
            )
            CompactTrafficLane(
                title: "Upload history",
                symbol: "arrow.up",
                history: uploadHistory,
                color: .purple
            )
            Text("Last 60 seconds")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .animation(nil, value: downloadHistory)
        .animation(nil, value: uploadHistory)
    }
}

private struct TrafficSummary: View {
    let title: String
    let symbol: String
    let value: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: symbol)
                .font(.caption2.weight(.medium))
                .foregroundStyle(color)
            Text(ByteRateFormatter.string(value))
                .font(.body.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(ByteRateFormatter.string(value))")
    }
}

private struct CompactTrafficLane: View {
    let title: String
    let symbol: String
    let values: [Double]
    let color: Color

    init(title: String, symbol: String, history: [Double], color: Color) {
        self.title = title
        self.symbol = symbol
        values = history
        self.color = color
    }

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                Text("Peak \(ByteRateFormatter.string(values.max() ?? 0))")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            TrafficGraph(values: values, color: color)
                .frame(height: 26)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), peak \(ByteRateFormatter.string(values.max() ?? 0))")
    }
}

private struct TrafficGraph: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let maximum = ThroughputGraphMetrics.scaleMaximum(for: values)
            let points = values.enumerated().map { index, value in
                CGPoint(
                    x: geometry.size.width * ThroughputGraphMetrics.normalizedX(
                        index: index,
                        sampleCount: values.count
                    ),
                    y: geometry.size.height * (1 - min(max(value / maximum, 0), 1))
                )
            }

            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: geometry.size.height - 0.5))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height - 0.5))
                }
                .stroke(.secondary.opacity(0.16), lineWidth: 1)

                if let first = points.first, let last = points.last {
                    Path { path in
                        path.move(to: CGPoint(x: first.x, y: geometry.size.height))
                        path.addLine(to: first)
                        for point in points.dropFirst() { path.addLine(to: point) }
                        path.addLine(to: CGPoint(x: last.x, y: geometry.size.height))
                        path.closeSubpath()
                    }
                    .fill(color.opacity(0.14))

                    Path { path in
                        path.move(to: first)
                        for point in points.dropFirst() { path.addLine(to: point) }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round))

                    Circle()
                        .fill(color)
                        .frame(width: 4, height: 4)
                        .position(last)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct InfoSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) { content }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InfoRow: View {
    let label: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value)
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.callout)
    }
}

private extension InternetState {
    var swiftUIColor: Color {
        switch self {
        case .online: .green
        case .checking, .degraded: .yellow
        case .offline: .red
        }
    }
}

#Preview {
    NetBarView(
        monitor: NetworkMonitor(),
        launchAtLogin: LaunchAtLoginController(),
        locationPermission: LocationPermissionController()
    )
}
