import AppKit
import SwiftUI

@main
struct NetBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let monitor = NetworkMonitor()
    private let launchAtLogin = LaunchAtLoginController()
    private let locationPermission = LocationPermissionController()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configurePopover()
        configureStatusItem()
        observeMonitor()
        locationPermission.requestAutomaticallyIfNeeded()
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 360, height: 620)
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
        guard let image = NSImage(
            systemSymbolName: transport.statusSymbolName,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(pointSize: 14, weight: .medium)) else {
            return nil
        }
        image.isTemplate = true
        return image
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
    }

    func popoverWillShow(_ notification: Notification) {
        monitor.startInteractiveMonitoring()
    }

    func popoverDidClose(_ notification: Notification) {
        monitor.stopInteractiveMonitoring()
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
