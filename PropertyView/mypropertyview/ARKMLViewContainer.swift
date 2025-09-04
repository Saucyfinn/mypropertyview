import SwiftUI
import ARKit
import SceneKit
import CoreLocation
import UIKit

/// Renders ONLY the provided rings (typically from LINZ WFS) in AR, in blue.
/// Coordinates are placed in meters relative to the USER'S CURRENT LOCATION,
/// so the geometry sits in its true position around you.
struct ARKMLViewContainer: UIViewRepresentable {
    // Kept for signature compatibility with callers; these are unused here.
    @Binding var rings: [[CLLocationCoordinate2D]]

    // Your current device location (must be set by ARTab / ARBootstrap)
    @Binding var origin: CLLocation?
    @Binding var status: String

    // Unused toggles (kept to avoid churn in call sites)
    @Binding var showNeighbours: Bool
    @Binding var showCorners: Bool
    @Binding var guidanceActive: Bool
    @Binding var yawDegrees: Double
    @Binding var offsetE: Double
    @Binding var offsetN: Double
    @Binding var setAID: Int
    @Binding var setBID: Int
    @Binding var solveID: Int

    // These are the only rings we actually render (blue)
    @Binding var kmlRings: [[CLLocationCoordinate2D]]
    @Binding var showKML: Bool
    @Binding var useKMLAsSubject: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> ARSCNView {
        let v = ARSCNView(frame: .zero)
        v.automaticallyUpdatesLighting = true
        v.delegate = context.coordinator
        v.session.delegate = context.coordinator
        v.scene = SCNScene()

        let cfg = ARWorldTrackingConfiguration()
        // ✅ Align world yaw to compass (so +E → +X, +N → -Z)
        cfg.worldAlignment = .gravityAndHeading
        cfg.planeDetection = [.horizontal]
        v.session.run(cfg, options: [.resetTracking, .removeExistingAnchors])

        context.coordinator.attach(to: v)
        return v
    }

    func updateUIView(_ v: ARSCNView, context: Context) {
        // We don’t apply manual pose; geometry is placed absolutely around the user.
        context.coordinator.render(kmlRings: kmlRings, user: origin, in: v, show: showKML)
    }

    // MARK: - Coordinator
    final class Coordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate {
        let parent: ARKMLViewContainer
        private weak var view: ARSCNView?
        private let root = SCNNode()
        private var groundY: Float?
        private var lastHash: Int?

        init(_ parent: ARKMLViewContainer) { self.parent = parent }

        func attach(to v: ARSCNView) {
            self.view = v
            v.scene.rootNode.addChildNode(root)
        }

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            // Detect ground plane once, place geometry ~2cm above it
            guard let v = view, groundY == nil else { return }
            let center = CGPoint(x: v.bounds.midX, y: v.bounds.midY)
            if let q = v.raycastQuery(from: center, allowing: .estimatedPlane, alignment: .horizontal),
               let first = v.session.raycast(q).first {
                groundY = first.worldTransform.columns.3.y
                DispatchQueue.main.async {
                    for n in self.root.childNodes { n.position.y = self.groundY! + 0.02 }
                }
            }
        }

        /// Build & place rings relative to the USER (not the parcel centroid).
        func render(kmlRings: [[CLLocationCoordinate2D]],
                    user: CLLocation?,
                    in v: ARSCNView,
                    show: Bool)
        {
            guard show else {
                if parent.status != "Hidden" { parent.status = "Hidden" }
                root.childNodes.forEach { $0.removeFromParentNode() }
                lastHash = nil
                return
            }
            guard let user = user else {
                if parent.status != "Waiting for GPS…" { parent.status = "Waiting for GPS…" }
                return
            }
            guard let first = kmlRings.first, first.count >= 3 else {
                if parent.status != "Load rings to display" { parent.status = "Load rings to display" }
                root.childNodes.forEach { $0.removeFromParentNode() }
                lastHash = nil
                return
            }

            // Rebuild key: rings content + coarse user position (so we redraw as you move)
            var hasher = Hasher()
            hasher.combine(kmlRings.count)
            for r in kmlRings.prefix(6) {
                hasher.combine(r.count)
                if let c = ringCentroid(of: r) {
                    hasher.combine(Int(c.latitude * 1e6))
                    hasher.combine(Int(c.longitude * 1e6))
                }
            }
            // include user position to ~0.5 m
            hasher.combine(Int(user.coordinate.latitude * 1e5))
            hasher.combine(Int(user.coordinate.longitude * 1e5))
            let key = hasher.finalize()
            if key == lastHash { return }
            lastHash = key

            // Clear old geometry
            root.childNodes.forEach { $0.removeFromParentNode() }

            // ✅ Convert every vertex from USER → vertex in ENU meters
            //    (+E → +X, +N → -Z, Y = ground)
            for ring in kmlRings {
                guard ring.count >= 2 else { continue }
                var pts: [SCNVector3] = []
                pts.reserveCapacity(ring.count)
                for c in ring {
                    let enu = Geo.enuDelta(from: user, to: c)
                    let x = Float(enu.x)      // meters east of user
                    let z = Float(-enu.y)     // meters north of user → -Z
                    pts.append(SCNVector3(x, 0, z))
                }
                if let node = buildPolyline(from: pts, color: .systemBlue, tubeRadius: 0.03, dotRadius: 0.04) {
                    placeOnGround(node, in: v)
                    root.addChildNode(node)
                }
            }

            parent.status = "Displayed \(kmlRings.count) ring(s)"
        }

        private func placeOnGround(_ node: SCNNode, in v: ARSCNView) {
            let y: Float
            if let g = groundY { y = g + 0.02 }
            else if let camY = v.pointOfView?.worldPosition.y { y = camY - 1.5 }
            else { y = 0 }
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
                group.addChildNode(seg)
            }
            // corner dots
            for p in pts {
                let dot = sphereNode(at: p, radius: dotRadius, color: color)
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
