import SwiftUI
import CoreLocation
import WebKit

struct MapTab: View {
    @EnvironmentObject var state: AppState
    @StateObject private var loc = LocationModel()
    @StateObject private var webViewStore = WebViewStore()
    @Binding var selectedTab: Int

    @State private var webURL: URL?
    @State private var didSeed = false
    @State private var showingAlert = false
    @State private var alertMessage = ""

    var body: some View {
        NavigationView {
            ZStack {
                // Enhanced WebView with improved messaging
                EnhancedWebMapView(
                    url: webURL ?? state.bundledWebURL(with: nil),
                    webViewStore: webViewStore,
                    selectedTab: $selectedTab,
                    onCoordinatesReceived: { coordinates in
                        state.updateCoordinates(coordinates)
                    },
                    onAlignmentPointsReceived: { points in
                        state.updateAlignmentPoints(points)
                    },
                    onError: { error in
                        alertMessage = error
                        showingAlert = true
                    }
                )
                .ignoresSafeArea()
                
                // Enhanced overlay information
                VStack {
                    HStack {
                        Spacer()
                        VStack(alignment: .trailing, spacing: 8) {
                            // Location status
                            if let location = loc.last {
                                Label("\(location.coordinate.latitude, specifier: "%.4f"), \(location.coordinate.longitude, specifier: "%.4f")", 
                                      systemImage: "location.fill")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                            }
                            
                            // Property count
                            if state.hasPropertyData() {
                                Label("\(state.getPropertyCount()) properties", 
                                      systemImage: "building.2")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                            }
                            
                            // Positioning status
                            Label(state.positioningStatus.displayText, 
                                  systemImage: "location.circle")
                                .font(.caption)
                                .foregroundColor(state.positioningStatus.color)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .padding(.trailing, 16)
                        .padding(.top, 8)
                    }
                    Spacer()
                }
            }
            .navigationTitle("PropertyView Enhanced")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: refreshLocation) {
                            Label("Refresh Location", systemImage: "location.circle")
                        }
                        
                        Button(action: clearCache) {
                            Label("Clear Cache", systemImage: "trash")
                        }
                        
                        if state.hasPropertyData() {
                            Button(action: shareProperty) {
                                Label("Share Property", systemImage: "square.and.arrow.up")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .onAppear {
                setupInitialURL()
            }
            .onChange(of: loc.last) { newLoc in
                handleLocationUpdate(newLoc)
            }
            .alert("Map Error", isPresented: $showingAlert) {
                Button("OK") { }
            } message: {
                Text(alertMessage)
            }
        }
    }
    
    private func setupInitialURL() {
        webURL = state.bundledWebURL(with: nil)
    }
    
    private func handleLocationUpdate(_ newLoc: CLLocation?) {
        guard !didSeed, let newLoc else { return }
        webURL = state.bundledWebURL(with: newLoc)
        didSeed = true
        state.updatePositioningStatus(.gps)
    }
    
    private func refreshLocation() {
        loc.requestLocation()
        didSeed = false
    }
    
    private func clearCache() {
        webViewStore.clearCache()
        alertMessage = "Cache cleared successfully"
        showingAlert = true
    }
    
    private func shareProperty() {
        guard let property = state.subjectProperty else { return }
        
        let shareText = """
        Property: \(property.appellation)
        Area: \(property.area > 10000 ? String(format: "%.2f hectares", property.area/10000) : String(format: "%.0f m²", property.area))
        """
        
        let activityVC = UIActivityViewController(
            activityItems: [shareText],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(activityVC, animated: true)
        }
    }
}

// Enhanced WebView Store for cache management
class WebViewStore: ObservableObject {
    @Published var webView: WKWebView
    
    init() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        
        // Enhanced JavaScript bridge
        let userContentController = WKUserContentController()
        config.userContentController = userContentController
        
        self.webView = WKWebView(frame: .zero, configuration: config)
    }
    
    func clearCache() {
        let dataStore = webView.configuration.websiteDataStore
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        
        dataStore.removeData(ofTypes: dataTypes, modifiedSince: Date(timeIntervalSince1970: 0)) {
            print("Cache cleared")
        }
    }
}

struct EnhancedWebMapView: UIViewRepresentable {
    let url: URL
    let webViewStore: WebViewStore
    @Binding var selectedTab: Int
    let onCoordinatesReceived: (ARCoordinateData) -> Void
    let onAlignmentPointsReceived: ([CLLocationCoordinate2D]) -> Void
    let onError: (String) -> Void
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = webViewStore.webView
        webView.navigationDelegate = context.coordinator
        
        // Enhanced JavaScript message handlers
        let userContentController = webView.configuration.userContentController
        
        userContentController.add(context.coordinator, name: "saveAlignmentPoints")
        userContentController.add(context.coordinator, name: "switchToAR")
        userContentController.add(context.coordinator, name: "statusUpdate")
        userContentController.add(context.coordinator, name: "errorReport")
        userContentController.add(context.coordinator, name: "exportKML")
        
        // Enhanced LINZ API key injection
        if let apiKey = Bundle.main.infoDictionary?["LINZ_API_KEY"] as? String {
            let script = "window.LINZ_API_KEY = '\(apiKey)';"
            let userScript = WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            userContentController.addUserScript(userScript)
        }
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        if webView.url != url {
            let request = URLRequest(url: url)
            webView.load(request)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let parent: EnhancedWebMapView
        
        init(_ parent: EnhancedWebMapView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.onError("Failed to load map: \(error.localizedDescription)")
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "saveAlignmentPoints":
                handleAlignmentPoints(message.body)
            case "switchToAR":
                handleSwitchToAR(message.body)
            case "statusUpdate":
                handleStatusUpdate(message.body)
            case "errorReport":
                handleErrorReport(message.body)
            case "exportKML":
                handleExportKML(message.body)
            default:
                break
            }
        }
        
        private func handleAlignmentPoints(_ body: Any) {
            guard let data = try? JSONSerialization.data(withJSONObject: body),
                  let alignmentData = try? JSONDecoder().decode(AlignmentData.self, from: data) else {
                parent.onError("Failed to parse alignment points")
                return
            }
            
            let coordinates = alignmentData.subjectProperty.alignmentPoints.map { point in
                CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
            }
            
            parent.onAlignmentPointsReceived(coordinates)
        }
        
        private func handleSwitchToAR(_ body: Any) {
            guard let data = try? JSONSerialization.data(withJSONObject: body) else {
                parent.onError("Failed to serialize AR coordinate data")
                return
            }
            
            // First try automated corners format (all property corners)
            if let cornersData = try? JSONDecoder().decode(ARCornersData.self, from: data) {
                let arData = convertCornersToARCoordinates(cornersData)
                parent.onCoordinatesReceived(arData)
                print("✅ Using automated corners: \(cornersData.corners.count) points from LINZ data")
                // Switch to AR tab
                DispatchQueue.main.async { [weak self] in
                    self?.parent.selectedTab = 1
                }
                return
            }
            
            // Try simplified baseline format (2 points)
            if let baselineData = try? JSONDecoder().decode(ARBaselineData.self, from: data) {
                let arData = convertBaselineToARCoordinates(baselineData)
                parent.onCoordinatesReceived(arData)
                print("✅ Using baseline: 2 points")
                // Switch to AR tab
                DispatchQueue.main.async { [weak self] in
                    self?.parent.selectedTab = 1
                }
                return
            }
            
            // Fall back to old complex format
            if let arData = try? JSONDecoder().decode(ARCoordinateData.self, from: data) {
                parent.onCoordinatesReceived(arData)
                // Switch to AR tab
                DispatchQueue.main.async { [weak self] in
                    self?.parent.selectedTab = 1
                }
                return
            }
            
            // Enhanced error logging
            let jsonString = String(data: data, encoding: .utf8) ?? "Invalid UTF-8"
            let preview = String(jsonString.prefix(200))
            print("Failed to parse AR coordinates. JSON preview: \(preview)")
            parent.onError("Failed to parse AR coordinates. Check LINZ data and API key.")
        }
        
        private func convertCornersToARCoordinates(_ corners: ARCornersData) -> ARCoordinateData {
            // Convert all corner points to full AR coordinate structure
            let arPoints = corners.corners.map { point in
                ARPoint(
                    x: 0.0, // Will be computed in ARManager
                    y: 0.0,
                    z: 0.0, 
                    latitude: point.latitude,
                    longitude: point.longitude,
                    distance: nil
                )
            }
            
            let subjectProperty = PropertyData(
                appellation: corners.metadata.subjectAppellation,
                area: corners.metadata.area,
                distance: nil,
                arPoints: arPoints,
                centroid: nil
            )
            
            let metadata = MetadataData(
                totalProperties: 1,
                conversionMethod: corners.metadata.conversionMethod,
                accuracy: corners.metadata.accuracy,
                timestamp: corners.metadata.timestamp
            )
            
            return ARCoordinateData(
                origin: corners.origin,
                subjectProperty: subjectProperty,
                neighborProperties: [],
                metadata: metadata
            )
        }
        
        private func convertBaselineToARCoordinates(_ baseline: ARBaselineData) -> ARCoordinateData {
            // Convert 2-point baseline to full AR coordinate structure
            let arPoints = baseline.baseline.map { point in
                ARPoint(
                    x: 0.0, // Will be computed in ARManager
                    y: 0.0,
                    z: 0.0, 
                    latitude: point.latitude,
                    longitude: point.longitude,
                    distance: nil
                )
            }
            
            let subjectProperty = PropertyData(
                appellation: baseline.metadata.subjectAppellation,
                area: baseline.metadata.area,
                distance: nil,
                arPoints: arPoints,
                centroid: nil
            )
            
            let metadata = MetadataData(
                totalProperties: 1,
                conversionMethod: baseline.metadata.conversionMethod,
                accuracy: baseline.metadata.accuracy,
                timestamp: baseline.metadata.timestamp
            )
            
            return ARCoordinateData(
                origin: baseline.origin,
                subjectProperty: subjectProperty,
                neighborProperties: [], // Simplified - no neighbors for 2-point setup
                metadata: metadata
            )
        }
        
        private func handleStatusUpdate(_ body: Any) {
            // Handle status updates from web view
            print("Status update:", body)
        }
        
        private func handleErrorReport(_ body: Any) {
            if let errorDict = body as? [String: Any],
               let error = errorDict["error"] as? String {
                parent.onError("Map error: \(error)")
            }
        }
        
        private func handleExportKML(_ body: Any) {
            guard let exportDict = body as? [String: Any],
                  let filename = exportDict["filename"] as? String,
                  let base64 = exportDict["base64"] as? String,
                  let data = Data(base64Encoded: base64) else {
                parent.onError("Failed to export KML")
                return
            }
            
            // Handle KML export
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            do {
                try data.write(to: tempURL)
                
                let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first {
                    window.rootViewController?.present(activityVC, animated: true)
                }
            } catch {
                parent.onError("Failed to save KML file")
            }
        }
    }
}

struct AlignmentData: Codable {
    let subjectProperty: AlignmentProperty
    let timestamp: String
}

struct AlignmentProperty: Codable {
    let appellation: String
    let alignmentPoints: [AlignmentPoint]
    let boundaries: [AlignmentPoint]
}

struct AlignmentPoint: Codable {
    let latitude: Double
    let longitude: Double
}

#Preview {
    MapTab(selectedTab: .constant(0))
        .environmentObject(AppState())
}
