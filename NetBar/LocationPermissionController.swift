import AppKit
import CoreLocation
import Foundation
import Observation

@MainActor
@Observable
final class LocationPermissionController: NSObject, @preconcurrency CLLocationManagerDelegate {
    private(set) var authorizationStatus: CLAuthorizationStatus
    private let manager = CLLocationManager()

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    var canRequest: Bool {
        authorizationStatus == .notDetermined
    }

    var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    func request() {
        manager.requestWhenInUseAuthorization()
    }

    func requestAutomaticallyIfNeeded() {
        guard canRequest,
              ProcessInfo.processInfo.environment["NETBAR_SKIP_LOCATION_PERMISSION_REQUEST"] != "1"
        else { return }
        request()
    }

    func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") else { return }
        NSWorkspace.shared.open(url)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }
}
