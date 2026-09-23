import Foundation
import CoreLocation
import NanoleafCore

/// Only the background service requests location. Coordinates stay in memory.
final class SystemLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var refreshTimer: Timer?
    private var fix: CLLocation?
    private var requestedAt = Date.distantPast
    private var enabled = false
    private var failure: String?
    var location: SolarLocation? {
        guard enabled, authorized, let fix,
              abs(fix.timestamp.timeIntervalSinceNow) < 7200 else { return nil }
        return SolarLocation(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude)
    }
    private var authorized: Bool {
        manager.authorizationStatus == .authorizedAlways
    }
    var status: String {
        guard enabled else { return "Location: inactive." }
        switch manager.authorizationStatus {
        case .denied, .restricted:
            return "Location unavailable. Allow Nanoleaf in System Settings > Privacy & Security > Location Services."
        case .notDetermined:
            return "Location: waiting for macOS permission."
        default:
            if location != nil { return "Location: available from macOS; refreshed hourly, retained only in memory." }
            return failure ?? "Location: waiting for a fresh macOS fix; sunset automation paused."
        }
    }
    func start() {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }
        refreshTimer?.tolerance = 10
    }
    func refresh() {
        let shouldEnable = (try? ConfigStore().load().sunsetAutomation) == true
        if !shouldEnable {
            enabled = false; fix = nil; manager.stopUpdatingLocation()
            requestedAt = .distantPast
            return
        }
        enabled = true
        if manager.authorizationStatus == .notDetermined {
            // requestWhenInUseAuthorization is the macOS consent prompt.
            if requestedAt == .distantPast {
                requestedAt = Date()
                manager.requestWhenInUseAuthorization()
            }
            return
        }
        guard authorized else { fix = nil; return }
        guard Date().timeIntervalSince(requestedAt) >= 3600 else { return }
        requestedAt = Date()
        manager.requestLocation()
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        requestedAt = .distantPast
        refresh()
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard enabled, let newest = locations.last, newest.horizontalAccuracy >= 0,
              newest.horizontalAccuracy <= 50_000,
              abs(newest.timestamp.timeIntervalSinceNow) < 7200,
              CLLocationCoordinate2DIsValid(newest.coordinate) else { return }
        fix = newest; failure = nil
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        failure = "Location unavailable; sunset automation paused until a fresh fix is available."
        // Retry transient failures in a minute, without frequent location requests.
        requestedAt = Date().addingTimeInterval(-3540)
    }
}
