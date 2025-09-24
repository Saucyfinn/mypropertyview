import SwiftUI
import ARKit
import SceneKit
import CoreLocation

struct ARView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingSettings = false
    @State private var showingError = false
    @State private var errorMessage: String = ""
    @State private var arManager = ARManager()
    @State private var status = "Initializing AR..."
    
    var body: some View {
        ZStack {
            if arManager.isARSupported {
                ARViewContainer(
                    arManager: arManager,
                    coordinates: appState.currentCoordinates ?? [],
                    positioningStatus: appState.positioningStatus,
                    status: $status
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
            
            // Status overlay
            VStack {
                Spacer()
                HStack {
                    Text(status)
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    Spacer()
                }
                .padding()
            }
        }
        .alert("AR Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
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
}

struct ARUnsupportedView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            Text("AR Not Supported")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("This device doesn't support ARKit. You can still use the Map view to see property boundaries.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
        }
        .padding()
    }
}

struct ARViewContainer: UIViewRepresentable {
    let arManager: ARManager
    let coordinates: [CLLocationCoordinate2D]
    let positioningStatus: PositioningStatus
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
        context.coordinator.updateBoundaries(coordinates, status: $status)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate {
        let parent: ARViewContainer
        private weak var arView: ARSCNView?
        
        init(_ parent: ARViewContainer) {
            self.parent = parent
        }
        
        func setupPositioningSystem(arView: ARSCNView) {
            self.arView = arView
            parent.arManager.setARView(arView)
        }
        
        func updateBoundaries(_ coordinates: [CLLocationCoordinate2D], status: Binding<String>) {
            guard !coordinates.isEmpty else {
                status.wrappedValue = "No property data available"
                return
            }
            
            parent.arManager.loadCoordinates(coordinates)
        }
        
        private func calculateCentroid(of coordinates: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D {
            guard !coordinates.isEmpty else { return CLLocationCoordinate2D(latitude: 0, longitude: 0) }
            
            var totalLat = 0.0
            var totalLon = 0.0
            
            for coord in coordinates {
                totalLat += coord.latitude
                totalLon += coord.longitude
            }
            
            return CLLocationCoordinate2D(
                latitude: totalLat / Double(coordinates.count),
                longitude: totalLon / Double(coordinates.count)
            )
        }
        
        // MARK: - ARSessionDelegate
        
        func session(_ session: ARSession, didFailWithError error: Error) {
            print("AR session failed: \(error)")
        }
        
        func sessionWasInterrupted(_ session: ARSession) {
            print("AR session interrupted")
        }
        
        func sessionInterruptionEnded(_ session: ARSession) {
            print("AR session interruption ended")
        }
    }
}

extension ARViewContainer.Coordinator: PositioningManagerDelegate {
    func positioningManager(_ manager: PositioningManager, didUpdateStatus status: PositioningStatus) {
        DispatchQueue.main.async {
            switch status {
            case .initializing:
                self.parent.status = "Initializing positioning..."
            case .geoTrackingAvailable:
                self.parent.status = "GPS tracking active"
            case .planeDetectionActive:
                self.parent.status = "Detecting surfaces..."
            case .compassBearingActive:
                self.parent.status = "Using compass orientation"
            case .visualMarkerActive:
                self.parent.status = "Looking for visual markers..."
            case .manualAlignmentRequired:
                self.parent.status = "Tap to align boundaries"
            case .positioned:
                self.parent.status = "Property boundaries positioned"
            case .failed(let error):
                self.parent.status = "Positioning failed: \(error)"
            }
        }
    }
    
    func positioningManager(_ manager: PositioningManager, didUpdateMethod method: PositioningMethod) {
        DispatchQueue.main.async {
            switch method {
            case .geoTracking:
                self.parent.status = "Using GPS geo-anchoring"
            case .planeDetection:
                self.parent.status = "Using plane detection"
            case .compassBearing:
                self.parent.status = "Using compass bearing"
            case .visualMarker:
                self.parent.status = "Using visual markers"
            case .manualAlignment:
                self.parent.status = "Manual alignment mode"
            case .fallback:
                self.parent.status = "Using fallback positioning"
            }
        }
    }
    
    func positioningManager(_ manager: PositioningManager, didPositionBoundaries transform: simd_float4x4) {
        DispatchQueue.main.async {
            self.parent.status = "Property boundaries positioned successfully"
        }
    }
}

class ARManager: ObservableObject {
    @Published var isARSupported = false
    private var arView: ARSCNView?
    
    init() {
        checkARSupport()
    }
    
    private func checkARSupport() {
        isARSupported = ARWorldTrackingConfiguration.isSupported
    }
    
    func setupSession(completion: @escaping (String?) -> Void) {
        guard isARSupported else {
            completion("AR not supported on this device")
            return
        }
        completion(nil)
    }
    
    func loadCoordinates(_ coordinates: [CLLocationCoordinate2D]) {
        // Implementation for loading coordinates into AR view
        print("Loading \(coordinates.count) coordinates into AR view")
    }
    
    func pauseSession() {
        // Implementation for pausing AR session
        print("Pausing AR session")
    }
    
    func resetSession() {
        // Implementation for resetting AR session
        print("Resetting AR session")
    }
}