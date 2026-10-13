import AppKit
import SwiftUI

@main
struct NetBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(
                launchAtLogin: appDelegate.launchAtLogin,
                locationPermission: appDelegate.locationPermission
            )
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let monitor = NetworkMonitor()
    let launchAtLogin = LaunchAtLoginController()
    let locationPermission = LocationPermissionController()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var outsideClickMonitor: Any?
    private var statusSymbols: [TransportKind: NSImage] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        configurePopover()
        configureStatusItem()
        observeMonitor()
        locationPermission.authorizationDidChange = { [weak self] status in
            guard let self else { return }
            self.monitor.refreshNetworkDetails()
            if status == .authorizedAlways {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.monitor.refreshNetworkDetails()
                }
            }
        }
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 360, height: 656)
        popover.contentViewController = NSHostingController(
            rootView: NetBarView(
                monitor: monitor,
                launchAtLogin: launchAtLogin,
                locationPermission: locationPermission
            )
        )
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.imagePosition = .imageLeading
        button.imageScaling = .scaleNone
        button.imageHugsTitle = true
        button.toolTip = "NetBar"
        button.identifier = NSUserInterfaceItemIdentifier("NetBarStatusItem")
        button.setAccessibilityLabel("NetBar network status")
        item.autosaveName = "NetBar.StatusItem"
        item.isVisible = true
        statusItem = item
        updateStatusItem()
    }

    private func installOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.popover.isShown else { return }
                self.popover.performClose(nil)
            }
        }
    }

    private func removeOutsideClickMonitor() {
        guard let outsideClickMonitor else { return }
        NSEvent.removeMonitor(outsideClickMonitor)
        self.outsideClickMonitor = nil
    }

    private func observeMonitor() {
        withObservationTracking {
            _ = monitor.reading.state
            _ = monitor.reading.transport
            _ = monitor.reading.friendlyTitle
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.updateStatusItem()
                self.observeMonitor()
            }
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let reading = monitor.reading
        button.image = statusSymbol(for: reading.transport)
        button.attributedTitle = statusDotTitle(for: reading.state)
        let description = "\(reading.friendlyTitle): \(reading.state.accessibilityDescription)"
        button.toolTip = description
        button.setAccessibilityTitle(description)
        button.setAccessibilityLabel(description)
    }

    private func statusSymbol(for transport: TransportKind) -> NSImage? {
        if let cached = statusSymbols[transport], let copy = cached.copy() as? NSImage {
            copy.isTemplate = true
            return copy
        }
        guard let image = NSImage(
            systemSymbolName: transport.statusSymbolName,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(pointSize: 14, weight: .medium)) else {
            return nil
        }
        image.isTemplate = true
        statusSymbols[transport] = image
        guard let copy = image.copy() as? NSImage else { return image }
        copy.isTemplate = true
        return copy
    }

    private func statusDotTitle(for state: InternetState) -> NSAttributedString {
        NSAttributedString(
            string: "●",
            attributes: [
                .font: NSFont.systemFont(ofSize: 7, weight: .semibold),
                .foregroundColor: state.menuBarColor,
                .baselineOffset: 1.5,
            ]
        )
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem?.button, !popover.isShown else { return }
        launchAtLogin.refresh()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.becomeKey()
        locationPermission.requestAutomaticallyIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        removeOutsideClickMonitor()
    }

    func popoverWillShow(_ notification: Notification) {
        installOutsideClickMonitor()
        monitor.startInteractiveMonitoring()
    }

    func popoverDidClose(_ notification: Notification) {
        removeOutsideClickMonitor()
        monitor.stopInteractiveMonitoring()
    }
}

private struct SettingsView: View {
    let launchAtLogin: LaunchAtLoginController
    let locationPermission: LocationPermissionController

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: Binding(
                get: { launchAtLogin.isEnabled },
                set: { launchAtLogin.setEnabled($0) }
            ))

            if let errorMessage = launchAtLogin.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if launchAtLogin.requiresApproval {
                Button("Open Login Item Settings…") {
                    launchAtLogin.openSettings()
                }
            }

            LabeledContent("Wi-Fi name") {
                Text(locationPermission.wifiNameAccessDescription)
            }
            Text("Used only to read the name of the connected network.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if locationPermission.isDenied {
                Button("Open Location Services…") {
                    locationPermission.openSettings()
                }
            }

            Button("Open Network Settings…") {
                openNetworkSettings()
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 300)
    }

    private func openNetworkSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}

private extension TransportKind {
    var statusSymbolName: String {
        switch self {
        case .wifi: "wifi"
        case .ethernet: "cable.connector"
        case .other: "network"
        case .none: "network.slash"
        }
    }
}

private extension InternetState {
    var menuBarColor: NSColor {
        switch self {
        case .online: .systemGreen
        case .checking, .degraded: .systemYellow
        case .offline: .systemRed
        }
    }
}
