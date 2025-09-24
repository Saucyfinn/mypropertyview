import SwiftUI
import ARKit
import SceneKit
import CoreLocation

// MARK: - SwiftUI wrapper (use this in .sheet / NavigationLink)
public struct ParcelARView: UIViewControllerRepresentable {
    public var radiusMeters: Double = 300
    public init(radiusMeters: Double = 300) { self.radiusMeters = radiusMeters }

    public func makeUIViewController(context: Context) -> ParcelARViewManager {
        ParcelARViewManager(radiusMeters: radiusMeters)
    }
    public func updateUIViewController(_ uiViewController: ParcelARViewManager, context: Context) {}
}

// MARK: - Main AR controller
public final class ParcelARViewManager: UIViewController, ARSCNViewDelegate, CLLocationManagerDelegate {

    // Public knobs (tweak if you like)
    public var radiusMeters: Double = 300

    // Internals
    private let sceneView = ARSCNView(frame: .zero)
    private let locMgr = CLLocationManager()
    private var originCoord: CLLocationCoordinate2D?
    private var pendingRings: [[[CLLocationCoordinate2D]]] = []   // MultiPolygon → [rings → coords]
    private let geoAnchorID = UUID().uuidString

    // MARK: init
    public init(radiusMeters: Double = 300) {
        self.radiusMeters = radiusMeters
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: lifecycle
    public override func viewDidLoad() {
        super.viewDidLoad()

        // AR view
        view.addSubview(sceneView)
        sceneView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            sceneView.topAnchor.constraint(equalTo: view.topAnchor),
            sceneView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sceneView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sceneView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        sceneView.delegate = self
        sceneView.automaticallyUpdatesLighting = true
        sceneView.scene = SCNScene()

        // Location
        locMgr.delegate = self
        locMgr.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locMgr.requestWhenInUseAuthorization()
        locMgr.requestLocation()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }

    // MARK: - Location
    public func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        guard let loc = locs.last else { return }
        if originCoord == nil { originCoord = loc.coordinate }

        // Check geo-tracking availability for this coordinate
        ARGeoTrackingConfiguration.checkAvailability(at: loc.coordinate) { [weak self] available, _ in
            DispatchQueue.main.async {
                self?.startAR(geo: available)
                self?.loadParcelsAround(loc.coordinate) // fetch & draw boundaries around user
            }
        }
    }

    public func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        // Fallback to world-tracking if we fail to get location first time
        startAR(geo: false)
    }

    // MARK: - Start AR
    private func startAR(geo: Bool) {
        if geo {
            guard ARGeoTrackingConfiguration.isSupported else { startAR(geo: false); return }
            let cfg = ARGeoTrackingConfiguration()
            cfg.planeDetection = []
            sceneView.session.run(cfg, options: [.resetTracking, .removeExistingAnchors])

            // Place a geo anchor near the first parcel’s centroid when we have data.
            // If we already have rings, add immediately.
            if let centroid = pendingRings.first.flatMap({ centroidOfMultiPolygon($0) }) {
                let anchor = ARGeoAnchor(coordinate: centroid)
                anchor.name = geoAnchorID
                sceneView.session.add(anchor: anchor)
            }
        } else {
            let cfg = ARWorldTrackingConfiguration()
            cfg.worldAlignment = .gravityAndHeading   // x = East, y = Up, z = South
            cfg.planeDetection = []
            sceneView.session.run(cfg, options: [.resetTracking, .removeExistingAnchors])
            drawNowWorldAligned()
        }
    }

    // MARK: - Draw (world tracking fallback)
    private func drawNowWorldAligned() {
        guard let origin = originCoord, !pendingRings.isEmpty else { return }
        // Clear previous
        sceneView.scene.rootNode.childNode(withName: "parcels", recursively: false)?.removeFromParentNode()

        let group = SCNNode()
        group.name = "parcels"
        for rings in pendingRings {
            let node = nodeForPolygon(rings: rings, origin: origin, y: -0.03) // 3cm down to avoid z-fighting
            group.addChildNode(node)
        }
        sceneView.scene.rootNode.addChildNode(group)
    }

    // MARK: - Draw (geo anchors)
    public func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard let a = anchor as? ARGeoAnchor, a.name == geoAnchorID else { return }
        guard let centroid = pendingRings.first.flatMap({ centroidOfMultiPolygon($0) }) else { return }

        let group = SCNNode()
        for rings in pendingRings {
            let n = nodeForPolygon(rings: rings, origin: centroid, y: 0)
            group.addChildNode(n)
        }
        node.addChildNode(group)
    }

    // MARK: - LINZ fetch (WFS → rings)
    private func loadParcelsAround(_ coord: CLLocationCoordinate2D) {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "LINZ_API_KEY") as? String, !key.isEmpty else {
            print("LINZ key missing in Info.plist (LINZ_API_KEY)"); return
        }
        let b = bboxAround(lat: coord.latitude, lon: coord.longitude, meters: radiusMeters)
        var comps = URLComponents(string: "https://data.linz.govt.nz/services;key=\(key)/wfs")!
        comps.queryItems = [
            .init(name: "service", value: "WFS"),
            .init(name: "version", value: "2.0.0"),
            .init(name: "request", value: "GetFeature"),
            .init(name: "typeNames", value: "layer-50823"), // NZ Primary Land Parcels
            .init(name: "srsName", value: "CRS:84"),
            .init(name: "outputFormat", value: "application/json"),
            .init(name: "bbox", value: "\(b.w),\(b.s),\(b.e),\(b.n),CRS:84")
        ]
        guard let url = comps.url else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, resp, err in
            guard let self else { return }
            guard err == nil, let data, (resp as? HTTPURLResponse)?.statusCode == 200 else {
                print("WFS error:", err ?? URLError(.badServerResponse)); return
            }
            do {
                let fc = try JSONDecoder().decode(FC.self, from: data)
                let rings: [[[CLLocationCoordinate2D]]] = fc.features.compactMap { $0.geometry.toRings() }
                DispatchQueue.main.async {
                    self.pendingRings = rings
                    if let currentConfig = self.sceneView.session.configuration as? ARWorldTrackingConfiguration {
                        // world-tracking: draw immediately
                        self.drawNowWorldAligned()
                    } else if (self.sceneView.session.configuration as? ARGeoTrackingConfiguration) != nil {
                        // geo-tracking: if no anchor yet, add one at centroid
                        if let centroid = rings.first.flatMap({ centroidOfMultiPolygon($0) }) {
                            let anchor = ARGeoAnchor(coordinate: centroid)
                            anchor.name = self.geoAnchorID
                            self.sceneView.session.add(anchor: anchor)
                        }
                    }
                }
            } catch {
                print("Decode error:", error)
            }
        }.resume()
    }

    // MARK: - Helpers
    private func bboxAround(lat: Double, lon: Double, meters: Double) -> (w: Double, s: Double, e: Double, n: Double) {
        let dLat = meters / 110_540.0
        let dLon = meters / (111_320.0 * cos(lat * .pi / 180))
        return (lon - dLon, lat - dLat, lon + dLon, lat + dLat)
    }

    private func metersOffset(from origin: CLLocationCoordinate2D, to c: CLLocationCoordinate2D) -> SIMD2<Double> {
        let R = 6_378_137.0
        let dLat = (c.latitude - origin.latitude) * .pi / 180
        let dLon = (c.longitude - origin.longitude) * .pi / 180
        let xEast  = dLon * cos(origin.latitude * .pi/180) * R
        let yNorth = dLat * R
        return .init(xEast, yNorth)
    }

    private func nodeForPolygon(rings: [[CLLocationCoordinate2D]],
                                origin: CLLocationCoordinate2D,
                                y: Float) -> SCNNode {
        let path = UIBezierPath()
        for (i, ring) in rings.enumerated() {
            guard let first = ring.first else { continue }
            let p0 = metersOffset(from: origin, to: first)
            path.move(to: CGPoint(x: p0.x, y: p0.y))
            for pt in ring.dropFirst() {
                let v = metersOffset(from: origin, to: pt)
                path.addLine(to: CGPoint(x: v.x, y: v.y))
            }
            path.close()
            if i == 0 { /* outer ring */ } else { /* holes implicit */ }
        }

        let shape = SCNShape(path: path, extrusionDepth: 0.05) // ~5 cm wide line
        shape.firstMaterial = {
            let m = SCNMaterial()
            m.diffuse.contents = UIColor.systemCyan
            m.emission.contents = UIColor.systemCyan.withAlphaComponent(0.7)
            m.isDoubleSided = true
            return m
        }()

        let n = SCNNode(geometry: shape)
        n.eulerAngles.x = -.pi / 2     // lay flat on ground
        n.position.y = y
        return n
    }

    private func centroidOfMultiPolygon(_ mp: [[CLLocationCoordinate2D]]) -> CLLocationCoordinate2D {
        // simple average of outer ring vertices (good enough for anchoring)
        let outer = mp.first ?? []
        let sum = outer.reduce((lat: 0.0, lon: 0.0)) { acc, p in (acc.lat + p.latitude, acc.lon + p.longitude) }
        let n = Double(max(outer.count, 1))
        return CLLocationCoordinate2D(latitude: sum.lat / n, longitude: sum.lon / n)
    }
}

// MARK: - Minimal LINZ GeoJSON models
private struct FC: Decodable { let features: [Feat] }
private struct Feat: Decodable { let geometry: Geom }
private struct Geom: Decodable {
    let type: String
    let coordinates: [[[[Double]]]]? // MultiPolygon
}

private extension Geom {
    func toRings() -> [[ [CLLocationCoordinate2D] ]]? {
        guard type == "MultiPolygon", let mp = coordinates else { return nil }
        // Convert [ [ [ [lon,lat], ... ] (ring), ... ] (polygon) ] to [[ [CLLocationCoordinate2D] ]]
        return mp.map { polygon in
            polygon.map { ring in
                ring.compactMap { pair in
                    guard pair.count >= 2 else { return nil }
                    return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0]) // [lon, lat]
                }
            }
        }
    }
}
