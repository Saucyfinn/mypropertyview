import SwiftUI
import ARKit
import CoreLocation
import RealityKit

struct ARTab: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var arManager = ARManager()
    @State private var showingSettings = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            ZStack {
                // Enhanced AR View
                if arManager.isARSupported {
                    EnhancedARViewContainer(
                        arManager: arManager,
                        coordinates: appState.currentCoordinates,
                        positioningStatus: appState.positioningStatus
                    )
                    .ignoresSafeArea()
                    .onAppear {
                        setupARSession()
                    }
                    .onDisappear {
                        arManager.pauseSession()
                    }
                } else {
                    ARUnsupportedView()
                }
                
                // Enhanced AR Controls Overlay
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
                        
                        // AR Settings
                        Button(action: { showingSettings = true }) {
                            Image(systemName: "gear")
                                .font(.title2)
                                .frame(width: 50, height: 50)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, 30)
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
}

// Enhanced AR Manager
class ARManager: NSObject, ObservableObject {
    @Published var sessionStatus: ARSessionStatus = .initializing
    @Published var isTrackingGood = false
    @Published var showingBoundaries = true
    @Published var currentCoordinates: ARCoordinateData?
    
    private var arView: ARView?
    private var propertyEntities: [ModelEntity] = []
    
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
        currentCoordinates = coordinates
        createPropertyBoundaries()
    }
    
    func toggleBoundaryVisibility() {
        showingBoundaries.toggle()
        updateBoundaryVisibility()
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
    
    private func createSubjectPropertyVisualization(_ property: PropertyData) {
        // Create 3D boundary visualization for subject property
        // This would contain the actual RealityKit/ARKit implementation
        print("Creating subject property visualization for: \(property.appellation)")
    }
    
    private func createNeighborPropertyVisualization(_ property: PropertyData) {
        // Create 3D boundary visualization for neighbor property
        print("Creating neighbor property visualization for: \(property.appellation)")
    }
    
    private func clearPropertyEntities() {
        propertyEntities.forEach { entity in
            entity.removeFromParent()
        }
        propertyEntities.removeAll()
    }
    
    private func updateBoundaryVisibility() {
        propertyEntities.forEach { entity in
            entity.isEnabled = showingBoundaries
        }
    }
}

// Enhanced AR View Container
struct EnhancedARViewContainer: UIViewRepresentable {
    let arManager: ARManager
    let coordinates: ARCoordinateData?
    let positioningStatus: AppState.PositioningStatus
    
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
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        // Update AR view based on coordinates and status
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
            // Implement coordinate visualization in AR space
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
                    
                    Button("Reset AR Session") {
                        arManager.resetSession()
                    }
                    
                    Button("Reload Property Data") {
                        // Trigger reload from map
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

struct SettingsTab: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        NavigationView {
            List {
                Section("App Information") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("PropertyView Enhanced 1.0")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Properties Loaded")
                        Spacer()
                        Text("\(appState.getPropertyCount())")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Data Sources") {
                    HStack {
                        Text("LINZ Integration")
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                    
                    HStack {
                        Text("AR Positioning")
                        Spacer()
                        Text(appState.positioningStatus.displayText)
                            .foregroundColor(appState.positioningStatus.color)
                    }
                }
                
                Section("Help") {
                    Button("How to Use AR View") { }
                    Button("Property Boundary Guide") { }
                    Button("Contact Support") { }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    ARTab()
        .environmentObject(AppState())
}

