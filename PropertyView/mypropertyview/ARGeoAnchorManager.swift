import Foundation
import ARKit
import CoreLocation
import SceneKit

@available(iOS 14.0, *)
class ARGeoAnchorManager: NSObject, ARSessionDelegate {
    private weak var arView: ARSCNView?
    private var geoAnchors: [UUID: ARGeoAnchor] = [:]
    private var anchorNodes: [UUID: SCNNode] = [:]
    private var onStatusUpdate: ((String) -> Void)?

    init(arView: ARSCNView, onStatusUpdate: @escaping (String) -> Void) {
        self.arView = arView
        self.onStatusUpdate = onStatusUpdate
        super.init()
        arView.session.delegate = self
    }

    func addBoundaryRings(_ rings: [[CLLocationCoordinate2D]]) {
        clearExistingAnchors()

        guard ARGeoTrackingConfiguration.isSupported else {
            onStatusUpdate?("GPS tracking not supported on this device")
            return
        }

        // Configure geo tracking with better settings
        let config = ARGeoTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.automaticImageScaleEstimationEnabled = true
        arView?.session.run(config, options: [.resetTracking, .removeExistingAnchors])

        // Create a single geo anchor at the property centroid
        for (ringIndex, ring) in rings.enumerated() {
            guard ring.count >= 2 else { continue }

            // Calculate ring centroid for better anchor placement
            let centroid = calculateCentroid(of: ring)
            let geoAnchor = ARGeoAnchor(coordinate: centroid, altitude: nil)

            // Create boundary geometry using actual LINZ coordinates
            let boundaryNode = createBoundaryNodeWithAbsoluteCoordinates(for: ring, centroid: centroid)
            boundaryNode.name = "boundary_\(ringIndex)"

            // Store for when anchor is tracked
            geoAnchors[geoAnchor.identifier] = geoAnchor
            anchorNodes[geoAnchor.identifier] = boundaryNode

            arView?.session.add(anchor: geoAnchor)

            print("Created GPS anchor at: \(centroid.latitude), \(centroid.longitude)")
            print("Ring coordinates: \(ring.map { "(\($0.latitude), \($0.longitude))" }.joined(separator: ", "))")
        }

        onStatusUpdate?("GPS anchors created for \(rings.count) boundaries")
    }

    private func createBoundaryNodeWithAbsoluteCoordinates(for ring: [CLLocationCoordinate2D], centroid: CLLocationCoordinate2D) -> SCNNode {
        let groupNode = SCNNode()

        // Use the new ENU conversion utility
        var points: [SCNVector3] = []
        for coord in ring {
            let enuPosition = Geo.enu(from: centroid, to: coord)
            points.append(SCNVector3(enuPosition.x, enuPosition.y, enuPosition.z))

            print("Coordinate \(coord.latitude), \(coord.longitude) -> ENU position (\(enuPosition.x), \(enuPosition.y), \(enuPosition.z))")
        }

        // Create line segments with better visibility
        for i in 0..<points.count {
            let start = points[i]
            let end = points[(i + 1) % points.count]

            let lineNode = createLineNode(from: start, to: end)
            groupNode.addChildNode(lineNode)
        }

        return groupNode
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

    private func createLineNode(from start: SCNVector3, to end: SCNVector3) -> SCNNode {
        let vector = SCNVector3(end.x - start.x, end.y - start.y, end.z - start.z)
        let distance = sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)

        let cylinder = SCNCylinder(radius: 0.02, height: CGFloat(distance))
        cylinder.firstMaterial?.diffuse.contents = UIColor.systemBlue
        cylinder.firstMaterial?.emission.contents = UIColor.systemBlue

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
            let angle = acos(max(-1, min(1, up.x * direction.x + up.y * direction.y + up.z * direction.z)))
            lineNode.rotation = SCNVector4(cross.x / crossLength, cross.y / crossLength, cross.z / crossLength, angle)
        }

        return lineNode
    }

    private func clearExistingAnchors() {
        for anchor in arView?.session.currentFrame?.anchors ?? [] {
            if let geoAnchor = anchor as? ARGeoAnchor {
                arView?.session.remove(anchor: geoAnchor)
            }
        }
        geoAnchors.removeAll()
        anchorNodes.removeAll()
    }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            if let geoAnchor = anchor as? ARGeoAnchor,
               let boundaryNode = anchorNodes[geoAnchor.identifier] {

                print("GPS anchor added at: \(geoAnchor.coordinate.latitude), \(geoAnchor.coordinate.longitude)")
                print("Anchor transform: \(geoAnchor.transform)")

                DispatchQueue.main.async {
                    // Remove any existing boundary nodes to prevent duplicates
                    self.arView?.scene.rootNode.childNodes.forEach { node in
                        if node.name?.starts(with: "gps_boundary") == true {
                            node.removeFromParentNode()
                        }
                    }

                    // Create anchor node with GPS transform
                    let anchorNode = SCNNode()
                    anchorNode.name = "gps_boundary_\(geoAnchor.identifier)"
                    anchorNode.simdTransform = geoAnchor.transform

                    // Position boundary node at ground level
                    boundaryNode.position = SCNVector3(0, 0, 0)
                    anchorNode.addChildNode(boundaryNode)

                    self.arView?.scene.rootNode.addChildNode(anchorNode)
                    self.onStatusUpdate?("GPS boundary anchored at \(geoAnchor.coordinate.latitude), \(geoAnchor.coordinate.longitude)")

                    print("Boundary node added to scene at GPS coordinates")
                }
            }
        }
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors {
            if let geoAnchor = anchor as? ARGeoAnchor {
                // Find and update the corresponding boundary node
                DispatchQueue.main.async {
                    if let anchorNode = self.arView?.scene.rootNode.childNode(withName: "gps_boundary_\(geoAnchor.identifier)", recursively: false) {
                        anchorNode.simdTransform = geoAnchor.transform
                    }
                }
            }
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        onStatusUpdate?("AR session failed: \(error.localizedDescription)")
    }

    func sessionWasInterrupted(_ session: ARSession) {
        onStatusUpdate?("AR session interrupted")
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        onStatusUpdate?("AR session resumed")
    }
}
