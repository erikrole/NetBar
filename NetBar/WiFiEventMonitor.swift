import CoreWLAN
import Foundation

final class WiFiEventMonitor: NSObject, @unchecked Sendable, CWEventDelegate {
    private let client = CWWiFiClient.shared()
    private let onChange: @Sendable () -> Void

    init(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        super.init()
        client.delegate = self
        for event in [CWEventType.ssidDidChange, .linkDidChange, .powerDidChange] {
            try? client.startMonitoringEvent(with: event)
        }
    }

    func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        onChange()
    }

    func linkDidChangeForWiFiInterface(withName interfaceName: String) {
        onChange()
    }

    func powerStateDidChangeForWiFiInterface(withName interfaceName: String) {
        onChange()
    }
}
