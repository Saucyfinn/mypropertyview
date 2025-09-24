import Foundation
import ARKit
import SceneKit
import CoreLocation

class ARManager: ObservableObject {
    @Published var isARSupported = false
    @Published var sessionStatus: ARSessionStatus = .initializing
    
    private var arView: ARSCNView?
    private var positioningManager: PositioningManager?
    
    init() {
        checkARSupport()
    }
    
    private func checkARSupport() {
        isARSupported = ARWorldTrackingConfiguration.isSupported
    }
    
    func setupSession(completion: @escaping (String?) -> Void) {
        guard isARSupported else {
            completion("AR not supported on this device")
            return
        }
        
        sessionStatus = .ready
        completion(nil)
    }
    
    func setARView(_ arView: ARSCNView) {
        self.arView = arView
        positioningManager = PositioningManager(arView: arView)
    }
    
    func loadCoordinates(_ coordinates: [CLLocationCoordinate2D]) {
        guard !coordinates.isEmpty else { return }
        
        let rings = [coordinates] // Convert to array of rings
        let centroid = calculateCentroid(of: coordinates)
        
        print("ARManager: Loading \(coordinates.count) coordinates into AR view")
        positioningManager?.startPositioning(for: rings, centroid: centroid)
    }
    
    func pauseSession() {
        arView?.session.pause()
        sessionStatus = .paused
        print("AR session paused")
    }
    
    func resetSession() {
        arView?.session.pause()
        
        // Clear all nodes
        arView?.scene.rootNode.childNodes.forEach { $0.removeFromParentNode() }
        
        // Reset configuration
        let configuration = ARWorldTrackingConfiguration()
        arView?.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        
        sessionStatus = .ready
        print("AR session reset")
    }
    
    private func calculateCentroid(of coordinates: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D {
        guard !coordinates.isEmpty else { return CLLocationCoordinate2D(latitude: 0, longitude: 0) }
        
        var totalLat = 0.0
        var totalLon = 0.0
        
        for coord in coordinates {
            totalLat += coord.latitude
            totalLon += coord.longitude
        }
        
        return CLLocationCoordinate2D(
            latitude: totalLat / Double(coordinates.count),
            longitude: totalLon / Double(coordinates.count)
        )
    }
}

enum ARSessionStatus {
    case initializing
    case ready
    case paused
    case error(String)
    
    var displayText: String {
        switch self {
        case .initializing:
            return "Initializing..."
        case .ready:
            return "Ready"
        case .paused:
            return "Paused"
        case .error(let message):
            return "Error: \(message)"
        }
    }
    
    var color: UIColor {
        switch self {
        case .initializing:
            return .systemYellow
        case .ready:
            return .systemGreen
        case .paused:
            return .systemOrange
        case .error:
            return .systemRed
        }
    }
}