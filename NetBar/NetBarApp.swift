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
        if ProcessInfo.processInfo.environment["NETBAR_OPEN_POPOVER_FOR_UI_TESTS"] == "1" {
            DispatchQueue.main.async { [weak self] in
                self?.showPopover()
            }
        }
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
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.imagePosition = .imageOnly
        button.toolTip = "NetBar"
        button.identifier = NSUserInterfaceItemIdentifier("NetBarStatusItem")
        button.setAccessibilityLabel("NetBar network status")
        item.autosaveName = "NetBar.StatusItem"
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
        button.title = ""
        button.image = statusImage(for: reading)
        let description = "\(reading.friendlyTitle): \(reading.state.accessibilityDescription)"
        button.toolTip = description
        button.setAccessibilityLabel(description)
    }

    private func statusImage(for reading: NetworkReading) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let circleRect = NSRect(x: 1, y: 1, width: 16, height: 16)
            let circle = NSBezierPath(ovalIn: circleRect)
            reading.state.menuBarColor.setFill()
            circle.fill()
            NSColor.black.withAlphaComponent(0.18).setStroke()
            circle.lineWidth = 0.75
            circle.stroke()

            guard reading.transport != .none,
                  let symbol = NSImage(
                    systemSymbolName: reading.transport.statusSymbolName,
                    accessibilityDescription: nil
                  )?
                    .withSymbolConfiguration(.init(pointSize: 9.25, weight: .bold))?
                    .withSymbolConfiguration(.init(paletteColors: [reading.state.menuBarGlyphColor]))
            else { return true }

            let symbolSize = symbol.size
            let scale = min(10.5 / symbolSize.width, 9.5 / symbolSize.height)
            let drawSize = NSSize(width: symbolSize.width * scale, height: symbolSize.height * scale)
            let drawRect = NSRect(
                x: rect.midX - drawSize.width / 2,
                y: rect.midY - drawSize.height / 2 - 0.25,
                width: drawSize.width,
                height: drawSize.height
            )
            symbol.draw(in: drawRect)
            return true
        }
        image.isTemplate = false
        return image
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
        case .ethernet: "cable.connector.horizontal"
        case .other: "network"
        case .none: "circle.fill"
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

    var menuBarGlyphColor: NSColor {
        switch self {
        case .online, .checking, .degraded:
            NSColor(calibratedWhite: 0.06, alpha: 1)
        case .offline:
            .white
        }
    }
}
