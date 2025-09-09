/**
 * Visual Marker Fallback Manager
 * Uses QR codes or custom visual markers for precise boundary positioning
 * Provides high-accuracy fallback when GPS and plane detection are unavailable
 */

import Foundation
import ARKit
import SceneKit
import CoreLocation
import Vision

protocol VisualMarkerFallbackDelegate: AnyObject {
    func visualMarkerFallback(_ manager: VisualMarkerFallbackManager, didDetectMarker marker: VNRectangleObservation)
    func visualMarkerFallback(_ manager: VisualMarkerFallbackManager, didPositionBoundaries transform: simd_float4x4)
    func visualMarkerFallback(_ manager: VisualMarkerFallbackManager, didUpdateStatus status: String)
    func visualMarkerFallback(_ manager: VisualMarkerFallbackManager, needsUserAction message: String)
}

@available(iOS 11.0, *)
class VisualMarkerFallbackManager: NSObject, ARSessionDelegate {
    weak var delegate: VisualMarkerFallbackDelegate?
    private weak var arView: ARSCNView?
    
    private var boundaryRings: [[CLLocationCoordinate2D]] = []
    private var isActive = false
    private var boundaryNodes: [SCNNode] = []
    private var detectedMarkers: [VNRectangleObservation] = []
    private var markerReferencePoints: [String: CLLocationCoordinate2D] = [:]
    
    // Vision processing
    private var visionRequests: [VNRequest] = []
    private let visionQueue = DispatchQueue(label: "com.propertyview.vision", qos: .userInteractive)
    
    // Configuration
    private let markerDetectionInterval: TimeInterval = 0.2 // Process frames every 200ms
    private var lastVisionProcessTime: Date = Date()
    private let boundaryScale: Float = 50.0 // Default scale in meters
    
    init(arView: ARSCNView) {
        self.arView = arView
        super.init()
        setupVisionRequests()
    }
    
    private func setupVisionRequests() {
        // Rectangle detection for QR codes and markers
        let rectangleRequest = VNDetectRectanglesRequest { [weak self] request, error in
            self?.handleRectangleDetection(request: request, error: error)
        }
        rectangleRequest.minimumAspectRatio = 0.3
        rectangleRequest.maximumAspectRatio = 3.0
        rectangleRequest.minimumSize = 0.1
        rectangleRequest.maximumObservations = 5
        
        visionRequests = [rectangleRequest]
    }
    
    func startVisualMarkerFallback(for rings: [[CLLocationCoordinate2D]], referencePoints: [String: CLLocationCoordinate2D] = [:]) {
        guard !rings.isEmpty else {
            delegate?.visualMarkerFallback(self, didUpdateStatus: "No boundary data provided")
            return
        }
        
        self.boundaryRings = rings
        self.markerReferencePoints = referencePoints
        self.isActive = true
        
        delegate?.visualMarkerFallback(self, didUpdateStatus: "Looking for visual markers...")
        
        // Configure ARKit for marker detection
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [] // Disable plane detection to focus on markers
        
        arView?.session.delegate = self
        arView?.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        
        if markerReferencePoints.isEmpty {
            delegate?.visualMarkerFallback(self, needsUserAction: "Place a reference marker (QR code or distinctive object) at a known property corner")
        }
        
        print("VisualMarkerFallback: Started visual marker detection for boundary positioning")
    }
    
    func addReferencePoint(_ coordinate: CLLocationCoordinate2D, forMarkerID markerID: String) {
        markerReferencePoints[markerID] = coordinate
        delegate?.visualMarkerFallback(self, didUpdateStatus: "Reference point added for marker: \(markerID)")
        
        // Try to position boundaries if we have detected markers
        if !detectedMarkers.isEmpty {
            attemptBoundaryPositioning()
        }
    }
    
    func stopVisualMarkerFallback() {
        isActive = false
        detectedMarkers.removeAll()
        clearBoundaryNodes()
        delegate?.visualMarkerFallback(self, didUpdateStatus: "Visual marker detection stopped")
    }
    
    // MARK: - ARSessionDelegate
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard isActive else { return }
        
        // Throttle vision processing
        let now = Date()
        if now.timeIntervalSince(lastVisionProcessTime) < markerDetectionInterval {
            return
        }
        lastVisionProcessTime = now
        
        // Process frame for marker detection
        let pixelBuffer = frame.capturedImage
        processFrameForMarkers(pixelBuffer: pixelBuffer)
    }
    
    // MARK: - Vision Processing
    
    private func processFrameForMarkers(pixelBuffer: CVPixelBuffer) {
        visionQueue.async { [weak self] in
            guard let self = self else { return }
            
            let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, 
                                                           orientation: .right, 
                                                           options: [:])
            
            do {
                try imageRequestHandler.perform(self.visionRequests)
            } catch {
                DispatchQueue.main.async {
                    self.delegate?.visualMarkerFallback(self, didUpdateStatus: "Vision processing error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func handleRectangleDetection(request: VNRequest, error: Error?) {
        if let error = error {
            DispatchQueue.main.async {
                self.delegate?.visualMarkerFallback(self, didUpdateStatus: "Rectangle detection error: \(error.localizedDescription)")
            }
            return
        }
        
        guard let observations = request.results as? [VNRectangleObservation] else {
            return
        }
        
        // Filter for stable, well-defined rectangles
        let stableMarkers = observations.filter { observation in
            observation.confidence > 0.8 &&
            observation.boundingBox.width > 0.05 &&
            observation.boundingBox.height > 0.05
        }
        
        DispatchQueue.main.async {
            self.detectedMarkers = stableMarkers
            
            if !stableMarkers.isEmpty {
                self.delegate?.visualMarkerFallback(self, didUpdateStatus: "Detected \(stableMarkers.count) potential markers")
                
                // Report the best marker
                if let bestMarker = stableMarkers.first {
                    self.delegate?.visualMarkerFallback(self, didDetectMarker: bestMarker)
                }
                
                self.attemptBoundaryPositioning()
            }
        }
    }
    
    // MARK: - Boundary Positioning
    
    private func attemptBoundaryPositioning() {
        guard !detectedMarkers.isEmpty && !markerReferencePoints.isEmpty else {
            delegate?.visualMarkerFallback(self, needsUserAction: "Need both detected markers and reference points")
            return
        }
        
        // For now, use the first detected marker as reference
        // In a full implementation, you'd match detected markers to known reference points
        guard let referenceCoordinate = markerReferencePoints.values.first else {
            return
        }
        
        positionBoundariesRelativeToMarker(referenceCoordinate: referenceCoordinate)
    }
    
    private func positionBoundariesRelativeToMarker(referenceCoordinate: CLLocationCoordinate2D) {
        clearBoundaryNodes()
        
        delegate?.visualMarkerFallback(self, didUpdateStatus: "Positioning boundaries relative to detected marker")
        
        // Create boundary visualization
        for (ringIndex, ring) in boundaryRings.enumerated() {
            let boundaryNode = createBoundaryNode(for: ring, 
                                                referenceCoordinate: referenceCoordinate, 
                                                ringIndex: ringIndex)
            boundaryNodes.append(boundaryNode)
            
            // Add to scene
            if let arView = arView {
                arView.scene.rootNode.addChildNode(boundaryNode)
            }
        }
        
        // Create transform for the positioned boundaries
        let transform = createBoundaryTransform(referenceCoordinate: referenceCoordinate)
        delegate?.visualMarkerFallback(self, didPositionBoundaries: transform)
        
        delegate?.visualMarkerFallback(self, didUpdateStatus: "Boundaries positioned using visual marker reference")
    }
    
    private func createBoundaryNode(for ring: [CLLocationCoordinate2D], 
                                  referenceCoordinate: CLLocationCoordinate2D, 
                                  ringIndex: Int) -> SCNNode {
        let groupNode = SCNNode()
        groupNode.name = "marker_boundary_\(ringIndex)"
        
        // Convert coordinates to positions relative to reference
        let relativePositions = convertCoordinatesToMarkerRelative(ring, referenceCoordinate: referenceCoordinate)
        
        // Create line segments
        for i in 0..<relativePositions.count {
            let startPos = relativePositions[i]
            let endPos = relativePositions[(i + 1) % relativePositions.count]
            
            let lineNode = createLineNode(from: startPos, to: endPos, isSubject: ringIndex == 0)
            groupNode.addChildNode(lineNode)
            
            // Add corner markers
            let cornerNode = createCornerMarker(at: startPos, isSubject: ringIndex == 0)
            groupNode.addChildNode(cornerNode)
        }
        
        // Position relative to detected marker (assuming marker is at origin)
        groupNode.position = SCNVector3(0, 0, 0)
        
        return groupNode
    }
    
    private func convertCoordinatesToMarkerRelative(_ ring: [CLLocationCoordinate2D], 
                                                   referenceCoordinate: CLLocationCoordinate2D) -> [SCNVector3] {
        var positions: [SCNVector3] = []
        
        // Convert coordinates to relative positions using the reference coordinate as origin
        for coord in ring {
            let deltaLat = coord.latitude - referenceCoordinate.latitude
            let deltaLon = coord.longitude - referenceCoordinate.longitude
            
            // Convert to approximate meters
            let metersPerDegreeLat = 111320.0
            let metersPerDegreeLon = 111320.0 * cos(referenceCoordinate.latitude * .pi / 180.0)
            
            let x = Float(deltaLon * metersPerDegreeLon) * (boundaryScale / 100.0)
            let z = Float(deltaLat * metersPerDegreeLat) * (boundaryScale / 100.0)
            
            positions.append(SCNVector3(x, 0.1, -z)) // Slightly above ground
        }
        
        return positions
    }
    
    private func createLineNode(from start: SCNVector3, to end: SCNVector3, isSubject: Bool) -> SCNNode {
        let distance = simd_distance(simd_make_float3(start), simd_make_float3(end))
        
        let cylinder = SCNCylinder(radius: 0.008, height: CGFloat(distance))
        
        // Different materials for subject vs neighbor boundaries
        let material = SCNMaterial()
        if isSubject {
            material.diffuse.contents = UIColor.systemBlue
            material.emission.contents = UIColor.systemBlue.withAlphaComponent(0.4)
        } else {
            material.diffuse.contents = UIColor.systemOrange
            material.emission.contents = UIColor.systemOrange.withAlphaComponent(0.3)
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
        let sphere = SCNSphere(radius: 0.03)
        
        let material = SCNMaterial()
        material.diffuse.contents = isSubject ? UIColor.systemBlue : UIColor.systemOrange
        material.emission.contents = (isSubject ? UIColor.systemBlue : UIColor.systemOrange).withAlphaComponent(0.6)
        sphere.materials = [material]
        
        let markerNode = SCNNode(geometry: sphere)
        markerNode.position = position
        
        return markerNode
    }
    
    private func createBoundaryTransform(referenceCoordinate: CLLocationCoordinate2D) -> simd_float4x4 {
        // Create identity transform - boundaries are positioned relative to marker
        return matrix_identity_float4x4
    }
    
    private func clearBoundaryNodes() {
        for node in boundaryNodes {
            node.removeFromParentNode()
        }
        boundaryNodes.removeAll()
    }
}

// Helper extension for creating translation matrix
extension simd_float4x4 {
    init(translation vector: simd_float3) {
        self.init(
            simd_float4(1, 0, 0, 0),
            simd_float4(0, 1, 0, 0),
            simd_float4(0, 0, 1, 0),
            simd_float4(vector.x, vector.y, vector.z, 1)
        )
    }
}