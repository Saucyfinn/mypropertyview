import SwiftUI
import UIKit
import ARKit
import SceneKit
import CoreLocation
import simd

// MARK: - SwiftUI wrapper used by ARTab
public struct ParcelsARView: UIViewControllerRepresentable {
    public typealias UIViewControllerType = ParcelARViewManager

    public var radiusMeters: Double
    public init(radiusMeters: Double = 120) { self.radiusMeters = radiusMeters }

    public func makeUIViewController(context: Context) -> ParcelARViewManager {
        ParcelARViewManager(radiusMeters: radiusMeters)
    }

    public func updateUIViewController(_ uiVC: ParcelARViewManager, context: Context) {
        uiVC.radiusMeters = radiusMeters
        uiVC.refetchIfNeeded()
    }
}

// MARK: - Main AR Controller
public final class ParcelARViewManager: UIViewController, ARSCNViewDelegate, CLLocationManagerDelegate {

    // Config
    public var radiusMeters: Double
    private let wantsDebugInfo = false

    // Views
    private let sceneView = ARSCNView(frame: .zero)
    private lazy var earthButton: UIButton = {
        let b = UIButton(type: .system)
        var cfg = UIButton.Configuration.filled()
        cfg.baseBackgroundColor = UIColor.systemBlue.withAlphaComponent(0.85)
        cfg.baseForegroundColor = .white
        cfg.image = UIImage(systemName: "globe.americas.fill")
        cfg.title = " Google Earth"
        cfg.imagePadding = 6
        cfg.cornerStyle = .capsule
        b.configuration = cfg
        b.addTarget(self, action: #selector(onExportTap), for: .touchUpInside)
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    // Location
    private let locMgr = CLLocationManager()
    private var deviceCoord: CLLocationCoordinate2D?
    private var sessionRefCoord: CLLocationCoordinate2D?  // frozen at AR session start (ENU origin)

    // Data
    private var subjectRings: [[CLLocationCoordinate2D]]?               // parcel user is inside
    private var neighbourPolygons: [[[CLLocationCoordinate2D]]] = []    // other polygons (all rings)
    private var didFetchFor: CLLocationCoordinate2D?                    // last fetch center

    // Nodes
    private var parcelsGroupNode: SCNNode?
    private var subjectNode: SCNNode?
    private var neighbourNodes: [SCNNode] = []

    // Ground snap
    private var latestGroundY: Float?
    private var needsSnapAfterPlane = false

    // Session start guard
    private var hasRunSessionOnce = false

    // Lifecycle
    public init(radiusMeters: Double = 120) {
        self.radiusMeters = radiusMeters
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func viewDidLoad() {
        super.viewDidLoad()

        // Scene view
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
        if wantsDebugInfo {
            sceneView.debugOptions = [.showFeaturePoints, .showWorldOrigin]
        }

        // Overlay: Google Earth export button
        view.addSubview(earthButton)
        NSLayoutConstraint.activate([
            earthButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            earthButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12)
        ])

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

    // MARK: - Public: update radius toggle
    public func refetchIfNeeded() {
        guard let here = deviceCoord else { return }
        fetchParcels(around: here)
    }

    // MARK: - Location Delegate
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let c = locations.last?.coordinate else { return }
        deviceCoord = c

        // Start AR once, with the first coordinate we get
        if !hasRunSessionOnce {
            hasRunSessionOnce = true
            startARSession(at: c)
        }

        // Fetch parcels for this coordinate (subject + neighbours)
        fetchParcels(around: c)
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error:", error.localizedDescription)
        if !hasRunSessionOnce {
            hasRunSessionOnce = true
            startARSession(at: nil)
        }
    }

    // MARK: - Start AR
    private func startARSession(at coord: CLLocationCoordinate2D?) {
        if let c = coord { sessionRefCoord = c }

        if #available(iOS 14.0, *),
           let c = coord,
           ARGeoTrackingConfiguration.isSupported {
            ARGeoTrackingConfiguration.checkAvailability(at: c) { [weak self] available, _ in
                DispatchQueue.main.async { self?.runConfig(geo: available) }
            }
        } else {
            runConfig(geo: false)
        }
    }

    private func runConfig(geo: Bool) {
        if geo, #available(iOS 14.0, *) {
            let cfg = ARGeoTrackingConfiguration()
            cfg.environmentTexturing = .automatic
            sceneView.session.run(cfg, options: [.resetTracking, .removeExistingAnchors])
        } else {
            let cfg = ARWorldTrackingConfiguration()
            cfg.worldAlignment = .gravityAndHeading
            cfg.planeDetection = [.horizontal]   // detect floors/ground
            cfg.environmentTexturing = .automatic
            sceneView.session.run(cfg, options: [.resetTracking, .removeExistingAnchors])
        }
    }

    // MARK: - Fetch LINZ (WFS)
    private func fetchParcels(around center: CLLocationCoordinate2D) {
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "LINZ_API_KEY") as? String,
              !apiKey.isEmpty else {
            print("⚠️ LINZ_API_KEY missing from Info.plist")
            return
        }

        // Throttle: only refetch if we moved > 10 m
        if let prev = didFetchFor {
            let d = distanceMeters(from: prev, to: center)
            if d < 10 { return }
        }
        didFetchFor = center

        let bb = bboxAround(lat: center.latitude, lon: center.longitude, meters: radiusMeters)
        var comps = URLComponents(string: "https://data.linz.govt.nz/services;key=\(apiKey)/wfs")!
        comps.queryItems = [
            .init(name: "service", value: "WFS"),
            .init(name: "version", value: "2.0.0"),
            .init(name: "request", value: "GetFeature"),
            .init(name: "typeNames", value: "layer-50823"),
            .init(name: "srsName", value: "CRS:84"),
            .init(name: "outputFormat", value: "application/json"),
            .init(name: "bbox", value: "\(bb.w),\(bb.s),\(bb.e),\(bb.n),CRS:84")
        ]
        guard let url = comps.url else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, resp, err in
            guard let self else { return }
            guard err == nil, let data, (resp as? HTTPURLResponse)?.statusCode == 200 else {
                print("WFS error:", err?.localizedDescription ?? "bad response")
                return
            }
            do {
                let fc = try JSONDecoder().decode(FC.self, from: data)

                // MultiPolygon → [[[CLLocationCoordinate2D]]], then flatten to polygons
                let polys: [[[CLLocationCoordinate2D]]] =
                    fc.features
                        .compactMap { $0.geometry.toMultiPolygon() }
                        .flatMap { $0 }

                // Subject = parcel containing the user; fallback to nearest centroid
                let inside: [[CLLocationCoordinate2D]]? = polys.first(where: { rings in
                    guard let outer = rings.first else { return false }
                    return pointInPolygon(point: center, polygon: outer)
                })
                let neighbours = polys.filter { rings in
                    guard let outer = rings.first else { return false }
                    return !pointInPolygon(point: center, polygon: outer)
                }

                DispatchQueue.main.async {
                    self.subjectRings = inside ?? polys.min(by: {
                        distanceMeters(from: center, to: centroid(of: $0.first ?? [])) <
                        distanceMeters(from: center, to: centroid(of: $1.first ?? []))
                    })
                    self.neighbourPolygons = neighbours
                    self.redrawParcelsGroup()
                }
            } catch {
                print("Decode error:", error.localizedDescription)
            }
        }.resume()
    }

    // MARK: - Build / Redraw nodes
    private func redrawParcelsGroup() {
        guard let ref = sessionRefCoord ?? deviceCoord else { return }
        guard let subject = subjectRings else { return }

        // Remove previous
        parcelsGroupNode?.removeFromParentNode()
        neighbourNodes.removeAll()
        subjectNode = nil

        // Build new group
        let group = SCNNode()
        group.name = "parcelsGroup"

        // SUBJECT: extremely translucent fill + clear outline
        let subj = buildPolygonNode(
            rings: subject,
            ref: ref,
            fill: UIColor.systemCyan.withAlphaComponent(0.04), // << very translucent
            outline: UIColor.systemTeal
        )
        group.addChildNode(subj)
        subjectNode = subj

        // NEIGHBOURS
        if radiusMeters > 110 {
            for rings in neighbourPolygons {
                let nn = buildPolygonNode(
                    rings: rings,
                    ref: ref,
                    fill: UIColor.systemGray.withAlphaComponent(0.035),
                    outline: UIColor.systemGray2.withAlphaComponent(0.9)
                )
                group.addChildNode(nn)
                neighbourNodes.append(nn)
            }
        }

        // Add to scene
        sceneView.scene.rootNode.addChildNode(group)
        parcelsGroupNode = group

        // Snap to ground plane if we have one
        if let y = latestGroundY {
            snapGroupToGround(y: y)
        } else {
            needsSnapAfterPlane = true
        }
    }

    // MARK: - Plane handling → snap to ground
    public func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard let plane = anchor as? ARPlaneAnchor else { return }
        let y = plane.transform.columns.3.y
        if latestGroundY == nil || y < latestGroundY! {
            latestGroundY = y
            if needsSnapAfterPlane { snapGroupToGround(y: y) }
        }
    }

    public func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let plane = anchor as? ARPlaneAnchor else { return }
        let y = plane.transform.columns.3.y
        if latestGroundY == nil || y < latestGroundY! {
            latestGroundY = y
            snapGroupToGround(y: y)
        }
    }

    private func snapGroupToGround(y: Float) {
        guard let group = parcelsGroupNode else { return }
        let (minB, _) = group.boundingBox
        let delta = y - minB.y + 0.01 // rest 1cm above plane
        group.position.y += delta
        needsSnapAfterPlane = false
    }

    // MARK: - Export to Google Earth (KML)
    @objc private func onExportTap() {
        guard let subject = subjectRings, let outer = subject.first, !outer.isEmpty else {
            let alert = UIAlertController(title: "No Parcel",
                                          message: "Subject parcel not loaded yet.",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }

        let kml = buildKML(for: subject)
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("parcel.kml")
        do {
            try kml.data(using: .utf8)?.write(to: tmpURL, options: .atomic)
        } catch {
            let alert = UIAlertController(title: "Export Failed",
                                          message: error.localizedDescription,
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }

        // Share sheet; Google Earth will appear if installed
        let av = UIActivityViewController(activityItems: [tmpURL], applicationActivities: nil)
        if let pop = av.popoverPresentationController {
            pop.sourceView = earthButton
            pop.sourceRect = earthButton.bounds
        }
        present(av, animated: true)
    }
}

// MARK: - Geometry Builders
private func buildPolygonNode(rings: [[CLLocationCoordinate2D]],
                              ref: CLLocationCoordinate2D,
                              fill: UIColor,
                              outline: UIColor) -> SCNNode {
    let path = UIBezierPath()
    path.usesEvenOddFillRule = true

    // Outer + holes (even-odd)
    for ring in rings {
        guard let first = ring.first else { continue }
        let p0 = enuFrom(lat: first.latitude, lon: first.longitude, refLat: ref.latitude, refLon: ref.longitude)
        path.move(to: CGPoint(x: CGFloat(p0.x), y: CGFloat(-p0.z))) // -z to map North upward
        for pt in ring.dropFirst() {
            let v = enuFrom(lat: pt.latitude, lon: pt.longitude, refLat: ref.latitude, refLon: ref.longitude)
            path.addLine(to: CGPoint(x: CGFloat(v.x), y: CGFloat(-v.z)))
        }
        path.close()
    }

    // Very shallow extrusion for performance
    let fillShape = SCNShape(path: path, extrusionDepth: 0.008)
    let fillMat = SCNMaterial()
    fillMat.diffuse.contents = fill
    fillMat.emission.contents = fill.withAlphaComponent(0.5)
    fillMat.isDoubleSided = true
    fillShape.firstMaterial = fillMat

    let fillNode = SCNNode(geometry: fillShape)
    fillNode.eulerAngles.x = -.pi / 2 // lay flat

    // Outline (same path, slightly thicker)
    let strokeShape = SCNShape(path: path, extrusionDepth: 0.012)
    let strokeMat = SCNMaterial()
    strokeMat.diffuse.contents = outline
    strokeMat.emission.contents = outline
    strokeMat.isDoubleSided = true
    strokeShape.firstMaterial = strokeMat

    let strokeNode = SCNNode(geometry: strokeShape)
    strokeNode.eulerAngles.x = -.pi / 2
    strokeNode.position.y = 0.003 // 3mm above fill to avoid z-fighting

    let parent = SCNNode()
    parent.addChildNode(fillNode)
    parent.addChildNode(strokeNode)
    return parent
}

// MARK: - Math / Helpers
/// WGS84 -> ENU (East, North, Up) around refLat/refLon
private func enuFrom(lat: Double, lon: Double, refLat: Double, refLon: Double) -> simd_float3 {
    let R = 6_378_137.0
    let dLat = (lat - refLat) * .pi / 180
    let dLon = (lon - refLon) * .pi / 180
    let east  = R * dLon * cos(refLat * .pi / 180)
    let north = R * dLat
    let up    = 0.0
    return simd_float3(Float(east), Float(up), Float(north))
}

private func bboxAround(lat: Double, lon: Double, meters: Double) -> (w: Double, s: Double, e: Double, n: Double) {
    let dLat = meters / 110_540.0
    let dLon = meters / (111_320.0 * cos(lat * .pi / 180))
    return (lon - dLon, lat - dLat, lon + dLon, lat + dLat)
}

private func distanceMeters(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
    let la1 = a.latitude  * .pi / 180
    let la2 = b.latitude  * .pi / 180
    let dLa = (b.latitude - a.latitude) * .pi / 180
    let dLo = (b.longitude - a.longitude) * .pi / 180
    let s = sin(dLa/2)*sin(dLa/2) + cos(la1)*cos(la2)*sin(dLo/2)*sin(dLo/2)
    return 2 * 6_371_000 * asin(min(1, sqrt(s)))
}

private func centroid(of ring: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D {
    guard !ring.isEmpty else { return .init(latitude: 0, longitude: 0) }
    let sum = ring.reduce((lat: 0.0, lon: 0.0)) { acc, c in (acc.lat + c.latitude, acc.lon + c.longitude) }
    let n = Double(ring.count)
    return .init(latitude: sum.lat / n, longitude: sum.lon / n)
}

private func pointInPolygon(point: CLLocationCoordinate2D, polygon: [CLLocationCoordinate2D]) -> Bool {
    guard polygon.count >= 3 else { return false }
    var inside = false
    var j = polygon.count - 1
    for i in 0..<polygon.count {
        let xi = polygon[i].longitude, yi = polygon[i].latitude
        let xj = polygon[j].longitude, yj = polygon[j].latitude
        let intersect = ((yi > point.latitude) != (yj > point.latitude)) &&
        (point.longitude < (xj - xi) * (point.latitude - yi) / (yj - yi + 1e-12) + xi)
        if intersect { inside.toggle() }
        j = i
    }
    return inside
}

// MARK: - LINZ GeoJSON (WFS) Models
private struct FC: Decodable { let features: [Feat] }
private struct Feat: Decodable { let geometry: Geom }
private struct Geom: Decodable {
    let type: String
    let coordinates: [[[[Double]]]]? // MultiPolygon [poly][ring][ [lon,lat] ]
}

private extension Geom {
    /// MultiPolygon → [polygon][ring][coord]
    func toMultiPolygon() -> [[[CLLocationCoordinate2D]]]? {
        guard type == "MultiPolygon", let mp = coordinates else { return nil }
        return mp.map { polygon in
            polygon.map { ring in
                ring.compactMap { pair in
                    guard pair.count >= 2 else { return nil }
                    return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
                }
            }
        }
    }
}

// MARK: - KML Builder
private func buildKML(for rings: [[CLLocationCoordinate2D]]) -> String {
    func coordString(_ ring: [CLLocationCoordinate2D]) -> String {
        ring.map { "\($0.longitude),\($0.latitude),0" }.joined(separator: " ")
    }

    var inner = ""
    if rings.count > 1 {
        for r in rings.dropFirst() {
            inner += """
            <innerBoundaryIs>
              <LinearRing>
                <coordinates>\(coordString(r))</coordinates>
              </LinearRing>
            </innerBoundaryIs>

            """
        }
    }

    let outerCoords = coordString(rings.first ?? [])
    return """
    <?xml version="1.0" encoding="UTF-8"?>
    <kml xmlns="http://www.opengis.net/kml/2.2">
      <Document>
        <name>Subject Parcel</name>
        <Placemark>
          <name>Parcel</name>
          <Style>
            <LineStyle><color>ff009999</color><width>2</width></LineStyle>
            <PolyStyle><color>3300ffff</color></PolyStyle>
          </Style>
          <Polygon>
            <outerBoundaryIs>
              <LinearRing>
                <coordinates>\(outerCoords)</coordinates>
              </LinearRing>
            </outerBoundaryIs>
            \(inner)
          </Polygon>
        </Placemark>
      </Document>
    </kml>
    """
}
