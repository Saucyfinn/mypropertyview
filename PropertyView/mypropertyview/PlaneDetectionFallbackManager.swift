/**
 * Plane Detection Fallback Manager
 * Uses ARKit plane detection to anchor property boundaries to detected surfaces
 * Provides fallback when GPS geo-anchoring is unavailable
 */

import Foundation
import ARKit
import SceneKit
import CoreLocation

protocol PlaneDetectionFallbackDelegate: AnyObject {
    func planeDetectionFallback(_ manager: PlaneDetectionFallbackManager, didDetectSuitablePlane plane: ARPlaneAnchor)
    func planeDetectionFallback(_ manager: PlaneDetectionFallbackManager, didPositionBoundaries transform: simd_float4x4)
    func planeDetectionFallback(_ manager: PlaneDetectionFallbackManager, didUpdateStatus status: String)
}

@available(iOS 11.0, *)
class PlaneDetectionFallbackManager: NSObject, ARSessionDelegate, ARSCNViewDelegate {
    weak var delegate: PlaneDetectionFallbackDelegate?
    private weak var arView: ARSCNView?
    
    private var boundaryRings: [[CLLocationCoordinate2D]] = []
    private var detectedPlanes: [UUID: ARPlaneAnchor] = [:]
    private var boundaryNodes: [SCNNode] = []
    private var isActive = false
    private var targetPlane: ARPlaneAnchor?
    private var planeDetectionStartTime: Date?
    
    // Configuration
    private let minimumPlaneArea: Float = 0.5 // Minimum plane area in square meters
    private let maxDetectionTime: TimeInterval = 10.0 // Max time to wait for suitable plane
    private let preferredPlaneTypes: ARPlaneDetection = [.horizontal]
    
    init(arView: ARSCNView) {
        self.arView = arView
        super.init()
    }
    
    func startPlaneDetectionFallback(for rings: [[CLLocationCoordinate2D]]) {
        guard !rings.isEmpty else {
            delegate?.planeDetectionFallback(self, didUpdateStatus: "No boundary data provided")
            return
        }
        
        self.boundaryRings = rings
        self.isActive = true
        self.planeDetectionStartTime = Date()
        
        delegate?.planeDetectionFallback(self, didUpdateStatus: "Detecting surfaces...")
        
        // Configure ARKit for plane detection
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = preferredPlaneTypes
        configuration.isLightEstimationEnabled = true
        
        arView?.session.delegate = self
        arView?.delegate = self
        arView?.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        
        // Set timeout for plane detection
        DispatchQueue.main.asyncAfter(deadline: .now() + maxDetectionTime) { [weak self] in
            self?.handleDetectionTimeout()
        }
        
        print("PlaneDetectionFallback: Started plane detection for boundary positioning")
    }
    
    func stopPlaneDetectionFallback() {
        isActive = false
        detectedPlanes.removeAll()
        clearBoundaryNodes()
        delegate?.planeDetectionFallback(self, didUpdateStatus: "Plane detection stopped")
    }
    
    // MARK: - ARSessionDelegate
    
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        guard isActive else { return }
        
        for anchor in anchors {
            if let planeAnchor = anchor as? ARPlaneAnchor {
                detectedPlanes[anchor.identifier] = planeAnchor
                evaluatePlaneForBoundaryPlacement(planeAnchor)
            }
        }
    }
    
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard isActive else { return }
        
        for anchor in anchors {
            if let planeAnchor = anchor as? ARPlaneAnchor {
                detectedPlanes[anchor.identifier] = planeAnchor
                
                // Re-evaluate updated plane if it's our target
                if targetPlane?.identifier == anchor.identifier {
                    evaluatePlaneForBoundaryPlacement(planeAnchor)
                }
            }
        }
    }
    
    // MARK: - Plane Evaluation and Boundary Placement
    
    private func evaluatePlaneForBoundaryPlacement(_ plane: ARPlaneAnchor) {
        // Check if plane is suitable for boundary placement
        let planeArea = plane.extent.x * plane.extent.z
        
        guard planeArea >= minimumPlaneArea else {
            print("PlaneDetectionFallback: Plane too small (\(planeArea) sq m)")
            return
        }
        
        // Prefer horizontal planes for boundary placement
        let planeNormal = simd_make_float3(plane.transform.columns.1)
        let upVector = simd_make_float3(0, 1, 0)
        let alignment = simd_dot(planeNormal, upVector)
        
        if alignment > 0.8 { // Nearly horizontal
            print("PlaneDetectionFallback: Found suitable horizontal plane (area: \(planeArea) sq m)")
            targetPlane = plane
            delegate?.planeDetectionFallback(self, didDetectSuitablePlane: plane)
            positionBoundariesOnPlane(plane)
        }
    }
    
    private func positionBoundariesOnPlane(_ plane: ARPlaneAnchor) {
        clearBoundaryNodes()
        
        // Calculate boundary centroid for positioning
        guard let firstRing = boundaryRings.first, !firstRing.isEmpty else {
            delegate?.planeDetectionFallback(self, didUpdateStatus: "Invalid boundary data")
            return
        }
        
        let centroid = calculateCentroid(of: firstRing)
        print("PlaneDetectionFallback: Positioning boundaries with centroid at \(centroid)")
        
        // Create boundary visualization on the detected plane
        for (ringIndex, ring) in boundaryRings.enumerated() {
            let boundaryNode = createBoundaryNode(for: ring, on: plane, ringIndex: ringIndex)
            boundaryNodes.append(boundaryNode)
            
            // Add to scene
            if let arView = arView {
                arView.scene.rootNode.addChildNode(boundaryNode)
            }
        }
        
        delegate?.planeDetectionFallback(self, didUpdateStatus: "Boundaries positioned on detected surface")
        delegate?.planeDetectionFallback(self, didPositionBoundaries: plane.transform)
        
        isActive = false // Stop looking for more planes
    }
    
    private func createBoundaryNode(for ring: [CLLocationCoordinate2D], on plane: ARPlaneAnchor, ringIndex: Int) -> SCNNode {
        let groupNode = SCNNode()
        groupNode.name = "plane_boundary_\(ringIndex)"
        
        // Convert coordinates to relative positions on the plane
        let relativePositions = convertCoordinatesToPlaneRelative(ring, plane: plane)
        
        // Create line segments connecting the boundary points
        for i in 0..<relativePositions.count {
            let startPos = relativePositions[i]
            let endPos = relativePositions[(i + 1) % relativePositions.count]
            
            let lineNode = createLineNode(from: startPos, to: endPos)
            groupNode.addChildNode(lineNode)
        }
        
        // Position the group node on the plane
        groupNode.transform = SCNMatrix4(plane.transform)
        
        return groupNode
    }
    
    private func convertCoordinatesToPlaneRelative(_ ring: [CLLocationCoordinate2D], plane: ARPlaneAnchor) -> [SCNVector3] {
        guard let firstCoord = ring.first else { return [] }
        
        var positions: [SCNVector3] = []
        
        // Use simple relative positioning - scale coordinates to fit within plane bounds
        let maxExtent = max(plane.extent.x, plane.extent.z) * 0.8 // Use 80% of plane size
        let coordRange = ring.reduce((minLat: firstCoord.latitude, maxLat: firstCoord.latitude, 
                                     minLon: firstCoord.longitude, maxLon: firstCoord.longitude)) { result, coord in
            (min(result.minLat, coord.latitude), max(result.maxLat, coord.latitude),
             min(result.minLon, coord.longitude), max(result.maxLon, coord.longitude))
        }
        
        let latRange = coordRange.maxLat - coordRange.minLat
        let lonRange = coordRange.maxLon - coordRange.minLon
        let maxRange = max(latRange, lonRange)
        
        for coord in ring {
            let normalizedX = Float((coord.longitude - coordRange.minLon) / maxRange - 0.5) * maxExtent
            let normalizedZ = Float((coord.latitude - coordRange.minLat) / maxRange - 0.5) * maxExtent
            
            positions.append(SCNVector3(normalizedX, 0.01, normalizedZ)) // Slightly above plane
        }
        
        return positions
    }
    
    private func createLineNode(from start: SCNVector3, to end: SCNVector3) -> SCNNode {
        let distance = simd_distance(simd_make_float3(start), simd_make_float3(end))
        
        // Create cylinder geometry for the line
        let cylinder = SCNCylinder(radius: 0.002, height: CGFloat(distance))
        
        // Blue material for property boundaries
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.systemBlue
        material.emission.contents = UIColor.systemBlue.withAlphaComponent(0.2)
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
    
    private func handleDetectionTimeout() {
        guard isActive else { return }
        
        if targetPlane == nil {
            delegate?.planeDetectionFallback(self, didUpdateStatus: "No suitable surface found - tap to place boundaries manually")
            isActive = false
        }
    }
    
    private func clearBoundaryNodes() {
        for node in boundaryNodes {
            node.removeFromParentNode()
        }
        boundaryNodes.removeAll()
    }
    
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
}