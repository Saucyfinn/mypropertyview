import Foundation
import CoreLocation
import SwiftUI

// MARK: - Location Verification Delegate

class LocationVerificationDelegate: NSObject, CLLocationManagerDelegate {
    private let completion: (Bool) -> Void
    private var hasCompleted = false
    
    init(completion: @escaping (Bool) -> Void) {
        self.completion = completion
        super.init()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !hasCompleted, let location = locations.last else { return }
        hasCompleted = true
        
        // Check if we got a reasonably accurate location
        let isAccurate = location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 100
        completion(isAccurate)
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard !hasCompleted else { return }
        hasCompleted = true
        completion(false)
    }
}

class AppState: ObservableObject {
    @Published var isAppReady = false
    @Published var loadingMessage = "Initializing..."
    @Published var currentCoordinates: ARCoordinateData?
    @Published var alignmentPoints: [CLLocationCoordinate2D] = []
    @Published var positioningStatus: PositioningStatus = .unknown
    
    // Enhanced property data
    @Published var subjectProperty: PropertyData?
    @Published var neighborProperties: [PropertyData] = []
    
    enum PositioningStatus {
        case unknown
        case gps
        case mathematical
        case manual
        case failed
        
        var displayText: String {
            switch self {
            case .unknown: return "Initializing..."
            case .gps: return "GPS Positioning"
            case .mathematical: return "Mathematical Positioning"
            case .manual: return "Manual Positioning"
            case .failed: return "Positioning Failed"
            }
        }
        
        var color: Color {
            switch self {
            case .unknown: return .gray
            case .gps: return .green
            case .mathematical: return .blue
            case .manual: return .orange
            case .failed: return .red
            }
        }
    }
    
    init() {
        // Enhanced app initialization
        Task {
            await initializeApp()
        }
    }

    @MainActor
    private func initializeApp() async {
        // Enhanced initialization sequence with proper GPS checking
        loadingMessage = "Checking location permissions..."
        positioningStatus = .unknown
        
        // Check actual location permissions and GPS availability
        let locationPermissionGranted = await checkLocationPermissions()
        try? await Task.sleep(nanoseconds: 600_000_000)

        loadingMessage = "Loading LINZ services..."
        try? await Task.sleep(nanoseconds: 800_000_000)

        loadingMessage = "Preparing AR components..."
        try? await Task.sleep(nanoseconds: 700_000_000)
        
        loadingMessage = "Initializing positioning system..."
        
        // Set positioning status based on actual GPS availability
        if locationPermissionGranted {
            let locationReady = await verifyLocationServices()
            if locationReady {
                positioningStatus = .gps
                loadingMessage = "GPS positioning ready!"
            } else {
                positioningStatus = .mathematical
                loadingMessage = "Using mathematical positioning..."
            }
        } else {
            positioningStatus = .mathematical
            loadingMessage = "Location unavailable, using fallback..."
        }
        
        try? await Task.sleep(nanoseconds: 500_000_000)

        loadingMessage = "Ready!"
        try? await Task.sleep(nanoseconds: 400_000_000)

        isAppReady = true
    }
    
    // MARK: - GPS Status Verification
    
    private func checkLocationPermissions() async -> Bool {
        let locationManager = CLLocationManager()
        
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return true
        case .notDetermined:
            // For demo purposes, return false if not determined
            // In real app, would request permission here
            return false
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
    
    private func verifyLocationServices() async -> Bool {
        guard CLLocationManager.locationServicesEnabled() else {
            return false
        }
        
        // Additional check for GPS accuracy
        return await withCheckedContinuation { continuation in
            let locationManager = CLLocationManager()
            let delegate = LocationVerificationDelegate { isReady in
                continuation.resume(returning: isReady)
            }
            locationManager.delegate = delegate
            
            // Try to get a location fix to verify GPS is actually working
            locationManager.requestLocation()
            
            // Timeout after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                continuation.resume(returning: false)
            }
        }
    }

    func bundledWebURL(with origin: CLLocation?) -> URL {
        // Enhanced URL construction for PropertyView-Enhanced
        let url: URL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Web")
            ?? Bundle.main.url(forResource: "index", withExtension: "html")
            ?? { preconditionFailure("index.html not found in PropertyView-Enhanced bundle") }()

        if let o = origin {
            var c = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            c.queryItems = [
                .init(name: "lat", value: String(o.coordinate.latitude)),
                .init(name: "lng", value: String(o.coordinate.longitude)),
                .init(name: "z", value: "17")
            ]
            return c.url!
        }
        return url
    }
    
    // Enhanced coordinate management
    func updateCoordinates(_ coordinates: ARCoordinateData) {
        DispatchQueue.main.async {
            self.currentCoordinates = coordinates
            self.subjectProperty = coordinates.subjectProperty
            self.neighborProperties = coordinates.neighborProperties
        }
    }
    
    func updateAlignmentPoints(_ points: [CLLocationCoordinate2D]) {
        DispatchQueue.main.async {
            self.alignmentPoints = points
        }
    }
    
    func updatePositioningStatus(_ status: PositioningStatus) {
        DispatchQueue.main.async {
            self.positioningStatus = status
        }
    }
    
    // Enhanced property data management
    func hasPropertyData() -> Bool {
        return subjectProperty != nil
    }
    
    func getPropertyCount() -> Int {
        return (subjectProperty != nil ? 1 : 0) + neighborProperties.count
    }
}

// Enhanced data structures with simplified baseline support
struct ARCoordinateData: Codable, Equatable {
    let origin: OriginData
    let subjectProperty: PropertyData
    let neighborProperties: [PropertyData]
    let metadata: MetadataData
}

// Simplified baseline format for 2-point AR setup
struct ARBaselineData: Codable, Equatable {
    let type: String
    let origin: OriginData
    let baseline: [BaselinePoint]
    let metadata: BaselineMetadata
}

struct BaselinePoint: Codable, Equatable {
    let latitude: Double
    let longitude: Double
}

struct BaselineMetadata: Codable, Equatable {
    let subjectAppellation: String
    let area: Double
    let neighborCount: Int
    let conversionMethod: String
    let accuracy: String
    let timestamp: String
}

struct OriginData: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    let altitude: Double
}

struct PropertyData: Codable, Identifiable, Equatable {
    let id = UUID()
    let appellation: String
    let area: Double
    let distance: Double?
    let arPoints: [ARPoint]
    let centroid: CentroidData?
    
    private enum CodingKeys: String, CodingKey {
        case appellation, area, distance, arPoints, centroid
    }
    
    static func == (lhs: PropertyData, rhs: PropertyData) -> Bool {
        return lhs.appellation == rhs.appellation &&
               lhs.area == rhs.area &&
               lhs.distance == rhs.distance &&
               lhs.arPoints == rhs.arPoints
    }
}

struct ARPoint: Codable, Equatable {
    let x: Double
    let y: Double
    let z: Double
    let latitude: Double
    let longitude: Double
    let distance: Double?
}

struct CentroidData: Codable, Equatable {
    let latitude: Double
    let longitude: Double
}

struct MetadataData: Codable, Equatable {
    let totalProperties: Int
    let conversionMethod: String
    let accuracy: String
    let timestamp: String
}