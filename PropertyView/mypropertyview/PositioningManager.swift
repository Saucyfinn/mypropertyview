import Foundation
import ARKit
import CoreLocation
import SceneKit

enum PositioningMethod {
    case geoTracking
    case manualAlignment
    case fallback
}

enum PositioningStatus {
    case initializing
    case geoTrackingAvailable
    case manualAlignmentRequired
    case positioned
    case failed(String)
}

protocol PositioningManagerDelegate: AnyObject {
    func positioningManager(_ manager: PositioningManager, didUpdateStatus status: PositioningStatus)
    func positioningManager(_ manager: PositioningManager, didUpdateMethod method: PositioningMethod)
    func positioningManager(_ manager: PositioningManager, didPositionBoundaries transform: simd_float4x4)
}

class PositioningManager: NSObject {
    weak var delegate: PositioningManagerDelegate?
    private weak var arView: ARSCNView?
    
    private var currentMethod: PositioningMethod = .fallback
    private var currentStatus: PositioningStatus = .initializing
    
    // ARKit GeoTracking
    private var geoAnchorManager: ARGeoAnchorManager?
    
    // Manual Alignment
    private var manualAlignmentManager: ManualAlignmentManager?
    
    // Property data
    private var boundaryRings: [[CLLocationCoordinate2D]] = []
    private var propertyCentroid: CLLocationCoordinate2D?
    
    init(arView: ARSCNView) {
        self.arView = arView
        super.init()
        setupPositioningSystem()
    }
    
    private func setupPositioningSystem() {
        updateStatus(.initializing)
        determineOptimalPositioningMethod()
    }
    
    func setBoundaryRings(_ rings: [[CLLocationCoordinate2D]]) {
        self.boundaryRings = rings
        self.propertyCentroid = calculateCentroid(of: rings.first ?? [])
        
        print("PositioningManager: Setting boundary rings with \(rings.count) rings")
        if let centroid = propertyCentroid {
            print("Property centroid: \(centroid.latitude), \(centroid.longitude)")
        }
        
        // Restart positioning with new data
        determineOptimalPositioningMethod()
    }
    
    private func determineOptimalPositioningMethod() {
        guard !boundaryRings.isEmpty else {
            print("No boundary rings to position")
            return
        }
        
        print("Determining positioning method for \(boundaryRings.count) rings")
        
        // Priority 1: ARKit GeoTracking (iOS 14+ with VPS coverage)
        if #available(iOS 14.0, *), ARGeoTrackingConfiguration.isSupported {
            print("ARGeoTracking supported, checking availability...")
            checkGeoTrackingAvailability()
        } else {
            print("ARGeoTracking not supported, using manual alignment fallback")
            // Priority 2: Manual alignment fallback
            initializeManualAlignment()
        }
    }
    
    @available(iOS 14.0, *)
    private func checkGeoTrackingAvailability() {
        guard let centroid = propertyCentroid else {
            print("No property centroid available, falling back to manual alignment")
            initializeManualAlignment()
            return
        }
        
        print("Checking ARGeoTracking availability at: \(centroid.latitude), \(centroid.longitude)")
        
        ARGeoTrackingConfiguration.checkAvailability(at: centroid) { [weak self] available, error in
            DispatchQueue.main.async {
                if available {
                    print("ARGeoTracking available at location")
                    self?.useGeoTracking()
                } else {
                    print("ARGeoTracking not available at location: \(error?.localizedDescription ?? "Unknown")")
                    print("Falling back to manual alignment")
                    self?.initializeManualAlignment()
                }
            }
        }
    }
    
    @available(iOS 14.0, *)
    private func useGeoTracking() {
        currentMethod = .geoTracking
        delegate?.positioningManager(self, didUpdateMethod: .geoTracking)
        updateStatus(.geoTrackingAvailable)
        
        guard let arView = arView else { return }
        
        geoAnchorManager = ARGeoAnchorManager(arView: arView) { status in
            // Handle geo anchor status updates
            print("GeoAnchor status: \(status)")
        }
        
        positionBoundaries()
    }
    
    
    private func initializeManualAlignment() {
        currentMethod = .manualAlignment
        delegate?.positioningManager(self, didUpdateMethod: .manualAlignment)
        updateStatus(.manualAlignmentRequired)
        
        guard let arView = arView else { return }
        
        manualAlignmentManager = ManualAlignmentManager(arView: arView)
        manualAlignmentManager?.delegate = self
        manualAlignmentManager?.startAlignment(for: boundaryRings)
    }
    
    private func positionBoundaries() {
        switch currentMethod {
        case .geoTracking:
            positionWithGeoTracking()
        case .manualAlignment:
            // Handled by ManualAlignmentManager delegate
            break
        case .fallback:
            positionWithFallback()
        }
    }
    
    @available(iOS 14.0, *)
    private func positionWithGeoTracking() {
        guard let geoAnchorManager = geoAnchorManager else { 
            print("ERROR: geoAnchorManager is nil")
            return 
        }
        
        print("Positioning with GeoTracking: \(boundaryRings.count) rings")
        for (i, ring) in boundaryRings.enumerated() {
            print("Ring \(i): \(ring.count) coordinates")
            if let first = ring.first {
                print("  First coord: \(first.latitude), \(first.longitude)")
            }
        }
        
        geoAnchorManager.addBoundaryRings(boundaryRings)
        updateStatus(.positioned)
    }
    
    
    private func positionWithFallback() {
        // Use existing relative positioning system
        updateStatus(.positioned)
    }
    
    // MARK: - Utility Methods
    
    private func calculateCentroid(of ring: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D {
        guard !ring.isEmpty else { return CLLocationCoordinate2D(latitude: 0, longitude: 0) }
        
        var totalLat = 0.0
        var totalLon = 0.0
        
        for coord in ring {
            totalLat += coord.latitude
            totalLon += coord.longitude
        }
        
        return CLLocationCoordinate2D(
            latitude: totalLat / Double(ring.count),
            longitude: totalLon / Double(ring.count)
        )
    }
    
    
    private func updateStatus(_ status: PositioningStatus) {
        currentStatus = status
        delegate?.positioningManager(self, didUpdateStatus: status)
    }
}


// MARK: - ManualAlignmentManagerDelegate

extension PositioningManager: ManualAlignmentManagerDelegate {
    func manualAlignmentManager(_ manager: ManualAlignmentManager, didAlign transform: simd_float4x4) {
        updateStatus(.positioned)
        delegate?.positioningManager(self, didPositionBoundaries: transform)
    }
    
    func manualAlignmentManagerDidCancel(_ manager: ManualAlignmentManager) {
        updateStatus(.failed("Manual alignment cancelled"))
    }
}
