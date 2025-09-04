import Foundation
import CoreLocation

final class LocationModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var last: CLLocation?
    @Published var status: CLAuthorizationStatus = .notDetermined
    @Published var accuracy: CLAccuracyAuthorization = .reducedAccuracy

    private let mgr = CLLocationManager()

    override init() {
        super.init()
        mgr.delegate = self
        mgr.desiredAccuracy = kCLLocationAccuracyBest

        // ✅ Use instance property (no deprecation)
        switch mgr.authorizationStatus {
        case .notDetermined:
            mgr.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            mgr.startUpdatingLocation()
        case .restricted, .denied:
            break
        @unknown default:
            break
        }
    }

    // iOS 14+: this is the right callback to observe changes
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        status = manager.authorizationStatus
        accuracy = manager.accuracyAuthorization

        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            // Optional: ask for precise location if currently reduced
            if manager.accuracyAuthorization == .reducedAccuracy {
                // If you add a purpose key to Info.plist (see below), you can request precise temporarily
                // manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "LocationUsage")
            }
            mgr.startUpdatingLocation()

        case .restricted, .denied:
            mgr.stopUpdatingLocation()

        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let loc = locations.last { last = loc }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("CL error:", error.localizedDescription)
    }
}
