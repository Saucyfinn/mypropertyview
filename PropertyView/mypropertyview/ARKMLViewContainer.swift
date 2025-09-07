import SwiftUI
import ARKit
import SceneKit
import CoreLocation
import UIKit

/// Renders ONLY the provided rings (typically from LINZ WFS) in AR, in blue.
/// Coordinates are placed in meters relative to the USER'S CURRENT LOCATION,
/// so the geometry sits in its true position around you.
struct ARKMLViewContainer: UIViewRepresentable {
    @Binding var kmlRings: [[CLLocationCoordinate2D]]
    @Binding var userLocation: CLLocation?
    @Binding var showRings: Bool
    @Binding var status: String

    func makeUIView(context: Context) -> ARSCNView {
        let arView = ARSCNView()
        arView.delegate = context.coordinator
        arView.session.delegate = context.coordinator

        // Initialize positioning system
        context.coordinator.setupPositioningSystem(arView: arView)

        return arView
    }

    func updateUIView(_ arView: ARSCNView, context: Context) {
        // Update positioning system with new boundary data
        context.coordinator.updateBoundaries(kmlRings, userLocation: userLocation, showRings: showRings)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator
    final class Coordinator: NSObject, ARSCNViewDelegate, SCNSceneRendererDelegate, ARSessionDelegate, PositioningManagerDelegate {
        let parent: ARKMLViewContainer
        private weak var view: ARSCNView?
        private let root = SCNNode()
        private var groundY: Float?
        private var lastHash: Int?

        // Multi-tier positioning system
        private var positioningManager: PositioningManager?

        init(_ parent: ARKMLViewContainer) { self.parent = parent }

        func setupPositioningSystem(arView: ARSCNView) {
            self.view = arView
            arView.scene.rootNode.addChildNode(root)

            positioningManager = PositioningManager(arView: arView)
            positioningManager?.delegate = self
        }

        func updateBoundaries(_ rings: [[CLLocationCoordinate2D]], userLocation: CLLocation?, showRings: Bool) {
            guard showRings, !rings.isEmpty else {
                parent.status = "Hidden"
                return
            }

            print("ARKMLViewContainer: Updating boundaries with \(rings.count) rings")
            print("User location: \(userLocation?.coordinate.latitude ?? 0), \(userLocation?.coordinate.longitude ?? 0)")

            positioningManager?.setBoundaryRings(rings)
        }

        // MARK: - PositioningManagerDelegate

        func positioningManager(_ manager: PositioningManager, didUpdateStatus status: PositioningStatus) {
            DispatchQueue.main.async {
                switch status {
                case .initializing:
                    self.parent.status = "Initializing positioning..."
                case .geoTrackingAvailable:
                    self.parent.status = "GPS tracking available"
                case .manualAlignmentRequired:
                    self.parent.status = "GPS tracking unavailable - Using manual alignment"
                case .positioned:
                    self.parent.status = "Boundaries positioned"
                case .failed(let error):
                    self.parent.status = "Error: \(error)"
                }
            }
        }

        func positioningManager(_ manager: PositioningManager, didUpdateMethod method: PositioningMethod) {
            DispatchQueue.main.async {
                switch method {
                case .geoTracking:
                    print("Using ARKit GeoTracking")
                case .manualAlignment:
                    self.parent.status = "GeoTracking unavailable - Select corners on map first"
                    print("Using manual alignment")
                case .fallback:
                    print("Using fallback positioning")
                }
            }
        }

        func positioningManager(_ manager: PositioningManager, didPositionBoundaries transform: simd_float4x4) {
            // Boundaries are positioned by the positioning system
            print("Boundaries positioned with transform: \(transform)")
        }

        /// Build & place rings using ARGeoAnchor for precise GPS positioning
        func render(kmlRings: [[CLLocationCoordinate2D]],
                    user: CLLocation?,
                    in arView: ARSCNView,
                    show: Bool) {
            guard show else {
                if parent.status != "Hidden" { parent.status = "Hidden" }
                root.childNodes.forEach { $0.removeFromParentNode() }
                lastHash = nil
                return
            }
            guard user != nil else {
                if parent.status != "Waiting for GPS…" { parent.status = "Waiting for GPS…" }
                return
            }
            guard let firstRing = kmlRings.first, firstRing.count >= 2 else {
                if parent.status != "Load rings to display" { parent.status = "Load rings to display" }
                root.childNodes.forEach { $0.removeFromParentNode() }
                lastHash = nil
                return
            }

            // Legacy code - now handled by PositioningManager
            // This method is kept for compatibility but positioning is handled elsewhere
        }

        /// Render boundaries using ARGeoAnchor for precise GPS positioning
        @available(iOS 14.0, *)
        private func renderWithGeoAnchors(kmlRings: [[CLLocationCoordinate2D]], user: CLLocation, in arView: ARSCNView) {
            // Clear existing anchors and nodes
            arView.session.getCurrentWorldMap { _, _ in
                // Remove existing geo anchors (Prefer For-Where / pattern matching)
                let anchors = arView.session.currentFrame?.anchors ?? []
                for case let geoAnchor as ARGeoAnchor in anchors {
                    arView.session.remove(anchor: geoAnchor)
                }
            }
            root.childNodes.forEach { $0.removeFromParentNode() }

            // Create geo anchors for each boundary point
            for (ringIndex, ring) in kmlRings.enumerated() where ring.count >= 2 {
                // Create anchor at first coordinate of the ring
                let firstCoord = ring[0]
                let geoAnchor = ARGeoAnchor(coordinate: firstCoord)
                arView.session.add(anchor: geoAnchor)

                // Build polyline relative to the geo anchor
                var points: [SCNVector3] = []
                for coordinate in ring {
                    let enu = Geo.enuDelta(
                        from: CLLocation(latitude: firstCoord.latitude, longitude: firstCoord.longitude),
                        to: coordinate
                    )
                    let xMeters = Float(enu.x)
                    let zMeters = Float(-enu.y)
                    points.append(SCNVector3(xMeters, 0, zMeters))
                }

                if let polylineNode = buildPolyline(from: points, color: .systemBlue, tubeRadius: 0.03, dotRadius: 0.04) {
                    // Store the node to be added when anchor is tracked
                    polylineNode.name = "boundary_ring_\(ringIndex)"
                    geoAnchorNodes[geoAnchor.identifier] = polylineNode
                }
            }

            parent.status = "GPS-anchored \(kmlRings.count) ring(s)"
        }

        private var geoAnchorNodes: [UUID: SCNNode] = [:]

        private func placeOnGround(_ node: SCNNode, in arView: ARSCNView) {
            let y: Float
            if let ground = groundY {
                y = ground + 0.02
            } else if let cameraY = arView.pointOfView?.worldPosition.y {
                y = cameraY - 1.5
            } else {
                y = 0
            }
            node.position.y = y
        }

        private func buildPolyline(from points: [SCNVector3],
                                   color: UIColor,
                                   tubeRadius: CGFloat,
                                   dotRadius: CGFloat) -> SCNNode? {
            guard points.count >= 2 else { return nil }
            let group = SCNNode()

            // Edges (close the ring by connecting last -> first)
            for index in 0..<points.count {
                let startPoint = points[index]
                let endPoint = points[(index + 1) % points.count]
                let segment = cylinderNode(from: startPoint, to: endPoint, radius: tubeRadius, color: color)
                segment.name = "polyline_segment"
                group.addChildNode(segment)
            }

            // Corner dots
            for position in points {
                let dot = sphereNode(at: position, radius: dotRadius, color: color)
                dot.name = "polyline_dot"
                group.addChildNode(dot)
            }
            return group
        }

        private func ringCentroid(of ring: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D? {
            guard !ring.isEmpty else { return nil }
            var sumLat = 0.0
            var sumLon = 0.0
            for coordinate in ring {
                sumLat += coordinate.latitude
                sumLon += coordinate.longitude
            }
            return .init(latitude: sumLat / Double(ring.count), longitude: sumLon / Double(ring.count))
        }

        private func cylinderNode(from start: SCNVector3, to end: SCNVector3, radius: CGFloat, color: UIColor) -> SCNNode {
            let vector = SCNVector3(end.x - start.x, end.y - start.y, end.z - start.z)
            let length = sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)
            if length < 0.001 { return SCNNode() }

            let cylinder = SCNCylinder(radius: radius, height: CGFloat(length))
            cylinder.radialSegmentCount = 12
            let material = SCNMaterial()
            material.diffuse.contents = color
            material.emission.contents = color
            cylinder.materials = [material]

            let node = SCNNode(geometry: cylinder)
            node.position = SCNVector3((start.x + end.x) / 2, (start.y + end.y) / 2, (start.z + end.z) / 2)

            let up = SCNVector3(0, 1, 0)
            let direction = SCNVector3(vector.x / length, vector.y / length, vector.z / length)
            let axis = up.cross(direction)
            let axisLength = sqrt(axis.x * axis.x + axis.y * axis.y + axis.z * axis.z)

            if axisLength > 1e-6 {
                let clampedDot = max(min(up.dot(direction), 1), -1)
                let angle = acosf(clampedDot)
                node.rotation = SCNVector4(axis.x / axisLength, axis.y / axisLength, axis.z / axisLength, angle)
            } else if up.dot(direction) < 0 {
                node.rotation = SCNVector4(1, 0, 0, Float.pi)
            }
            return node
        }

        private func sphereNode(at position: SCNVector3, radius: CGFloat, color: UIColor) -> SCNNode {
            let sphere = SCNSphere(radius: radius)
            let material = SCNMaterial()
            material.diffuse.contents = color
            material.emission.contents = color
            sphere.materials = [material]
            let node = SCNNode(geometry: sphere)
            node.position = position
            return node
        }
    }
}

// MARK: - Tiny helpers
private extension SCNVector3 {
    func dot(_ other: SCNVector3) -> Float { x * other.x + y * other.y + z * other.z }
    func cross(_ other: SCNVector3) -> SCNVector3 {
        SCNVector3(
            y * other.z - z * other.y,
            z * other.x - x * other.z,
            x * other.y - y * other.x
        )
    }
}
