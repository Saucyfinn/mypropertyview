import Foundation
import CoreLocation

/// Minimal bootstrap: handles location permission and updates,
/// reports status text, and returns the latest CLLocation.
/// Rings are no longer fetched here; ARTab calls LDSService directly.
final class ARBootstrap: NSObject, CLLocationManagerDelegate {
    private let mgr = CLLocationManager()
    private let onStatus: (String) -> Void
    private let onResult: ([[CLLocationCoordinate2D]], CLLocation?) -> Void

    init(onStatus: @escaping (String) -> Void,
         onResult: @escaping ([[CLLocationCoordinate2D]], CLLocation?) -> Void) {
        self.onStatus = onStatus
        self.onResult = onResult
        super.init()
        mgr.delegate = self
        mgr.desiredAccuracy = kCLLocationAccuracyBest
        mgr.distanceFilter = 1.0
    }

    func start() {
        switch mgr.authorizationStatus {
        case .notDetermined:
            onStatus("Requesting location permission…")
            mgr.requestWhenInUseAuthorization()
        case .denied, .restricted:
            onStatus("Location permission denied")
        default:
            onStatus("Starting location…")
            mgr.startUpdatingLocation()
        }
    }

    func stop() {
        mgr.stopUpdatingLocation()
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            onStatus("Location authorized")
            manager.startUpdatingLocation()
        case .denied, .restricted:
            onStatus("Location permission denied")
            onResult([], nil)
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        onStatus(String(format: "Lat %.5f, Lon %.5f", loc.coordinate.latitude, loc.coordinate.longitude))
        onResult([], loc)   // rings are empty here; ARTab fetches from LDSService
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        onStatus("Location error: \(error.localizedDescription)")
        onResult([], nil)
    }
}
