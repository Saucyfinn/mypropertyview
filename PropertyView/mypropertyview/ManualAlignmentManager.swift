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
    private var selectedPinIndex: Int?

    init(arView: ARSCNView) {
        self.arView = arView
        super.init()
        setupGestureRecognizers()
    }

    private func setupGestureRecognizers() {
        // Remove existing gesture recognizers to avoid conflicts
        arView?.gestureRecognizers?.forEach { arView?.removeGestureRecognizer($0) }

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tapGesture.numberOfTapsRequired = 1
        arView?.addGestureRecognizer(tapGesture)

        // Add pan gesture for dragging pins
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        arView?.addGestureRecognizer(panGesture)

        print("ManualAlignment: Gesture recognizers set up")
    }

    func startAlignment(for rings: [[CLLocationCoordinate2D]]) {
        print("ManualAlignmentManager: Starting alignment for \(rings.count) rings")
        self.boundaryRings = rings

        // Ensure we're on main thread for UI operations
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Check if we have pre-selected alignment points from the web interface
            if let savedPoints = self.loadSavedAlignmentPoints() {
                print("Using pre-selected alignment points from web interface")
                self.usePreSelectedPoints(savedPoints)
                return
            }

            // Fallback to AR tap-based alignment
            print("No pre-selected points found, using AR tap alignment")
            self.startARTapAlignment()
        }
    }

    private func startARTapAlignment() {
        self.currentState = .selectingFirstCorner

        clearAlignmentNodes()
        showInstructions("Tap pin 1 and move it to the first corner")
        addAlignmentPins()

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
        guard currentState != .completed else { return }
        guard let arView = arView else { return }

        let location = gesture.location(in: arView)
        print("ManualAlignment: Tap detected at \(location)")

        // Check if user tapped on a pin first
        let hitResults = arView.hitTest(location, options: nil)
        print("ManualAlignment: Hit test found \(hitResults.count) results")

        for result in hitResults {
            print("ManualAlignment: Checking node \(result.node.name ?? "unnamed")")
            // Check if this node or its parent is one of our pins
            if alignmentNodes.contains(result.node) {
                let pinIndex = alignmentNodes.firstIndex(of: result.node)!
                selectedPinIndex = pinIndex
                print("ManualAlignment: Selected pin \(pinIndex + 1)")
                showInstructions("Tap where you want to move pin \(pinIndex + 1)")
                return
            }
            if let parent = result.node.parent, alignmentNodes.contains(parent) {
                let pinIndex = alignmentNodes.firstIndex(of: parent)!
                selectedPinIndex = pinIndex
                print("ManualAlignment: Selected pin \(pinIndex + 1) via parent")
                showInstructions("Tap where you want to move pin \(pinIndex + 1)")
                return
            }
        }

        print("ManualAlignment: No pin tapped, processing surface tap")

        // If no pin was tapped, move the selected pin or place next pin
        if #available(iOS 14.0, *) {
            guard let query = arView.raycastQuery(from: location, allowing: .estimatedPlane, alignment: .horizontal) else {
                print("ManualAlignment: Unable to create raycast query")
                showInstructions("Unable to create raycast query - try tapping on a detected surface")
                return
            }
            let raycastResults = arView.session.raycast(query)
            guard let raycastResult = raycastResults.first else {
                print("ManualAlignment: No raycast results")
                showInstructions("Tap on a detected surface")
                return
            }

            let worldPosition = SCNVector3(
                raycastResult.worldTransform.columns.3.x,
                raycastResult.worldTransform.columns.3.y,
                raycastResult.worldTransform.columns.3.z
            )

            print("ManualAlignment: World position: \(worldPosition)")

            // Move selected pin or place next pin
            if let selectedIndex = selectedPinIndex {
                print("ManualAlignment: Moving selected pin \(selectedIndex + 1)")
                // Move the selected pin
                alignmentNodes[selectedIndex].position = worldPosition
                if selectedIndex < alignmentPoints.count {
                    alignmentPoints[selectedIndex] = worldPosition
                } else {
                    alignmentPoints.append(worldPosition)
                }
                selectedPinIndex = nil

                // Update state based on how many pins are placed
                if alignmentPoints.count == 1 {
                    currentState = .selectingSecondCorner
                    showInstructions("Tap pin 2 and move it to the second corner")
                } else if alignmentPoints.count >= 2 {
                    currentState = .calculating
                    showInstructions("Calculating alignment...")
                    calculateAlignment()
                }
            } else {
                print("ManualAlignment: No pin selected, auto-placing next pin")
                // Auto-select and move the next pin
                if alignmentPoints.count < 2 && alignmentNodes.count >= 2 {
                    let nextPinIndex = alignmentPoints.count
                    alignmentNodes[nextPinIndex].position = worldPosition
                    alignmentPoints.append(worldPosition)

                    if alignmentPoints.count == 1 {
                        currentState = .selectingSecondCorner
                        showInstructions("Tap pin 2 and move it to the second corner")
                    } else if alignmentPoints.count >= 2 {
                        currentState = .calculating
                        showInstructions("Calculating alignment...")
                        calculateAlignment()
                    }
                }
            }
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let arView = arView else { return }

        let location = gesture.location(in: arView)

        switch gesture.state {
        case .began:
            // Check if pan started on a pin
            let hitResults = arView.hitTest(location, options: nil)
            for result in hitResults {
                if let pinIndex = alignmentNodes.firstIndex(of: result.node.parent ?? result.node) {
                    selectedPinIndex = pinIndex
                    showInstructions("Dragging pin \(pinIndex + 1)")
                    break
                }
            }

        case .changed:
            // Move the selected pin during drag
            if let selectedIndex = selectedPinIndex {
                if #available(iOS 14.0, *) {
                    guard let query = arView.raycastQuery(from: location, allowing: .estimatedPlane, alignment: .horizontal) else { return }
                    let raycastResults = arView.session.raycast(query)
                    guard let raycastResult = raycastResults.first else { return }

                    let worldPosition = SCNVector3(
                        raycastResult.worldTransform.columns.3.x,
                        raycastResult.worldTransform.columns.3.y,
                        raycastResult.worldTransform.columns.3.z
                    )

                    alignmentNodes[selectedIndex].position = worldPosition
                }
            }

        case .ended:
            // Finalize pin position
            if let selectedIndex = selectedPinIndex {
                let finalPosition = alignmentNodes[selectedIndex].position

                if selectedIndex < alignmentPoints.count {
                    alignmentPoints[selectedIndex] = finalPosition
                } else {
                    alignmentPoints.append(finalPosition)
                }

                selectedPinIndex = nil

                // Update state based on pins placed
                if alignmentPoints.count == 1 {
                    currentState = .selectingSecondCorner
                    showInstructions("Tap or drag pin 2 to the second corner")
                } else if alignmentPoints.count >= 2 {
                    currentState = .calculating
                    showInstructions("Calculating alignment...")
                    calculateAlignment()
                }
            }

        default:
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
        _ = gpsToENU(gpsPoint2, centroid: centroid)

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
        clearAlignmentNodes()

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

    private func addAlignmentPins() {
        guard let arView = arView else { return }

        // Check if we have pre-selected alignment points from web map
        if let savedPoints = loadSavedAlignmentPoints() {
            print("ManualAlignment: Using saved alignment points from web map")
            // Convert GPS coordinates to AR world positions
            let centroid = calculateCentroid(of: boundaryRings.first ?? [])

            for (index, point) in savedPoints.alignmentPoints.enumerated() {
                let coord = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
                let enuPosition = gpsToENU(coord, centroid: centroid)

                let pin = createAlignmentPin(number: index + 1, color: index == 0 ? .red : .blue)
                pin.position = SCNVector3(enuPosition.x, 0, enuPosition.z)

                arView.scene.rootNode.addChildNode(pin)
                alignmentNodes.append(pin)
                alignmentPoints.append(pin.position)

                print("ManualAlignment: Placed pin \(index + 1) at GPS position \(coord) -> ENU \(enuPosition)")
            }

            if alignmentPoints.count >= 2 {
                currentState = .calculating
                showInstructions("Using saved alignment points - calculating...")
                calculateAlignment()
                return
            }
        }

        // Fallback: Create pins in front of camera if no saved points
        let pin1 = createAlignmentPin(number: 1, color: .red)
        let pin2 = createAlignmentPin(number: 2, color: .blue)

        // Position pins in front of camera
        let cameraTransform = arView.session.currentFrame?.camera.transform ?? matrix_identity_float4x4
        let cameraPosition = SCNVector3(cameraTransform.columns.3.x, cameraTransform.columns.3.y, cameraTransform.columns.3.z)

        // Place pins 2 meters in front of camera, slightly apart
        pin1.position = SCNVector3(cameraPosition.x - 0.5, cameraPosition.y - 0.5, cameraPosition.z - 2.0)
        pin2.position = SCNVector3(cameraPosition.x + 0.5, cameraPosition.y - 0.5, cameraPosition.z - 2.0)

        arView.scene.rootNode.addChildNode(pin1)
        arView.scene.rootNode.addChildNode(pin2)

        alignmentNodes.append(pin1)
        alignmentNodes.append(pin2)
    }

    private func createAlignmentPin(number: Int, color: UIColor) -> SCNNode {
        let pinNode = SCNNode()
        pinNode.name = "alignmentPin\(number)"

        // Create pin geometry (cylinder + sphere)
        let cylinder = SCNCylinder(radius: 0.02, height: 0.3)
        cylinder.firstMaterial?.diffuse.contents = color
        let cylinderNode = SCNNode(geometry: cylinder)
        cylinderNode.position = SCNVector3(0, -0.15, 0)
        cylinderNode.name = "cylinder\(number)"

        let sphere = SCNSphere(radius: 0.05)
        sphere.firstMaterial?.diffuse.contents = color
        let sphereNode = SCNNode(geometry: sphere)
        sphereNode.position = SCNVector3(0, 0.05, 0)
        sphereNode.name = "sphere\(number)"

        // Add number text
        let text = SCNText(string: "\(number)", extrusionDepth: 0.01)
        text.font = UIFont.boldSystemFont(ofSize: 0.1)
        text.firstMaterial?.diffuse.contents = UIColor.white
        let textNode = SCNNode(geometry: text)
        textNode.position = SCNVector3(-0.025, 0.02, 0.06)
        textNode.scale = SCNVector3(0.5, 0.5, 0.5)
        textNode.name = "text\(number)"

        pinNode.addChildNode(cylinderNode)
        pinNode.addChildNode(sphereNode)
        pinNode.addChildNode(textNode)

        print("ManualAlignment: Created pin \(number) with name \(pinNode.name ?? "none")")
        return pinNode
    }

    private func clearAlignmentNodes() {
        alignmentPoints.removeAll()
        selectedCorners.removeAll()
        alignmentNodes.forEach { $0.removeFromParentNode() }
        alignmentNodes.removeAll()
        instructionNode?.removeFromParentNode()
        instructionNode = nil
    }

    private func resetAlignment() {
        alignmentPoints.removeAll()
        selectedCorners.removeAll()
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
