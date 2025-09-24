import Foundation
import ARKit
import CoreLocation
import SceneKit

@available(iOS 14.0, *)
class ARGeoAnchorManager: NSObject, ARSessionDelegate, ARSCNViewDelegate {
    private weak var arView: ARSCNView?
    private var geoAnchors: [UUID: ARGeoAnchor] = [:]
    private var anchorNodes: [UUID: SCNNode] = [:]
    private var onStatusUpdate: ((String) -> Void)?

    init(arView: ARSCNView, onStatusUpdate: @escaping (String) -> Void) {
        self.arView = arView
        self.onStatusUpdate = onStatusUpdate
        super.init()
        arView.session.delegate = self
        arView.delegate = self
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

    private func createBoundaryNodeWithAbsoluteCoordinates(for ring: [CLLocationCoordinate2D], centroid: CLLocationCoordinate2D) -> SCNNode { // swiftlint:disable:this line_length
        let groupNode = SCNNode()

        // Use simple relative positioning
        var points: [SCNVector3] = []
        for coord in ring {
            let relativePosition = simpleRelativePosition(from: centroid, to: coord)
            points.append(SCNVector3(relativePosition.x, 0, relativePosition.y))

            print("Coordinate \(coord.latitude), \(coord.longitude) -> relative position (\(relativePosition.x), 0, \(relativePosition.y))")
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
    
    private func simpleRelativePosition(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) -> (x: Float, y: Float) {
        // Simple conversion: 1 degree ≈ 111,000 meters
        let latDiff = destination.latitude - origin.latitude
        let lonDiff = destination.longitude - origin.longitude
        
        let x = Float(lonDiff * 111000) // Longitude difference to meters (east-west)
        let y = Float(latDiff * 111000) // Latitude difference to meters (north-south)
        
        return (x, y)
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

        guard distance > 0.001 else {
            // Return empty node for zero-length lines
            return SCNNode()
        }

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
            let axis = SCNVector3(cross.x / crossLength, cross.y / crossLength, cross.z / crossLength)
            let angle = acos(min(1.0, max(-1.0, simd_dot(simd_make_float3(up), simd_make_float3(direction)))))
            lineNode.rotation = SCNVector4(axis.x, axis.y, axis.z, angle)
        }

        return lineNode
    }

    private func clearExistingAnchors() {
        for (identifier, _) in geoAnchors {
            if let anchor = arView?.session.currentFrame?.anchors.first(where: { $0.identifier == identifier }) {
                arView?.session.remove(anchor: anchor)
            }
        }
        geoAnchors.removeAll()
        anchorNodes.removeAll()
    }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            if let geoAnchor = anchor as? ARGeoAnchor,
               let node = anchorNodes[geoAnchor.identifier] {
                DispatchQueue.main.async {
                    self.arView?.scene.rootNode.addChildNode(node)
                    print("Added boundary node for geo anchor")
                }
            }
        }
    }
    
    // MARK: - ARSCNViewDelegate
    
    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        guard let geoAnchor = anchor as? ARGeoAnchor,
              let node = anchorNodes[geoAnchor.identifier] else {
            return nil
        }
        
        print("Renderer providing node for geo anchor")
        return node
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard anchor is ARGeoAnchor else { return }
        print("Renderer added node for geo anchor")
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        // Handle anchor updates if needed
    }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        for anchor in anchors {
            if let geoAnchor = anchor as? ARGeoAnchor,
               let node = anchorNodes[geoAnchor.identifier] {
                DispatchQueue.main.async {
                    node.removeFromParentNode()
                }
            }
        }
    }
}