/**
 * Compass Bearing Fallback Manager
 * Uses device compass and user input to orient property boundaries
 * Provides low-tech fallback when other positioning methods fail
 */

import Foundation
import CoreLocation
import ARKit
import SceneKit

protocol CompassBearingFallbackDelegate: AnyObject {
    func compassBearingFallback(_ manager: CompassBearingFallbackManager, didUpdateHeading heading: CLLocationDirection)
    func compassBearingFallback(_ manager: CompassBearingFallbackManager, didPositionBoundaries transform: simd_float4x4)
    func compassBearingFallback(_ manager: CompassBearingFallbackManager, didUpdateStatus status: String)
    func compassBearingFallback(_ manager: CompassBearingFallbackManager, needsUserInput message: String)
}

class CompassBearingFallbackManager: NSObject, CLLocationManagerDelegate {
    weak var delegate: CompassBearingFallbackDelegate?
    private weak var arView: ARSCNView?
    
    private let locationManager = CLLocationManager()
    private var boundaryRings: [[CLLocationCoordinate2D]] = []
    private var isActive = false
    private var currentHeading: CLLocationDirection = 0
    private var boundaryNodes: [SCNNode] = []
    private var userBearing: CLLocationDirection?
    private var boundaryScale: Float = 50.0 // Default scale in meters
    
    // Compass accuracy threshold
    private let minimumHeadingAccuracy: CLLocationDirection = 15.0
    
    init(arView: ARSCNView) {
        self.arView = arView
        super.init()
        setupLocationManager()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        
        // Request location permission if needed
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
    }
    
    func startCompassBearingFallback(for rings: [[CLLocationCoordinate2D]], userBearing: CLLocationDirection? = nil, scale: Float = 50.0) {
        guard !rings.isEmpty else {
            delegate?.compassBearingFallback(self, didUpdateStatus: "No boundary data provided")
            return
        }
        
        self.boundaryRings = rings
        self.userBearing = userBearing
        self.boundaryScale = scale
        self.isActive = true
        
        delegate?.compassBearingFallback(self, didUpdateStatus: "Starting compass-based positioning...")
        
        // Start compass updates
        if CLLocationManager.headingAvailable() {
            locationManager.startUpdatingHeading()
            
            if userBearing == nil {
                delegate?.compassBearingFallback(self, needsUserInput: "Please face north and tap 'Set Bearing' or enter known bearing")
            } else {
                positionBoundariesWithBearing()
            }
        } else {
            delegate?.compassBearingFallback(self, didUpdateStatus: "Compass not available on this device")
        }
        
        // Configure basic AR tracking
        let configuration = ARWorldTrackingConfiguration()
        arView?.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        
        print("CompassBearingFallback: Started compass-based boundary positioning")
    }
    
    func setUserBearing(_ bearing: CLLocationDirection) {
        self.userBearing = bearing
        delegate?.compassBearingFallback(self, didUpdateStatus: "User bearing set to \(Int(bearing))°")
        positionBoundariesWithBearing()
    }
    
    func setCurrentHeadingAsBearing() {
        if currentHeading > 0 {
            setUserBearing(currentHeading)
        }
    }
    
    func updateScale(_ scale: Float) {
        self.boundaryScale = scale
        if isActive {
            positionBoundariesWithBearing()
        }
    }
    
    func stopCompassBearingFallback() {
        isActive = false
        locationManager.stopUpdatingHeading()
        clearBoundaryNodes()
        delegate?.compassBearingFallback(self, didUpdateStatus: "Compass positioning stopped")
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard isActive else { return }
        
        // Use magnetic heading, adjust for true north if needed
        let heading = newHeading.magneticHeading
        
        // Check heading accuracy
        if newHeading.headingAccuracy < 0 || newHeading.headingAccuracy > minimumHeadingAccuracy {
            delegate?.compassBearingFallback(self, didUpdateStatus: "Compass accuracy poor - move away from metal objects")
            return
        }
        
        currentHeading = heading
        delegate?.compassBearingFallback(self, didUpdateHeading: heading)
        
        // Update boundary orientation if we have a user bearing
        if userBearing != nil {
            updateBoundaryOrientation()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        delegate?.compassBearingFallback(self, didUpdateStatus: "Location error: \(error.localizedDescription)")
    }
    
    // MARK: - Boundary Positioning
    
    private func positionBoundariesWithBearing() {
        guard let bearing = userBearing else {
            delegate?.compassBearingFallback(self, needsUserInput: "Please set a reference bearing first")
            return
        }
        
        clearBoundaryNodes()
        
        delegate?.compassBearingFallback(self, didUpdateStatus: "Positioning boundaries with bearing \(Int(bearing))°")
        
        // Create boundary visualization
        for (ringIndex, ring) in boundaryRings.enumerated() {
            let boundaryNode = createBoundaryNode(for: ring, bearing: bearing, ringIndex: ringIndex)
            boundaryNodes.append(boundaryNode)
            
            // Add to scene
            if let arView = arView {
                arView.scene.rootNode.addChildNode(boundaryNode)
            }
        }
        
        // Create transform representing the positioned boundaries
        let transform = createBoundaryTransform(bearing: bearing)
        delegate?.compassBearingFallback(self, didPositionBoundaries: transform)
        
        delegate?.compassBearingFallback(self, didUpdateStatus: "Boundaries positioned with compass bearing")
    }
    
    private func updateBoundaryOrientation() {
        guard let bearing = userBearing else { return }
        
        // Update existing boundary nodes with new orientation
        for node in boundaryNodes {
            updateNodeOrientation(node, bearing: bearing)
        }
    }
    
    private func createBoundaryNode(for ring: [CLLocationCoordinate2D], bearing: CLLocationDirection, ringIndex: Int) -> SCNNode {
        let groupNode = SCNNode()
        groupNode.name = "compass_boundary_\(ringIndex)"
        
        // Convert coordinates to relative positions
        let relativePositions = convertCoordinatesToRelative(ring)
        
        // Create line segments
        for i in 0..<relativePositions.count {
            let startPos = relativePositions[i]
            let endPos = relativePositions[(i + 1) % relativePositions.count]
            
            let lineNode = createLineNode(from: startPos, to: endPos, isSubject: ringIndex == 0)
            groupNode.addChildNode(lineNode)
            
            // Add corner markers for better visibility
            let cornerNode = createCornerMarker(at: startPos, isSubject: ringIndex == 0)
            groupNode.addChildNode(cornerNode)
        }
        
        // Apply bearing rotation and position in front of user
        updateNodeOrientation(groupNode, bearing: bearing)
        groupNode.position = SCNVector3(0, -0.5, -2) // 2 meters in front, 0.5m below camera
        
        return groupNode
    }
    
    private func updateNodeOrientation(_ node: SCNNode, bearing: CLLocationDirection) {
        // Calculate rotation based on bearing difference from current heading
        let headingDiff = bearing - currentHeading
        let rotationY = Float(headingDiff * .pi / 180.0)
        
        node.eulerAngles.y = rotationY
    }
    
    private func convertCoordinatesToRelative(_ ring: [CLLocationCoordinate2D]) -> [SCNVector3] {
        guard let firstCoord = ring.first else { return [] }
        
        var positions: [SCNVector3] = []
        
        // Calculate coordinate bounds
        let coordBounds = ring.reduce((minLat: firstCoord.latitude, maxLat: firstCoord.latitude, 
                                      minLon: firstCoord.longitude, maxLon: firstCoord.longitude)) { result, coord in
            (min(result.minLat, coord.latitude), max(result.maxLat, coord.latitude),
             min(result.minLon, coord.longitude), max(result.maxLon, coord.longitude))
        }
        
        let centerLat = (coordBounds.minLat + coordBounds.maxLat) / 2
        let centerLon = (coordBounds.minLon + coordBounds.maxLon) / 2
        
        // Convert to relative positions using approximate meters per degree
        for coord in ring {
            let deltaLat = coord.latitude - centerLat
            let deltaLon = coord.longitude - centerLon
            
            // Approximate conversion to meters (more accurate near equator)
            let metersPerDegreeLat = 111320.0
            let metersPerDegreeLon = 111320.0 * cos(centerLat * .pi / 180.0)
            
            let x = Float(deltaLon * metersPerDegreeLon) * (boundaryScale / 100.0)
            let z = Float(deltaLat * metersPerDegreeLat) * (boundaryScale / 100.0)
            
            positions.append(SCNVector3(x, 0, -z)) // Negative Z for correct orientation
        }
        
        return positions
    }
    
    private func createLineNode(from start: SCNVector3, to end: SCNVector3, isSubject: Bool) -> SCNNode {
        let distance = simd_distance(simd_make_float3(start), simd_make_float3(end))
        
        let cylinder = SCNCylinder(radius: 0.005, height: CGFloat(distance))
        
        // Different colors for subject vs neighbor boundaries
        let material = SCNMaterial()
        if isSubject {
            material.diffuse.contents = UIColor.systemBlue
            material.emission.contents = UIColor.systemBlue.withAlphaComponent(0.3)
        } else {
            material.diffuse.contents = UIColor.systemRed
            material.emission.contents = UIColor.systemRed.withAlphaComponent(0.2)
        }
        cylinder.materials = [material]
        
        let lineNode = SCNNode(geometry: cylinder)
        
        // Position and orient the line
        let midPoint = SCNVector3(
            (start.x + end.x) / 2,
            (start.y + end.y) / 2,
            (start.z + end.z) / 2
        )
        
        lineNode.position = midPoint
        
        // Orient cylinder along the line
        let direction = simd_normalize(simd_make_float3(end) - simd_make_float3(start))
        let up = simd_make_float3(0, 1, 0)
        
        if abs(simd_dot(direction, up)) < 0.99 {
            let right = simd_normalize(simd_cross(direction, up))
            let realUp = simd_cross(right, direction)
            
            let rotationMatrix = simd_float3x3(right, realUp, -direction)
            lineNode.simdOrientation = simd_quaternion(rotationMatrix)
        }
        
        return lineNode
    }
    
    private func createCornerMarker(at position: SCNVector3, isSubject: Bool) -> SCNNode {
        let sphere = SCNSphere(radius: 0.02)
        
        let material = SCNMaterial()
        material.diffuse.contents = isSubject ? UIColor.systemBlue : UIColor.systemRed
        material.emission.contents = (isSubject ? UIColor.systemBlue : UIColor.systemRed).withAlphaComponent(0.5)
        sphere.materials = [material]
        
        let markerNode = SCNNode(geometry: sphere)
        markerNode.position = position
        
        return markerNode
    }
    
    private func createBoundaryTransform(bearing: CLLocationDirection) -> simd_float4x4 {
        // Create transform representing the boundary placement
        let rotationY = Float(bearing * .pi / 180.0)
        let rotation = simd_float4x4(simd_quaternion(angle: rotationY, axis: simd_make_float3(0, 1, 0)))
        let translation = simd_float4x4(translation: simd_make_float3(0, -0.5, -2))
        
        return simd_mul(translation, rotation)
    }
    
    private func clearBoundaryNodes() {
        for node in boundaryNodes {
            node.removeFromParentNode()
        }
        boundaryNodes.removeAll()
    }
}