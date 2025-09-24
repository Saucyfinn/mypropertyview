import Foundation
import CoreLocation

class AppState: ObservableObject {
    @Published var isAppReady = false
    @Published var loadingMessage = "Initializing..."
    @Published var currentCoordinates: [CLLocationCoordinate2D]?
    @Published var positioningStatus: PositioningStatus = .initializing
    
    init() {
        // Start app initialization
        Task {
            await initializeApp()
        }
    }
    
    @MainActor
    private func initializeApp() async {
        // Simulate initialization steps with realistic timing
        loadingMessage = "Checking location permissions..."
        try? await Task.sleep(nanoseconds: 600_000_000) // 0.6 seconds
        
        loadingMessage = "Loading LINZ services..."
        try? await Task.sleep(nanoseconds: 800_000_000) // 0.8 seconds
        
        loadingMessage = "Preparing AR components..."
        try? await Task.sleep(nanoseconds: 700_000_000) // 0.7 seconds
        
        loadingMessage = "Ready!"
        try? await Task.sleep(nanoseconds: 400_000_000) // 0.4 seconds
        
        // App is ready - hide loading screen
        isAppReady = true
    }
    
    func bundledWebURL(with origin: CLLocation?) -> URL {
        // Try Web/index.html (blue folder), then root/index.html (yellow group)
        let url: URL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Web")
            ?? Bundle.main.url(forResource: "index", withExtension: "html")
            ?? { preconditionFailure("index.html not found in app bundle") }()
        
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
    
    func updatePropertyCoordinates(_ coordinates: [CLLocationCoordinate2D]) {
        currentCoordinates = coordinates
    }
}

enum PositioningStatus {
    case initializing
    case geoTrackingAvailable
    case planeDetectionActive
    case compassBearingActive
    case visualMarkerActive
    case manualAlignmentRequired
    case positioned
    case failed(String)
}