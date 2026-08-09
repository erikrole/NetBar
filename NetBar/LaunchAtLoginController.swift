import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class LaunchAtLoginController {
    private(set) var status: SMAppService.Status
    private(set) var errorMessage: String?

    private let service = SMAppService.mainApp

    init() {
        status = service.status
    }

    var isEnabled: Bool { status == .enabled }
    var requiresApproval: Bool { status == .requiresApproval }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try service.register()
            } else if status != .notRegistered {
                try service.unregister()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        status = service.status
    }

    func refresh() {
        status = service.status
    }

    func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
