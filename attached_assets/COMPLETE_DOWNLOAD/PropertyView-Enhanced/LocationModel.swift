import Foundation
import CoreLocation

final class LocationModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    // Singleton instance
    static let shared = LocationModel()
    
    @Published var last: CLLocation?
    @Published var status: CLAuthorizationStatus = .notDetermined
    @Published var accuracy: CLAccuracyAuthorization = .reducedAccuracy
    @Published var isLocationEnabled = false
    @Published var locationError: String?
    
    private let mgr = CLLocationManager()
    private var locationUpdateTimer: Timer?
    
    // Private init for singleton pattern
    private override init() {
        super.init()
        setupLocationManager()
    }
    
    private func setupLocationManager() {
        mgr.delegate = self
        mgr.desiredAccuracy = kCLLocationAccuracyBest
        mgr.distanceFilter = 5.0 // Update every 5 meters
        
        // Enhanced initial authorization request
        switch mgr.authorizationStatus {
        case .notDetermined:
            mgr.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            startLocationUpdates()
        case .restricted, .denied:
            locationError = "Location access denied. Please enable in Settings."
        @unknown default:
            break
        }
    }
    
    deinit {
        stopLocationUpdates()
    }
    
    // Enhanced location management
    func requestLocation() {
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            mgr.requestWhenInUseAuthorization()
            return
        }
        
        mgr.requestLocation()
    }
    
    func startLocationUpdates() {
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
        
        mgr.startUpdatingLocation()
        isLocationEnabled = true
        locationError = nil
        
        // Enhanced: Request high accuracy location
        if accuracy == .reducedAccuracy {
            // Temporarily request full accuracy for property boundary precision
            mgr.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "PropertyBoundaryAccuracy")
        }
    }
    
    func stopLocationUpdates() {
        mgr.stopUpdatingLocation()
        isLocationEnabled = false
        locationUpdateTimer?.invalidate()
        locationUpdateTimer = nil
    }
    
    // Enhanced authorization handling
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.status = manager.authorizationStatus
            self.accuracy = manager.accuracyAuthorization
        }
        
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            // Enhanced accuracy request for property boundaries
            if manager.accuracyAuthorization == .reducedAccuracy {
                manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "PropertyBoundaryAccuracy")
            }
            startLocationUpdates()
            
        case .restricted, .denied:
            stopLocationUpdates()
            DispatchQueue.main.async {
                self.locationError = "Location access is required for property boundary detection. Please enable in Settings."
            }
            
        case .notDetermined:
            DispatchQueue.main.async {
                self.locationError = nil
            }
            
        @unknown default:
            break
        }
    }
    
    // Enhanced location updates
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // Enhanced location validation
        let age = abs(location.timestamp.timeIntervalSinceNow)
        guard age < 30.0 else { return } // Ignore locations older than 30 seconds
        
        guard location.horizontalAccuracy > 0 && location.horizontalAccuracy < 100 else {
            return // Ignore inaccurate locations
        }
        
        DispatchQueue.main.async {
            self.last = location
            self.locationError = nil
        }
    }
    
    // Enhanced error handling
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Enhanced LocationModel error:", error.localizedDescription)
        
        DispatchQueue.main.async {
            if let clError = error as? CLError {
                switch clError.code {
                case .denied:
                    self.locationError = "Location access denied"
                case .locationUnknown:
                    self.locationError = "Unable to determine location"
                case .network:
                    self.locationError = "Network error while getting location"
                default:
                    self.locationError = "Location error: \(error.localizedDescription)"
                }
            } else {
                self.locationError = "Location error: \(error.localizedDescription)"
            }
        }
    }
    
    // Enhanced location accuracy for property boundaries
    func requestHighAccuracyLocation() {
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            requestLocation()
            return
        }
        
        // Temporarily increase accuracy for property detection
        mgr.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        mgr.requestLocation()
        
        // Reset to normal accuracy after 30 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            self.mgr.desiredAccuracy = kCLLocationAccuracyBest
        }
    }
    
    // Enhanced utility methods
    func distanceFromLastLocation(to coordinate: CLLocationCoordinate2D) -> Double? {
        guard let lastLocation = last else { return nil }
        let targetLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return lastLocation.distance(from: targetLocation)
    }
    
    func isLocationRecent(within seconds: TimeInterval = 60) -> Bool {
        guard let lastLocation = last else { return false }
        return abs(lastLocation.timestamp.timeIntervalSinceNow) < seconds
    }
    
    func getLocationAccuracyDescription() -> String {
        guard let location = last else { return "No location" }
        
        let accuracy = location.horizontalAccuracy
        if accuracy < 0 {
            return "Invalid location"
        } else if accuracy < 5 {
            return "Excellent accuracy (±\(Int(accuracy))m)"
        } else if accuracy < 20 {
            return "Good accuracy (±\(Int(accuracy))m)"
        } else if accuracy < 100 {
            return "Fair accuracy (±\(Int(accuracy))m)"
        } else {
            return "Poor accuracy (±\(Int(accuracy))m)"
        }
    }
}