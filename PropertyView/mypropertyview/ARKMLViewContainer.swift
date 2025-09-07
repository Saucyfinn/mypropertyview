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

    func updateUIView(_ v: ARSCNView, context: Context) {
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
                    in v: ARSCNView,
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
            guard let first = kmlRings.first, first.count >= 2 else {
                if parent.status != "Load rings to display" { parent.status = "Load rings to display" }
                root.childNodes.forEach { $0.removeFromParentNode() }
                lastHash = nil
                return
            }

            // Legacy code - now handled by PositioningManager
            // This method is kept for compatibility but positioning is handled elsewhere
            return
        }

        /// Render boundaries using ARGeoAnchor for precise GPS positioning
        @available(iOS 14.0, *)
        private func renderWithGeoAnchors(kmlRings: [[CLLocationCoordinate2D]], user: CLLocation, in v: ARSCNView) {
            // Clear existing anchors and nodes
            v.session.getCurrentWorldMap { _, _ in
                // Remove existing geo anchors
                for anchor in v.session.currentFrame?.anchors ?? [] {
                    if anchor is ARGeoAnchor {
                        v.session.remove(anchor: anchor)
                    }
                }
            }
            root.childNodes.forEach { $0.removeFromParentNode() }

            // Create geo anchors for each boundary point
            for (ringIndex, ring) in kmlRings.enumerated() {
                guard ring.count >= 2 else { continue }

                // Create anchor at first coordinate of the ring
                let firstCoord = ring[0]
                let geoAnchor = ARGeoAnchor(coordinate: firstCoord)
                v.session.add(anchor: geoAnchor)

                // Build polyline relative to the geo anchor
                var pts: [SCNVector3] = []
                for coord in ring {
                    let enu = Geo.enuDelta(from: CLLocation(latitude: firstCoord.latitude, longitude: firstCoord.longitude), to: coord)
                    let x = Float(enu.x)
                    let z = Float(-enu.y)
                    pts.append(SCNVector3(x, 0, z))
                }

                if let polylineNode = buildPolyline(from: pts, color: .systemBlue, tubeRadius: 0.03, dotRadius: 0.04) {
                    // Store the node to be added when anchor is tracked
                    polylineNode.name = "boundary_ring_\(ringIndex)"
                    geoAnchorNodes[geoAnchor.identifier] = polylineNode
                }
            }

            parent.status = "GPS-anchored \(kmlRings.count) ring(s)"
        }

        private var geoAnchorNodes: [UUID: SCNNode] = [:]

        private func placeOnGround(_ node: SCNNode, in v: ARSCNView) {
            let y: Float
            if let g = groundY { y = g + 0.02 } else if let camY = v.pointOfView?.worldPosition.y { y = camY - 1.5 } else { y = 0 }
            node.position.y = y
        }

        private func buildPolyline(from pts: [SCNVector3],
                                   color: UIColor,
                                   tubeRadius: CGFloat,
                                   dotRadius: CGFloat) -> SCNNode? {
            guard pts.count >= 2 else { return nil }
            let group = SCNNode()
            // edges
            for i in 0..<pts.count {
                let a = pts[i]
                let b = pts[(i + 1) % pts.count]
                let seg = cylinderNode(from: a, to: b, radius: tubeRadius, color: color)
                seg.name = "polyline_segment"
                group.addChildNode(seg)
            }
            // corner dots
            for p in pts {
                let dot = sphereNode(at: p, radius: dotRadius, color: color)
                dot.name = "polyline_dot"
                group.addChildNode(dot)
            }
            return group
        }

        private func ringCentroid(of ring: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D? {
            guard !ring.isEmpty else { return nil }
            var sLat = 0.0, sLon = 0.0
            for c in ring { sLat += c.latitude; sLon += c.longitude }
            return .init(latitude: sLat / Double(ring.count), longitude: sLon / Double(ring.count))
        }

        private func cylinderNode(from a: SCNVector3, to b: SCNVector3, radius: CGFloat, color: UIColor) -> SCNNode {
            let v = SCNVector3(b.x - a.x, b.y - a.y, b.z - a.z)
            let len = sqrt(v.x*v.x + v.y*v.y + v.z*v.z)
            if len < 0.001 { return SCNNode() }
            let cyl = SCNCylinder(radius: radius, height: CGFloat(len))
            cyl.radialSegmentCount = 12
            let m = SCNMaterial()
            m.diffuse.contents = color
            m.emission.contents = color
            cyl.materials = [m]
            let node = SCNNode(geometry: cyl)
            node.position = SCNVector3((a.x + b.x)/2, (a.y + b.y)/2, (a.z + b.z)/2)

            let up = SCNVector3(0, 1, 0)
            let dir = SCNVector3(v.x/len, v.y/len, v.z/len)
            let axis = up.cross(dir)
            let axisLen = sqrt(axis.x*axis.x + axis.y*axis.y + axis.z*axis.z)
            if axisLen > 1e-6 {
                let dot = max(min(up.dot(dir), 1), -1)
                let angle = acosf(dot)
                node.rotation = SCNVector4(axis.x/axisLen, axis.y/axisLen, axis.z/axisLen, angle)
            } else if up.dot(dir) < 0 {
                node.rotation = SCNVector4(1, 0, 0, Float.pi)
            }
            return node
        }

        private func sphereNode(at p: SCNVector3, radius: CGFloat, color: UIColor) -> SCNNode {
            let s = SCNSphere(radius: radius)
            let m = SCNMaterial()
            m.diffuse.contents = color
            m.emission.contents = color
            s.materials = [m]
            let n = SCNNode(geometry: s)
            n.position = p
            return n
        }
    }
}

// MARK: - Tiny helpers
private extension SCNVector3 {
    func dot(_ o: SCNVector3) -> Float { x*o.x + y*o.y + z*o.z }
    func cross(_ o: SCNVector3) -> SCNVector3 { SCNVector3(y*o.z - z*o.y, z*o.x - x*o.z, x*o.y - y*o.x) }
}
