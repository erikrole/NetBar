import AppKit
import SwiftUI

struct NetBarView: View {
    let monitor: NetworkMonitor
    let launchAtLogin: LaunchAtLoginController
    let locationPermission: LocationPermissionController
    @State private var globalProtectLaunchError: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 12) {
                    throughput
                    connection
                    vpn
                    wifi
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            Divider()
            footer
        }
        .frame(width: 360, height: 620)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(spacing: 11) {
            HStack(spacing: 11) {
                StatusBadge(state: monitor.reading.state, transport: monitor.reading.transport)

                VStack(alignment: .leading, spacing: 2) {
                    Text(monitor.reading.friendlyTitle)
                        .font(.headline)
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
            .help("Check internet now")
            .accessibilityLabel("Check internet now")
        }
        .padding(16)
    }

    private var throughput: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Live throughput")
            ThroughputCard(
                downloadValue: monitor.reading.downloadBytesPerSecond,
                uploadValue: monitor.reading.uploadBytesPerSecond,
                downloadHistory: monitor.reading.downloadHistory,
                uploadHistory: monitor.reading.uploadHistory
            )
        }
    }

    private var connection: some View {
        InfoSection(title: "Connection", symbol: monitor.reading.transport.symbolName) {
            InfoRow(label: "Router", value: monitor.reading.routerAddress ?? "Unavailable")
            InfoRow(label: "Local address", value: monitor.reading.localAddress ?? "Unavailable")
            if let ethernet = monitor.reading.inactiveEthernetConnection {
                EthernetNotActiveNotice(connection: ethernet)
            }
        }
    }

    private var vpn: some View {
        InfoSection(title: "GlobalProtect", symbol: "lock.shield") {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("VPN")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 12)
                Text(monitor.reading.globalProtectConnected ? "Connected" : "Disconnected")
                    .foregroundStyle(monitor.reading.globalProtectConnected ? .green : .secondary)
                Button("Open GlobalProtect…") {
                    openGlobalProtect()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Open GlobalProtect with your saved portal ready")
                .accessibilityIdentifier("GlobalProtectConnectionButton")
            }
            .font(.callout)

            if let globalProtectLaunchError {
                Label(globalProtectLaunchError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("GlobalProtectLaunchError")
            }
        }
    }

    @ViewBuilder
    private var wifi: some View {
        InfoSection(title: "Wi-Fi", symbol: "wifi") {
            if !monitor.reading.wifi.isPowered {
                InfoRow(label: "Radio", value: "Off")
            } else if !monitor.reading.wifi.isAssociated {
                InfoRow(label: "Network", value: "Not connected", valueColor: .secondary)
            } else {
                InfoRow(label: "Network", value: monitor.reading.wifi.ssid ?? "Unavailable")
                if monitor.reading.transport != .wifi {
                    InfoRow(label: "Usage", value: "Connected, not active", valueColor: .secondary)
                }
                if let rssi = monitor.reading.wifi.rssi {
                    InfoRow(label: "Signal", value: "\(rssi) dBm · \(monitor.reading.wifi.quality ?? "Unknown")")
                }
                if let noise = monitor.reading.wifi.noise, let snr = monitor.reading.wifi.snr {
                    InfoRow(label: "Noise / SNR", value: "\(noise) dBm / \(snr) dB")
                }
                if let transmitRate = monitor.reading.wifi.transmitRate {
                    InfoRow(label: "Transmit rate", value: String(format: "%.0f Mbps", transmitRate))
                }
                if let channel = monitor.reading.wifi.channelDescription {
                    InfoRow(label: "Channel", value: channel)
                }

            }
        }
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
                    Button("Open Network Settings") {
                        openNetworkSettings()
                    }
                    if locationPermission.isDenied {
                        Button("Open Location Services") {
                            locationPermission.openSettings()
                        }
                    }
                    if launchAtLogin.requiresApproval {
                        Button("Open Login Item Settings") {
                            launchAtLogin.openSettings()
                        }
                    }
                    Divider()
                    Button("Quit NetBar") {
                        NSApplication.shared.terminate(nil)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("More options")
                .accessibilityLabel("More options")
            }

            if let errorMessage = launchAtLogin.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("LaunchAtLoginError")
            } else if launchAtLogin.requiresApproval {
                HStack(spacing: 4) {
                    Text("Login item approval required.")
                    Button("Open Settings") {
                        launchAtLogin.openSettings()
                    }
                    .buttonStyle(.link)
                }
            }

        }
        .font(.caption)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .tracking(0.45)
    }

    private func openNetworkSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    private func openGlobalProtect() {
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.paloaltonetworks.GlobalProtect.client"
        ) else {
            globalProtectLaunchError = "GlobalProtect is not installed."
            return
        }

        globalProtectLaunchError = nil
        Task { @MainActor in
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            do {
                _ = try await NSWorkspace.shared.openApplication(
                    at: url,
                    configuration: configuration
                )
            } catch {
                globalProtectLaunchError = error.localizedDescription
            }
        }
    }
}

private struct StatusBadge: View {
    let state: InternetState
    let transport: TransportKind

    var body: some View {
        ZStack {
            Circle()
                .fill(state.swiftUIColor)
                .shadow(color: state.swiftUIColor.opacity(0.28), radius: 4)
                .overlay {
                    Circle()
                        .stroke(.black.opacity(0.18), lineWidth: 0.75)
                }
            if transport != .none {
                Image(systemName: transport.statusSymbolName)
                    .font(.system(size: 9.25, weight: .bold))
                    .foregroundStyle(state.statusGlyphColor)
                    .offset(y: 0.25)
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}

private extension InternetState {
    var statusGlyphColor: Color {
        switch self {
        case .online, .checking, .degraded:
            Color(white: 0.06)
        case .offline:
            .white
        }
    }
}

private struct EthernetNotActiveNotice: View {
    let connection: EthernetConnection

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "cable.connector.horizontal")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 22, height: 22)
                .background(.orange.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text("Ethernet connected, not in use")
                    .font(.caption.weight(.semibold))
                Text(connection.linkSpeedBitsPerSecond.map {
                    "\(LinkSpeedFormatter.string($0)) link detected"
                } ?? "Wired link detected")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
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
            HStack {
                Text("Last 60 seconds")
                Spacer()
                Text("1 second samples")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(.quaternary.opacity(0.64), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                .font(.system(.body, design: .rounded, weight: .semibold))
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
        values = Array(history.suffix(ThroughputGraphMetrics.sampleCapacity))
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
                    .fill(LinearGradient(
                        colors: [color.opacity(0.22), color.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))

                    Path { path in
                        path.move(to: first)
                        for point in points.dropFirst() { path.addLine(to: point) }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round))

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
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 6) { content }
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

private extension TransportKind {
    var statusSymbolName: String {
        switch self {
        case .wifi: "wifi"
        case .ethernet: "cable.connector.horizontal"
        case .other: "network"
        case .none: "circle.fill"
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
