import SwiftUI
import ARKit
import RealityKit
import CoreLocation
import simd

struct ARTab: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var arManager = ARManager()
    @State private var showingSettings = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            ZStack {
                if ARWorldTrackingConfiguration.isSupported {
                    EnhancedARViewContainer(
                        arManager: arManager,
                        coordinates: appState.currentCoordinates,
                        fallbackMode: appState.positioningStatus == .failed
                    )
                    .ignoresSafeArea()
                    .onAppear {
                        setupARSession()
                    }
                    .onDisappear {
                        arManager.pauseSession()
                    }
                    .onChange(of: appState.currentCoordinates) { newCoordinates in
                        handleCoordinateUpdate(newCoordinates)
                    }
                    
                    // AR Controls Overlay
                    VStack {
                        // Top status bar
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Circle()
                                        .fill(arManager.sessionStatus.color)
                                        .frame(width: 8, height: 8)
                                    Text(arManager.sessionStatus.displayText)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                
                                if let property = appState.subjectProperty {
                                    Text(property.appellation)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(appState.positioningStatus.displayText)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(appState.positioningStatus.color)
                                
                                if arManager.isTrackingGood {
                                    Text("Tracking: Good")
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                } else {
                                    Text("Tracking: Limited")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                        .padding(.top, 8)
                        
                        Spacer()
                        
                        // Bottom controls
                        HStack(spacing: 20) {
                            // Reset AR session
                            Button(action: resetARSession) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.title2)
                                    .frame(width: 50, height: 50)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                            
                            Spacer()
                            
                            // Toggle property visibility
                            Button(action: togglePropertyVisibility) {
                                Image(systemName: arManager.showingBoundaries ? "eye.fill" : "eye.slash")
                                    .font(.title2)
                                    .frame(width: 50, height: 50)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                            
                            // Fallback positioning toggle
                            Button(action: toggleFallbackMode) {
                                Image(systemName: arManager.fallbackMode ? "compass.drawing" : "location.circle")
                                    .font(.title2)
                                    .frame(width: 50, height: 50)
                                    .background(.ultraThinMaterial, in: Circle())
                                    .foregroundColor(arManager.fallbackMode ? .orange : .blue)
                            }
                        }
                        .padding(.horizontal, 30)
                        .padding(.bottom, 30)
                    }
                } else {
                    ARUnsupportedView()
                }
            }
            .navigationTitle("AR View")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Info") {
                        showingSettings = true
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                ARSettingsView(arManager: arManager)
                    .environmentObject(appState)
            }
            .alert("AR Error", isPresented: $showingError) {
                Button("OK") { }
                Button("Retry") { setupARSession() }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func setupARSession() {
        arManager.setupSession { error in
            if let error = error {
                errorMessage = error
                showingError = true
            }
        }
        
        // Load coordinates if available
        if let coordinates = appState.currentCoordinates {
            arManager.loadCoordinates(coordinates)
        }
    }
    
    private func handleCoordinateUpdate(_ newCoordinates: ARCoordinateData?) {
        print("🔄 ARTab.handleCoordinateUpdate called with coordinates: \(newCoordinates != nil)")
        
        guard let coordinates = newCoordinates else {
            print("❌ No coordinates provided to AR tab")
            return
        }
        
        print("✅ Loading coordinates into AR manager: \(coordinates.subjectProperty.appellation) with \(coordinates.subjectProperty.arPoints.count) points")
        
        // Successfully parsed coordinates - update AR manager
        arManager.loadCoordinates(coordinates)
        
        // Update positioning status based on coordinate quality  
        if coordinates.metadata.accuracy == "high" {
            appState.updatePositioningStatus(.gps)
        } else {
            appState.updatePositioningStatus(.mathematical)
        }
    }
    
    private func resetARSession() {
        arManager.resetSession()
        
        // Reload coordinates
        if let coordinates = appState.currentCoordinates {
            arManager.loadCoordinates(coordinates)
        }
    }
    
    private func togglePropertyVisibility() {
        arManager.toggleBoundaryVisibility()
    }
    
    private func toggleFallbackMode() {
        arManager.toggleFallbackMode()
        
        // Update app positioning status
        if arManager.fallbackMode {
            appState.updatePositioningStatus(.manual)
        } else {
            appState.updatePositioningStatus(.gps)
        }
    }
}

// Enhanced AR Manager with Property Boundary Support
class ARManager: NSObject, ObservableObject {
    @Published var sessionStatus: ARSessionStatus = .initializing
    @Published var isTrackingGood = false
    @Published var showingBoundaries = true
    @Published var fallbackMode = false
    @Published var currentCoordinates: ARCoordinateData?
    @Published var deviceHeading: Double = 0.0
    
    private var arView: ARView?
    private var propertyEntities: [ModelEntity] = []
    private var boundaryAnchors: [AnchorEntity] = []
    private var locationManager: CLLocationManager?
    private var deviceLocation: CLLocation?
    private var geoAnchors: [ARAnchor] = []
    
    var isARSupported: Bool {
        ARWorldTrackingConfiguration.isSupported
    }
    
    enum ARSessionStatus {
        case initializing
        case ready
        case tracking
        case limited
        case interrupted
        case failed
        
        var displayText: String {
            switch self {
            case .initializing: return "Initializing AR..."
            case .ready: return "AR Ready"
            case .tracking: return "AR Tracking"
            case .limited: return "Limited Tracking"
            case .interrupted: return "AR Interrupted"
            case .failed: return "AR Failed"
            }
        }
        
        var color: Color {
            switch self {
            case .initializing: return .orange
            case .ready: return .blue
            case .tracking: return .green
            case .limited: return .yellow
            case .interrupted: return .orange
            case .failed: return .red
            }
        }
    }
    
    func setupSession(completion: @escaping (String?) -> Void) {
        guard isARSupported else {
            completion("AR is not supported on this device")
            return
        }
        
        sessionStatus = .initializing
        setupLocationManager()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.sessionStatus = .ready
            completion(nil)
        }
    }
    
    func pauseSession() {
        arView?.session.pause()
        sessionStatus = .interrupted
    }
    
    func resetSession() {
        sessionStatus = .initializing
        clearPropertyEntities()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.sessionStatus = .tracking
        }
    }
    
    func loadCoordinates(_ coordinates: ARCoordinateData) {
        print("🎯 ARManager.loadCoordinates called: \(coordinates.subjectProperty.appellation)")
        print("📊 Points: \(coordinates.subjectProperty.arPoints.count), Device location: \(deviceLocation?.coordinate.latitude ?? 0), \(deviceLocation?.coordinate.longitude ?? 0)")
        print("🔄 Fallback mode: \(fallbackMode), Showing boundaries: \(showingBoundaries)")
        
        currentCoordinates = coordinates
        createPropertyBoundaries()
        
        print("✅ ARManager.loadCoordinates completed")
    }
    
    func toggleBoundaryVisibility() {
        showingBoundaries.toggle()
        updateBoundaryVisibility()
    }
    
    func toggleFallbackMode() {
        fallbackMode.toggle()
        
        if fallbackMode {
            // Switch to compass-based positioning
            createFallbackBoundaries()
        } else {
            // Switch back to GPS positioning
            createPropertyBoundaries()
        }
    }
    
    private func createPropertyBoundaries() {
        clearPropertyEntities()
        
        guard let coordinates = currentCoordinates, showingBoundaries else { return }
        
        // Create subject property visualization
        createSubjectPropertyVisualization(coordinates.subjectProperty)
        
        // Create neighbor properties visualization  
        for neighbor in coordinates.neighborProperties {
            createNeighborPropertyVisualization(neighbor)
        }
    }
    
    private func createFallbackBoundaries() {
        clearPropertyEntities()
        
        guard let coordinates = currentCoordinates, showingBoundaries else { return }
        
        // Create simplified compass-based visualization
        createCompassBasedVisualization(coordinates.subjectProperty)
    }
    
    private func createSubjectPropertyVisualization(_ property: PropertyData) {
        // Create GPS-based boundary visualization for subject property (solid blue lines)
        guard let arView = self.arView, currentCoordinates != nil else { 
            print("❌ AR visualization failed: arView=\(arView != nil), coords=\(currentCoordinates != nil)")
            return 
        }
        
        print("🎯 Creating AR visualization for: \(property.appellation) with \(property.arPoints.count) points")
        print("📍 Device location: \(deviceLocation?.coordinate.latitude ?? 0), \(deviceLocation?.coordinate.longitude ?? 0)")
        print("🔄 Fallback mode: \(fallbackMode)")
        
        let anchor: AnchorEntity
        
        // Try to use GPS-based positioning first
        if let deviceLocation = self.deviceLocation, !fallbackMode {
            print("✅ Using GPS-based positioning")
            // Use real GPS positioning with device location as origin
            let originCoord = deviceLocation.coordinate
            anchor = AnchorEntity(world: [0, 0, 0]) // Place at world origin since we're using real coordinates
            
            // Special handling for 2-point baseline
            if property.arPoints.count == 2 {
                print("📏 Creating 2-point baseline visualization")
                let point1 = property.arPoints[0]
                let point2 = property.arPoints[1]
                
                print("🔍 Point 1: lat=\(point1.latitude), lon=\(point1.longitude)")
                print("🔍 Point 2: lat=\(point2.latitude), lon=\(point2.longitude)")
                
                let enu1 = gpsToENU(
                    lat: point1.latitude,
                    lon: point1.longitude,
                    originLat: originCoord.latitude,
                    originLon: originCoord.longitude
                )
                let enu2 = gpsToENU(
                    lat: point2.latitude,
                    lon: point2.longitude,
                    originLat: originCoord.latitude,
                    originLon: originCoord.longitude
                )
                
                print("🎯 ENU 1: \(enu1)")
                print("🎯 ENU 2: \(enu2)")
                
                // Create main baseline
                let baselineEntity = createBoundaryLine(
                    from: enu1,
                    to: enu2,
                    color: .blue,
                    style: .solid
                )
                anchor.addChild(baselineEntity)
                
                // Create perpendicular markers at endpoints to make it more visible
                let distance = simd_distance(enu1, enu2)
                let direction = simd_normalize(enu2 - enu1)
                let perpendicular = simd_float3(-direction.z, direction.y, direction.x) * 2.0 // 2m markers
                
                // Endpoint markers
                let marker1a = createBoundaryLine(from: enu1 - perpendicular, to: enu1 + perpendicular, color: .blue, style: .solid)
                let marker2a = createBoundaryLine(from: enu2 - perpendicular, to: enu2 + perpendicular, color: .blue, style: .solid)
                anchor.addChild(marker1a)
                anchor.addChild(marker2a)
                
                print("✅ Created 2-point baseline with \(distance)m length")
            } else {
                // Create boundary lines using real GPS-to-ENU conversion  
                for i in 0..<property.arPoints.count {
                    let currentPoint = property.arPoints[i]
                    let nextPoint = property.arPoints[(i + 1) % property.arPoints.count]
                    
                    // Convert GPS coordinates to ENU positions relative to device location
                    let currentENU = gpsToENU(
                        lat: currentPoint.latitude,
                        lon: currentPoint.longitude,
                        originLat: originCoord.latitude,
                        originLon: originCoord.longitude
                    )
                    let nextENU = gpsToENU(
                        lat: nextPoint.latitude,
                        lon: nextPoint.longitude,
                        originLat: originCoord.latitude,
                        originLon: originCoord.longitude
                    )
                    
                    let lineEntity = createBoundaryLine(
                        from: currentENU,
                        to: nextENU,
                        color: .blue,
                        style: .solid
                    )
                    
                    anchor.addChild(lineEntity)
                }
            }
        } else {
            print("⚠️ Using fallback positioning (no GPS or fallback mode)")
            // Force GPS conversion even in fallback mode for baseline format
            if property.arPoints.count == 2 {
                // Use origin coordinates from the coordinate data
                if let coords = currentCoordinates {
                    let originCoord = CLLocationCoordinate2D(latitude: coords.origin.latitude, longitude: coords.origin.longitude)
                    anchor = AnchorEntity(world: [0, 0, -3])
                    
                    let point1 = property.arPoints[0]
                    let point2 = property.arPoints[1]
                    
                    let enu1 = gpsToENU(
                        lat: point1.latitude,
                        lon: point1.longitude,
                        originLat: originCoord.latitude,
                        originLon: originCoord.longitude
                    )
                    let enu2 = gpsToENU(
                        lat: point2.latitude,
                        lon: point2.longitude,
                        originLat: originCoord.latitude,
                        originLon: originCoord.longitude
                    )
                    
                    let baselineEntity = createBoundaryLine(from: enu1, to: enu2, color: .blue, style: .solid)
                    anchor.addChild(baselineEntity)
                    
                    print("✅ Created fallback 2-point baseline")
                } else {
                    // Final fallback - create a simple line in front of user
                    anchor = AnchorEntity(world: [0, 0, -5])
                    let lineEntity = createBoundaryLine(
                        from: simd_float3(-2, 0, 0),
                        to: simd_float3(2, 0, 0),
                        color: .blue,
                        style: .solid
                    )
                    anchor.addChild(lineEntity)
                    print("⚠️ Using minimal fallback line")
                }
            } else {
                // Original fallback logic for full polygons (shouldn't happen with baseline format)
                anchor = AnchorEntity(world: [0, 0, -5])
                print("❌ Using x/y/z fallback - this may be invisible!")
                
                for i in 0..<property.arPoints.count {
                    let currentPoint = property.arPoints[i]
                    let nextPoint = property.arPoints[(i + 1) % property.arPoints.count]
                    
                    let lineEntity = createBoundaryLine(
                        from: simd_float3(Float(currentPoint.x), Float(currentPoint.y), Float(currentPoint.z)),
                        to: simd_float3(Float(nextPoint.x), Float(nextPoint.y), Float(nextPoint.z)),
                        color: .blue,
                        style: .solid
                    )
                    
                    anchor.addChild(lineEntity)
                }
            }
        }
        
        arView.scene.addAnchor(anchor)
        boundaryAnchors.append(anchor)
        
        print("Created GPS-based subject property visualization for: \(property.appellation)")
    }
    
    private func createNeighborPropertyVisualization(_ property: PropertyData) {
        // Create GPS-based boundary visualization for neighbor property (dashed red lines)
        guard let arView = self.arView else { return }
        
        let anchor: AnchorEntity
        
        // Try to use GPS-based positioning first
        if let deviceLocation = self.deviceLocation, !fallbackMode {
            // Use real GPS positioning with device location as origin
            let originCoord = deviceLocation.coordinate
            anchor = AnchorEntity(world: [0, 0, 0])
            
            // Create boundary lines using real GPS-to-ENU conversion
            for i in 0..<property.arPoints.count {
                let currentPoint = property.arPoints[i]
                let nextPoint = property.arPoints[(i + 1) % property.arPoints.count]
                
                // Convert GPS coordinates to ENU positions relative to device location
                let currentENU = gpsToENU(
                    lat: currentPoint.latitude,
                    lon: currentPoint.longitude,
                    originLat: originCoord.latitude,
                    originLon: originCoord.longitude
                )
                let nextENU = gpsToENU(
                    lat: nextPoint.latitude,
                    lon: nextPoint.longitude,
                    originLat: originCoord.latitude,
                    originLon: originCoord.longitude
                )
                
                let lineEntity = createBoundaryLine(
                    from: currentENU,
                    to: nextENU,
                    color: .red,
                    style: .dashed
                )
                
                anchor.addChild(lineEntity)
            }
        } else {
            // Fallback to AR coordinates if no GPS or in fallback mode
            anchor = AnchorEntity(world: [0, 0, -5])
            
            for i in 0..<property.arPoints.count {
                let currentPoint = property.arPoints[i]
                let nextPoint = property.arPoints[(i + 1) % property.arPoints.count]
                
                let lineEntity = createBoundaryLine(
                    from: simd_float3(Float(currentPoint.x), Float(currentPoint.y), Float(currentPoint.z)),
                    to: simd_float3(Float(nextPoint.x), Float(nextPoint.y), Float(nextPoint.z)),
                    color: .red,
                    style: .dashed
                )
                
                anchor.addChild(lineEntity)
            }
        }
        
        arView.scene.addAnchor(anchor)
        boundaryAnchors.append(anchor)
        
        print("Created GPS-based neighbor property visualization for: \(property.appellation)")
    }
    
    private func createCompassBasedVisualization(_ property: PropertyData) {
        // Create real compass-based positioning using device heading
        guard let arView = self.arView else { return }
        
        let distance: Float = 8.0 // 8 meters in front for compass mode
        let anchor = AnchorEntity(world: [0, 0, -distance])
        
        // Use actual property boundary points but orient them using device heading
        let headingRadians = Float(deviceHeading * .pi / 180.0)
        let cosHeading = cos(headingRadians)
        let sinHeading = sin(headingRadians)
        
        // Create rotation matrix for device heading
        let rotationMatrix = simd_float3x3(
            simd_float3(cosHeading, 0, sinHeading),
            simd_float3(0, 1, 0),
            simd_float3(-sinHeading, 0, cosHeading)
        )
        
        // If we have AR points, use them with compass orientation
        if !property.arPoints.isEmpty {
            for i in 0..<property.arPoints.count {
                let currentPoint = property.arPoints[i]
                let nextPoint = property.arPoints[(i + 1) % property.arPoints.count]
                
                // Apply compass rotation to AR points
                let currentPos = rotationMatrix * simd_float3(Float(currentPoint.x), Float(currentPoint.y), Float(currentPoint.z))
                let nextPos = rotationMatrix * simd_float3(Float(nextPoint.x), Float(nextPoint.y), Float(nextPoint.z))
                
                let lineEntity = createBoundaryLine(
                    from: currentPos,
                    to: nextPos,
                    color: .orange,
                    style: .solid
                )
                
                anchor.addChild(lineEntity)
            }
        } else {
            // Fallback to rectangular approximation with compass orientation
            let size = sqrt(property.area) / 1000 // Convert to approximate meters
            let halfSize = Float(size) / 2
            
            // Create corners of rectangle and apply compass rotation
            let baseCorners = [
                simd_float3(-halfSize, 0, -halfSize),
                simd_float3(halfSize, 0, -halfSize),
                simd_float3(halfSize, 0, halfSize),
                simd_float3(-halfSize, 0, halfSize)
            ]
            
            let rotatedCorners = baseCorners.map { rotationMatrix * $0 }
            
            // Create boundary lines with compass orientation
            for i in 0..<rotatedCorners.count {
                let currentCorner = rotatedCorners[i]
                let nextCorner = rotatedCorners[(i + 1) % rotatedCorners.count]
                
                let lineEntity = createBoundaryLine(
                    from: currentCorner,
                    to: nextCorner,
                    color: .orange,
                    style: .solid
                )
                
                anchor.addChild(lineEntity)
            }
        }
        
        arView.scene.addAnchor(anchor)
        boundaryAnchors.append(anchor)
        
        print("Created compass-based visualization for: \(property.appellation) with heading: \(deviceHeading)°")
    }
    
    private func createBoundaryLine(from start: simd_float3, to end: simd_float3, color: UIColor, style: LineStyle) -> ModelEntity {
        // Create a simple line entity between two points
        let distance = simd_distance(start, end)
        let direction = normalize(end - start)
        let midPoint = (start + end) / 2
        
        // Create a thin box to represent the line
        let lineHeight: Float = 0.02 // 2cm thick line
        let mesh = MeshResource.generateBox(width: distance, height: lineHeight, depth: lineHeight)
        
        var material = SimpleMaterial()
        material.color = .init(tint: color)
        
        // For dashed lines, reduce opacity
        if style == .dashed {
            material.color = .init(tint: color.withAlphaComponent(0.7))
        }
        
        let lineEntity = ModelEntity(mesh: mesh, materials: [material])
        lineEntity.position = midPoint
        
        // Rotate to align with direction
        let angle = atan2(direction.z, direction.x)
        lineEntity.orientation = simd_quatf(angle: angle, axis: [0, 1, 0])
        
        return lineEntity
    }
    
    private func clearPropertyEntities() {
        // Remove all existing property visualizations
        boundaryAnchors.forEach { anchor in
            arView?.scene.removeAnchor(anchor)
        }
        boundaryAnchors.removeAll()
        
        propertyEntities.forEach { entity in
            entity.removeFromParent()
        }
        propertyEntities.removeAll()
    }
    
    private func updateBoundaryVisibility() {
        boundaryAnchors.forEach { anchor in
            anchor.isEnabled = showingBoundaries
        }
    }
    
    func setARView(_ arView: ARView) {
        self.arView = arView
    }
    
    // MARK: - Location Management
    
    private func setupLocationManager() {
        locationManager = CLLocationManager()
        locationManager?.delegate = self
        locationManager?.desiredAccuracy = kCLLocationAccuracyBest
        locationManager?.requestWhenInUseAuthorization()
        
        // Enable heading updates for compass functionality
        if CLLocationManager.headingAvailable() {
            locationManager?.startUpdatingHeading()
        }
        
        locationManager?.startUpdatingLocation()
    }
    
    // MARK: - Coordinate Conversion
    
    /// Convert GPS coordinates to ENU (East-North-Up) relative to origin
    private func gpsToENU(lat: Double, lon: Double, originLat: Double, originLon: Double) -> simd_float3 {
        let R = 6378137.0 // WGS84 Earth radius in meters
        
        // Convert to radians
        let latRad = lat * .pi / 180.0
        let lonRad = lon * .pi / 180.0
        let originLatRad = originLat * .pi / 180.0
        let originLonRad = originLon * .pi / 180.0
        
        // Calculate differences
        let dLat = latRad - originLatRad
        let dLon = lonRad - originLonRad
        
        // Convert to ENU coordinates
        let cosLat = cos(originLatRad)
        
        let east = R * dLon * cosLat
        let north = R * dLat
        let up = 0.0 // Assume same altitude for AR
        
        // Return in AR coordinate system (x=east, y=up, z=-north for RealityKit)
        return simd_float3(Float(east), Float(up), Float(-north))
    }
    
    enum LineStyle {
        case solid
        case dashed
    }
}

// MARK: - CLLocationManagerDelegate

extension ARManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        DispatchQueue.main.async {
            self.deviceLocation = location
            
            // Update positioning status based on location accuracy
            if location.horizontalAccuracy < 10 {
                // High accuracy GPS - reload boundaries with GPS positioning
                if self.currentCoordinates != nil {
                    self.createPropertyBoundaries()
                }
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        DispatchQueue.main.async {
            // Use magnetic heading for compass functionality
            self.deviceHeading = newHeading.magneticHeading
            
            // If in fallback mode, update compass-based visualization
            if self.fallbackMode && self.currentCoordinates != nil {
                self.createFallbackBoundaries()
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager error: \(error.localizedDescription)")
        
        DispatchQueue.main.async {
            // Fall back to manual mode if location services fail
            self.fallbackMode = true
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() {
                manager.startUpdatingHeading()
            }
        case .denied, .restricted:
            DispatchQueue.main.async {
                self.fallbackMode = true
            }
        default:
            break
        }
    }
}

// Enhanced AR View Container with Property Boundary Support
struct EnhancedARViewContainer: UIViewRepresentable {
    let arManager: ARManager
    let coordinates: ARCoordinateData?
    let fallbackMode: Bool
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        
        // Enhanced AR configuration
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        
        arView.session.run(config)
        arView.session.delegate = context.coordinator
        
        // Set AR view in manager
        arManager.setARView(arView)
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        // Update AR view based on coordinates and fallback mode
        if let coordinates = coordinates {
            context.coordinator.updateCoordinates(coordinates, in: uiView)
        }
    }
    
    func makeCoordinator() -> ARCoordinator {
        ARCoordinator(arManager: arManager)
    }
    
    class ARCoordinator: NSObject, ARSessionDelegate {
        let arManager: ARManager
        
        init(arManager: ARManager) {
            self.arManager = arManager
        }
        
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            DispatchQueue.main.async {
                // Update tracking quality
                switch frame.camera.trackingState {
                case .normal:
                    self.arManager.isTrackingGood = true
                    self.arManager.sessionStatus = .tracking
                case .limited:
                    self.arManager.isTrackingGood = false
                    self.arManager.sessionStatus = .limited
                case .notAvailable:
                    self.arManager.isTrackingGood = false
                    self.arManager.sessionStatus = .failed
                }
            }
        }
        
        func sessionWasInterrupted(_ session: ARSession) {
            DispatchQueue.main.async {
                self.arManager.sessionStatus = .interrupted
            }
        }
        
        func sessionInterruptionEnded(_ session: ARSession) {
            DispatchQueue.main.async {
                self.arManager.sessionStatus = .tracking
            }
        }
        
        func updateCoordinates(_ coordinates: ARCoordinateData, in arView: ARView) {
            // Update coordinate visualization in AR space
            print("Updating AR coordinates for \(coordinates.subjectProperty.appellation)")
        }
    }
}

// AR Unsupported View
struct ARUnsupportedView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            Text("AR Not Supported")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Your device doesn't support the required AR features for property boundary visualization.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            Button("Learn More") {
                // Open AR requirements info
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
    }
}

// AR Settings View
struct ARSettingsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var arManager: ARManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section("AR Status") {
                    HStack {
                        Text("Session Status")
                        Spacer()
                        Text(arManager.sessionStatus.displayText)
                            .foregroundColor(arManager.sessionStatus.color)
                    }
                    
                    HStack {
                        Text("Tracking Quality")
                        Spacer()
                        Text(arManager.isTrackingGood ? "Good" : "Limited")
                            .foregroundColor(arManager.isTrackingGood ? .green : .orange)
                    }
                    
                    HStack {
                        Text("Positioning Method")
                        Spacer()
                        Text(appState.positioningStatus.displayText)
                            .foregroundColor(appState.positioningStatus.color)
                    }
                }
                
                Section("Property Data") {
                    if let property = appState.subjectProperty {
                        HStack {
                            Text("Property")
                            Spacer()
                            Text(property.appellation)
                        }
                        
                        HStack {
                            Text("AR Points")
                            Spacer()
                            Text("\(property.arPoints.count)")
                        }
                        
                        HStack {
                            Text("Neighbors")
                            Spacer()
                            Text("\(appState.neighborProperties.count)")
                        }
                    } else {
                        Text("No property data loaded")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Controls") {
                    Toggle("Show Boundaries", isOn: $arManager.showingBoundaries)
                    Toggle("Fallback Mode", isOn: $arManager.fallbackMode)
                    
                    Button("Reset AR Session") {
                        arManager.resetSession()
                    }
                }
            }
            .navigationTitle("AR Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    ARTab()
        .environmentObject(AppState())
}