import SwiftUI
import WebKit
import CoreLocation

protocol WebViewDelegate: AnyObject {
    var webView: WKWebView? { get }
}

struct MapView: UIViewRepresentable {
    @EnvironmentObject var appState: AppState
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        
        // Get API keys from Bundle with multiple fallback methods
        let linzKey = Bundle.main.object(forInfoDictionaryKey: "LINZ_API_KEY") as? String ?? ""
        let locationiqKey = Bundle.main.object(forInfoDictionaryKey: "LOCATIONIQ_API_KEY") as? String ?? "pk.022a4792ac3437f3ae8d42bf5128cc88"
        let googleKey = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_API_KEY") as? String ?? ""
        
        // Log for debugging
        print("🔑 iOS API Key Status:")
        print("  LINZ: \(linzKey.isEmpty ? "EMPTY" : "LOADED (\(linzKey.count) chars)")")
        print("  LocationIQ: \(locationiqKey.isEmpty ? "EMPTY" : "LOADED (\(locationiqKey.count) chars)")")
        print("  Google: \(googleKey.isEmpty ? "EMPTY" : "LOADED (\(googleKey.count) chars)")")
        
        // Escape quotes properly
        let escapedLinz = linzKey.replacingOccurrences(of: "'", with: "\\'").replacingOccurrences(of: "\"", with: "\\\"")
        let escapedLocationiq = locationiqKey.replacingOccurrences(of: "'", with: "\\'").replacingOccurrences(of: "\"", with: "\\\"")
        let escapedGoogle = googleKey.replacingOccurrences(of: "'", with: "\\'").replacingOccurrences(of: "\"", with: "\\\"")
        
        // Inject ALL API keys BEFORE page loads with comprehensive logging
        let script = """
        console.log('🔑 iOS injecting API keys...');
        window.LINZ_API_KEY = '\(escapedLinz)';
        window.LOCATIONIQ_API_KEY = '\(escapedLocationiq)';
        window.GOOGLE_API_KEY = '\(escapedGoogle)';
        console.log('🔑 API Keys injected from iOS:', {
            LINZ: !!window.LINZ_API_KEY,
            LocationIQ: !!window.LOCATIONIQ_API_KEY,
            Google: !!window.GOOGLE_API_KEY
        });
        console.log('🔑 LINZ API Key length:', window.LINZ_API_KEY.length);
        console.log('🔑 LINZ API Key preview:', window.LINZ_API_KEY.substring(0,8) + '...');
        
        // Also set a flag that iOS injection happened
        window.iOS_INJECTION_COMPLETE = true;
        """
        
        let userScript = WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        controller.addUserScript(userScript)
        
        // Add message handlers
        controller.add(context.coordinator, name: "iosLog")
        controller.add(context.coordinator, name: "requestLocation")
        controller.add(context.coordinator, name: "propertyData")
        controller.add(context.coordinator, name: "openAR") 
        
        config.userContentController = controller
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        
        // Load local HTML
        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Web") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            print("❌ Could not find Web/index.html")
            webView.loadHTMLString("<h1>Error: Web/index.html not found</h1>", baseURL: nil)
        }
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(appState: appState)
    }
    
    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, CLLocationManagerDelegate {
        private let locationManager = CLLocationManager()
        var webView: WKWebView?
        private var appState: AppState
        
        init(appState: AppState) {
            self.appState = appState
            super.init()
            locationManager.delegate = self
            locationManager.desiredAccuracy = kCLLocationAccuracyBest
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "iosLog":
                print("📱 Web: \(message.body)")
            case "requestLocation":
                requestLocation()
            case "propertyData":
                handlePropertyData(message.body)
            case "openAR":
                handleOpenAR()
            default:
                break
            }
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("✅ Web page loaded successfully")
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("❌ Web page failed to load: \(error)")
        }
        
        private func requestLocation() {
            locationManager.requestWhenInUseAuthorization()
            locationManager.requestLocation()
        }
        
        func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            guard let location = locations.first else { return }
            print("📍 Got location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
            
            // Send location data to JavaScript
            let script = "if (window.receiveLocation) { window.receiveLocation(\(location.coordinate.latitude), \(location.coordinate.longitude)); }"
            webView?.evaluateJavaScript(script) { result, error in
                if let error = error {
                    print("❌ Error sending location to web: \(error)")
                } else {
                    print("✅ Location sent to web view")
                }
            }
        }
        
        
        func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
            print("❌ Location error: \(error)")
        }
        
        private func handlePropertyData(_ data: Any) {
            guard let propertyDict = data as? [String: Any],
                  let coordinates = propertyDict["coordinates"] as? [[String: Double]],
                  let property = propertyDict["property"] as? [String: Any] else {
                print("❌ Invalid property data received")
                return
            }
            
            let boundaryCoordinates = coordinates.compactMap { coord -> CLLocationCoordinate2D? in
                guard let lat = coord["latitude"], let lon = coord["longitude"] else { return nil }
                return CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
            
            print("✅ Property data received: \(boundaryCoordinates.count) coordinates")
            
            // Update app state with property coordinates for AR view
            DispatchQueue.main.async {
                self.appState.updatePropertyCoordinates(boundaryCoordinates)
            }
        }
        
        private func handleOpenAR() {
            print("📱 Web requested to open AR view")
            
            // Switch to AR tab
            DispatchQueue.main.async {
                if let tabView = UIApplication.shared.windows.first?.rootViewController {
                    // This would need to be implemented based on your specific tab navigation structure
                    // For now, we'll just log the request
                    print("🥽 AR view request received from web interface")
                }
            }
        }
        
    }
}