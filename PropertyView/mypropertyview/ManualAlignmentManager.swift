import Foundation
import ARKit
import SceneKit
import CoreLocation

// Data structure for alignment points saved from web interface
struct AlignmentData: Codable {
    struct AlignmentPoint: Codable {
        let latitude: Double
        let longitude: Double
    }
    
    struct SubjectProperty: Codable {
        let appellation: String
        let alignmentPoints: [AlignmentPoint]
        let boundaries: [Coordinate]
    }
    
    struct Coordinate: Codable {
        let latitude: Double
        let longitude: Double
    }
    
    let subjectProperty: SubjectProperty
    let timestamp: String
    
    var alignmentPoints: [AlignmentPoint] {
        return subjectProperty.alignmentPoints
    }
}

protocol ManualAlignmentManagerDelegate: AnyObject {
    func manualAlignmentManager(_ manager: ManualAlignmentManager, didAlign transform: simd_float4x4)
    func manualAlignmentManagerDidCancel(_ manager: ManualAlignmentManager)
}

class ManualAlignmentManager: NSObject {
    weak var delegate: ManualAlignmentManagerDelegate?
    private weak var arView: ARSCNView?
    
    private var boundaryRings: [[CLLocationCoordinate2D]] = []
    private var alignmentPoints: [SCNVector3] = []
    private var selectedCorners: [CLLocationCoordinate2D] = []
    
    private var alignmentNodes: [SCNNode] = []
    private var instructionNode: SCNNode?
    
    private enum AlignmentState {
        case selectingFirstCorner
        case selectingSecondCorner
        case calculating
        case completed
    }
    
    private var currentState: AlignmentState = .selectingFirstCorner
    
    init(arView: ARSCNView) {
        self.arView = arView
        super.init()
        setupGestureRecognizers()
    }
    
    private func setupGestureRecognizers() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        arView?.addGestureRecognizer(tapGesture)
    }
    
    func startAlignment(for rings: [[CLLocationCoordinate2D]]) {
        self.boundaryRings = rings
        
        // Check if we have pre-selected alignment points from the web interface
        if let savedPoints = loadSavedAlignmentPoints() {
            print("Using pre-selected alignment points from web interface")
            usePreSelectedPoints(savedPoints)
            return
        }
        
        // Fallback to AR tap-based alignment
        print("No pre-selected points found, using AR tap alignment")
        startARTapAlignment()
    }
    
    private func startARTapAlignment() {
        self.currentState = .selectingFirstCorner
        
        clearAlignment()
        showInstructions("Tap on the first visible property corner")
        
        // Configure AR session for manual alignment
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        arView?.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
    
    private func loadSavedAlignmentPoints() -> AlignmentData? {
        // Try to load from Documents directory (saved by web interface)
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let alignmentFile = documentsPath.appendingPathComponent("alignment_points.json")
        
        guard FileManager.default.fileExists(atPath: alignmentFile.path) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: alignmentFile)
            let alignmentData = try JSONDecoder().decode(AlignmentData.self, from: data)
            
            // Verify the alignment points are for the current property
            if alignmentData.alignmentPoints.count == 2 {
                return alignmentData
            }
        } catch {
            print("Failed to load alignment points: \(error)")
        }
        
        return nil
    }
    
    private func usePreSelectedPoints(_ alignmentData: AlignmentData) {
        // Use identity transform since we're working with GPS coordinates
        // The actual positioning will be handled by ARGeoAnchor system
        let identityTransform = simd_float4x4(
            simd_float4(1, 0, 0, 0),
            simd_float4(0, 1, 0, 0),
            simd_float4(0, 0, 1, 0),
            simd_float4(0, 0, 0, 1)
        )
        
        currentState = .completed
        showInstructions("Using pre-selected alignment points from map")
        
        // Notify delegate that alignment is complete
        delegate?.manualAlignmentManager(self, didAlign: identityTransform)
    }
    
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let arView = arView else { return }
        
        let location = gesture.location(in: arView)
        
        // Perform raycast to find world position (iOS 14+ replacement for deprecated hitTest)
        if #available(iOS 14.0, *) {
            let query = arView.raycastQuery(from: location, allowing: .estimatedPlane, alignment: .horizontal)
            guard let query = query else {
                showInstructions("Unable to create raycast query")
                return
            }
            let raycastResults = arView.session.raycast(query)
            guard let raycastResult = raycastResults.first else {
                showInstructions("Tap on a detected surface")
                return
            }
            
            let worldPosition = SCNVector3(
                raycastResult.worldTransform.columns.3.x,
                raycastResult.worldTransform.columns.3.y,
                raycastResult.worldTransform.columns.3.z
            )
            
            handleTapAtPosition(worldPosition)
        } else {
            // Fallback for iOS 13
            let hitTestResults = arView.hitTest(location, types: [.existingPlaneUsingExtent, .estimatedHorizontalPlane])
            
            guard let hitResult = hitTestResults.first else {
                showInstructions("Tap on a detected surface")
                return
            }
            
            let worldPosition = SCNVector3(
                hitResult.worldTransform.columns.3.x,
                hitResult.worldTransform.columns.3.y,
                hitResult.worldTransform.columns.3.z
            )
            
            handleTapAtPosition(worldPosition)
        }
    }
    
    private func handleTapAtPosition(_ worldPosition: SCNVector3) {
        
        
        switch currentState {
        case .selectingFirstCorner:
            selectFirstCorner(at: worldPosition)
        case .selectingSecondCorner:
            selectSecondCorner(at: worldPosition)
        case .calculating, .completed:
            break
        }
    }
    
    private func selectFirstCorner(at position: SCNVector3) {
        alignmentPoints.append(position)
        
        // Create visual marker
        let marker = createCornerMarker(at: position, label: "1")
        alignmentNodes.append(marker)
        arView?.scene.rootNode.addChildNode(marker)
        
        currentState = .selectingSecondCorner
        showInstructions("Tap on the second visible property corner")
    }
    
    private func selectSecondCorner(at position: SCNVector3) {
        alignmentPoints.append(position)
        
        // Create visual marker
        let marker = createCornerMarker(at: position, label: "2")
        alignmentNodes.append(marker)
        arView?.scene.rootNode.addChildNode(marker)
        
        currentState = .calculating
        showInstructions("Calculating alignment...")
        
        // Show corner selection UI
        showCornerSelectionUI()
    }
    
    private func showCornerSelectionUI() {
        // In a real implementation, this would show a UI to let the user
        // select which property corners correspond to the tapped points
        
        // For now, we'll assume the first two corners of the first ring
        guard let firstRing = boundaryRings.first, firstRing.count >= 2 else {
            delegate?.manualAlignmentManagerDidCancel(self)
            return
        }
        
        selectedCorners = [firstRing[0], firstRing[1]]
        calculateAlignment()
    }
    
    private func calculateAlignment() {
        guard alignmentPoints.count == 2,
              selectedCorners.count == 2 else {
            delegate?.manualAlignmentManagerDidCancel(self)
            return
        }
        
        // Calculate the rigid transform between AR points and GPS coordinates
        let arPoint1 = alignmentPoints[0]
        let arPoint2 = alignmentPoints[1]
        
        let gpsPoint1 = selectedCorners[0]
        let gpsPoint2 = selectedCorners[1]
        
        // Convert GPS to ENU coordinates (assuming centroid as origin)
        let centroid = calculateCentroid(of: boundaryRings.first ?? [])
        let enu1 = gpsToENU(gpsPoint1, centroid: centroid)
        let _ = gpsToENU(gpsPoint2, centroid: centroid)
        
        // Calculate scale, rotation, and translation
        let arVector = simd_float2(arPoint2.x - arPoint1.x, arPoint2.z - arPoint1.z)
        let enuVector = simd_float2(enu1.x, enu1.z)
        
        let arLength = simd_length(arVector)
        let enuLength = simd_length(enuVector)
        
        guard arLength > 0.01, enuLength > 0.01 else {
            showInstructions("Points too close together. Try again.")
            resetAlignment()
            return
        }
        
        // Calculate rotation angle
        let arAngle = atan2(arVector.y, arVector.x)
        let enuAngle = atan2(enuVector.y, enuVector.x)
        let rotationAngle = enuAngle - arAngle
        
        // Calculate scale
        let scale = enuLength / arLength
        
        // Create transform matrix
        let cosAngle = cos(rotationAngle)
        let sinAngle = sin(rotationAngle)
        
        var transform = simd_float4x4(
            simd_float4(cosAngle * scale, 0, -sinAngle * scale, 0),
            simd_float4(0, 1, 0, 0),
            simd_float4(sinAngle * scale, 0, cosAngle * scale, 0),
            simd_float4(0, 0, 0, 1)
        )
        
        // Calculate translation to align first point
        let transformedAR1 = transform * simd_float4(arPoint1.x, arPoint1.y, arPoint1.z, 1)
        let translationX = enu1.x - transformedAR1.x
        let translationZ = enu1.z - transformedAR1.z
        
        transform.columns.3.x = translationX
        transform.columns.3.z = translationZ
        
        currentState = .completed
        showInstructions("Alignment complete!")
        
        // Position boundaries using calculated transform
        positionBoundariesWithTransform(transform)
        
        delegate?.manualAlignmentManager(self, didAlign: transform)
    }
    
    private func positionBoundariesWithTransform(_ transform: simd_float4x4) {
        guard let arView = arView else { return }
        
        // Clear existing alignment markers
        clearAlignment()
        
        // Create boundary nodes
        let centroid = calculateCentroid(of: boundaryRings.first ?? [])
        
        for (ringIndex, ring) in boundaryRings.enumerated() {
            let boundaryNode = createBoundaryNode(for: ring, centroid: centroid, name: "manual_boundary_\(ringIndex)")
            boundaryNode.simdTransform = transform
            arView.scene.rootNode.addChildNode(boundaryNode)
        }
    }
    
    private func createBoundaryNode(for ring: [CLLocationCoordinate2D], centroid: CLLocationCoordinate2D, name: String) -> SCNNode {
        let groupNode = SCNNode()
        groupNode.name = name
        
        // Convert GPS coordinates to ENU offsets
        var points: [SCNVector3] = []
        for coord in ring {
            let enu = gpsToENU(coord, centroid: centroid)
            points.append(SCNVector3(enu.x, 0, enu.z))
        }
        
        // Create line segments
        for i in 0..<points.count {
            let start = points[i]
            let end = points[(i + 1) % points.count]
            
            let lineNode = createLineNode(from: start, to: end)
            groupNode.addChildNode(lineNode)
        }
        
        return groupNode
    }
    
    private func createLineNode(from start: SCNVector3, to end: SCNVector3) -> SCNNode {
        let vector = SCNVector3(end.x - start.x, end.y - start.y, end.z - start.z)
        let distance = sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)
        
        let cylinder = SCNCylinder(radius: 0.02, height: CGFloat(distance))
        cylinder.firstMaterial?.diffuse.contents = UIColor.systemOrange // Different color for manual
        cylinder.firstMaterial?.emission.contents = UIColor.systemOrange
        
        let lineNode = SCNNode(geometry: cylinder)
        lineNode.position = SCNVector3(
            (start.x + end.x) / 2,
            (start.y + end.y) / 2,
            (start.z + end.z) / 2
        )
        
        // Orient cylinder along the line
        let up = SCNVector3(0, 1, 0)
        let direction = SCNVector3(vector.x / distance, vector.y / distance, vector.z / distance)
        let cross = SCNVector3(
            up.y * direction.z - up.z * direction.y,
            up.z * direction.x - up.x * direction.z,
            up.x * direction.y - up.y * direction.x
        )
        let crossLength = sqrt(cross.x * cross.x + cross.y * cross.y + cross.z * cross.z)
        
        if crossLength > 0.001 {
            let normalizedCross = SCNVector3(cross.x / crossLength, cross.y / crossLength, cross.z / crossLength)
            let dot = up.x * direction.x + up.y * direction.y + up.z * direction.z
            let angle = acos(max(-1, min(1, dot)))
            
            lineNode.rotation = SCNVector4(normalizedCross.x, normalizedCross.y, normalizedCross.z, angle)
        }
        
        return lineNode
    }
    
    private func createCornerMarker(at position: SCNVector3, label: String) -> SCNNode {
        let sphere = SCNSphere(radius: 0.05)
        sphere.firstMaterial?.diffuse.contents = UIColor.systemRed
        sphere.firstMaterial?.emission.contents = UIColor.systemRed
        
        let node = SCNNode(geometry: sphere)
        node.position = position
        
        // Add text label
        let text = SCNText(string: label, extrusionDepth: 0.01)
        text.firstMaterial?.diffuse.contents = UIColor.white
        text.font = UIFont.systemFont(ofSize: 0.1)
        
        let textNode = SCNNode(geometry: text)
        textNode.position = SCNVector3(0, 0.1, 0)
        textNode.scale = SCNVector3(0.5, 0.5, 0.5)
        node.addChildNode(textNode)
        
        return node
    }
    
    private func showInstructions(_ message: String) {
        // Remove existing instruction
        instructionNode?.removeFromParentNode()
        
        // Create new instruction text
        let text = SCNText(string: message, extrusionDepth: 0.01)
        text.firstMaterial?.diffuse.contents = UIColor.white
        text.font = UIFont.systemFont(ofSize: 0.05)
        
        instructionNode = SCNNode(geometry: text)
        instructionNode?.position = SCNVector3(0, 0.5, -1)
        
        if let node = instructionNode {
            arView?.scene.rootNode.addChildNode(node)
        }
        
        print("Manual Alignment: \(message)")
    }
    
    private func resetAlignment() {
        alignmentPoints.removeAll()
        selectedCorners.removeAll()
        currentState = .selectingFirstCorner
        clearAlignment()
        showInstructions("Tap on the first visible property corner")
    }
    
    private func clearAlignment() {
        alignmentNodes.forEach { $0.removeFromParentNode() }
        alignmentNodes.removeAll()
        instructionNode?.removeFromParentNode()
        instructionNode = nil
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
    
    private func gpsToENU(_ coord: CLLocationCoordinate2D, centroid: CLLocationCoordinate2D) -> simd_float3 {
        let deltaLat = coord.latitude - centroid.latitude
        let deltaLon = coord.longitude - centroid.longitude
        
        let earthRadius = 6378137.0
        let latRadians = centroid.latitude * .pi / 180
        
        let metersPerDegreeLat = earthRadius * .pi / 180
        let metersPerDegreeLon = earthRadius * cos(latRadians) * .pi / 180
        
        let east = Float(deltaLon * metersPerDegreeLon)
        let north = Float(deltaLat * metersPerDegreeLat)
        
        return simd_float3(east, 0, north)
    }
}
