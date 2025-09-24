//
//  WebMapView.swift
//  PropertyView-Enhanced
//

import SwiftUI
import WebKit
import CoreLocation
import UIKit

struct WebMapView: UIViewRepresentable {

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        let ucc = WKUserContentController()

        // Inject LINZ key + defaults before any page JS runs
        let linzKey = (Bundle.main.object(forInfoDictionaryKey: "LINZ_API_KEY") as? String) ?? ""
        let escapedKey = linzKey.replacingOccurrences(of: "'", with: "\\'")
        let bootstrap = """
        window.LINZ_API_KEY = '\(escapedKey)';
        window.APP_SATELLITE_DEFAULT = true; // let the web code start in satellite view
        """
        ucc.addUserScript(WKUserScript(source: bootstrap, injectionTime: .atDocumentStart, forMainFrameOnly: true))

        // JS → iOS bridges
        ucc.add(context.coordinator, name: "ios.requestLocation")
        ucc.add(context.coordinator, name: "ios.log")
        ucc.add(context.coordinator, name: "ios.shareKML") // pass a KML string to share via sheet
        ucc.add(context.coordinator, name: "switchToAR") // AR coordinates bridge
        ucc.add(context.coordinator, name: "requestAddress") // reverse geocoding for property addresses

        cfg.userContentController = ucc
        if #available(iOS 14.0, *) {
            cfg.defaultWebpagePreferences.allowsContentJavaScript = true
        }

        let web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = context.coordinator
        context.coordinator.webView = web

        // Load Web/index.html from bundle
        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Web") {
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            web.loadHTMLString("""
            <html><body style="font-family:-apple-system;padding:24px">
              <h3>Missing Web/index.html</h3>
              <p>Add <code>Web/index.html</code> (and your JS/CSS) to the app target.</p>
            </body></html>
            """, baseURL: nil)
        }

        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) { /* no-op */ }

    // MARK: - Coordinator
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, CLLocationManagerDelegate {
        weak var webView: WKWebView?

        private let loc = CLLocationManager()
        private var askedAuth = false

        override init() {
            super.init()
            loc.delegate = self
            loc.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        }

        deinit {
            webView?.configuration.userContentController.removeScriptMessageHandler(forName: "ios.requestLocation")
            webView?.configuration.userContentController.removeScriptMessageHandler(forName: "ios.log")
            webView?.configuration.userContentController.removeScriptMessageHandler(forName: "ios.shareKML")
            webView?.configuration.userContentController.removeScriptMessageHandler(forName: "switchToAR")
            webView?.configuration.userContentController.removeScriptMessageHandler(forName: "requestAddress")
        }

        // JS → iOS
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "ios.requestLocation":
                requestLocation()
            case "ios.log":
                print("[JS]", message.body)
            case "ios.shareKML":
                if let kml = message.body as? String { shareKML(kml) }
            case "switchToAR":
                if let arData = message.body as? [String: Any] {
                    handleARSwitch(arData: arData)
                }
            case "requestAddress":
                if let params = message.body as? [String: Any],
                   let lat = params["latitude"] as? Double,
                   let lng = params["longitude"] as? Double {
                    reverseGeocodeAddress(latitude: lat, longitude: lng)
                }
            default:
                break
            }
        }

        // Start/handle location
        private func requestLocation() {
            if #available(iOS 14.0, *) {
                switch loc.authorizationStatus {
                case .notDetermined:
                    askedAuth = true
                    loc.requestWhenInUseAuthorization()
                case .denied:
                    js("window.__iosLocationError && window.__iosLocationError('Location permission denied');")
                case .restricted:
                    js("window.__iosLocationError && window.__iosLocationError('Location restricted');")
                default:
                    loc.requestLocation()
                }
            } else {
                switch type(of: loc).authorizationStatus() {
                case .notDetermined:
                    askedAuth = true
                    loc.requestWhenInUseAuthorization()
                case .denied:
                    js("window.__iosLocationError && window.__iosLocationError('Location permission denied');")
                case .restricted:
                    js("window.__iosLocationError && window.__iosLocationError('Location restricted');")
                default:
                    loc.requestLocation()
                }
            }
        }

        // iOS 14+
        func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            guard #available(iOS 14.0, *) else { return }
            guard askedAuth else { return }
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                loc.requestLocation()
            case .denied:
                js("window.__iosLocationError && window.__iosLocationError('Location permission denied');")
            case .restricted:
                js("window.__iosLocationError && window.__iosLocationError('Location restricted');")
            default: break
            }
        }

        // iOS 13-
        func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
            if status == .authorizedAlways || status == .authorizedWhenInUse {
                loc.requestLocation()
            } else if status == .denied {
                js("window.__iosLocationError && window.__iosLocationError('Location permission denied');")
            } else if status == .restricted {
                js("window.__iosLocationError && window.__iosLocationError('Location restricted');")
            }
        }

        func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            guard let c = locations.last?.coordinate else {
                js("window.__iosLocationError && window.__iosLocationError('No location available');")
                return
            }
            js("window.__iosProvideLocation && window.__iosProvideLocation(\(c.latitude), \(c.longitude));")
        }

        func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
            let msg = (error.localizedDescription as NSString).replacingOccurrences(of: "'", with: "\\'")
            js("window.__iosLocationError && window.__iosLocationError('\(msg)');")
        }

        // WebView lifecycle
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            js("window.__iosReady && window.__iosReady();")
        }

        // Helpers
        private func js(_ code: String) {
            webView?.evaluateJavaScript(code, completionHandler: nil)
        }

        private func shareKML(_ kml: String) {
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("parcel.kml")
            do {
                try kml.data(using: .utf8)?.write(to: url, options: .atomic)
                let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                av.excludedActivityTypes = [.assignToContact, .addToReadingList, .saveToCameraRoll, .print]
                presentTop(av)
            } catch {
                let msg = (error.localizedDescription as NSString).replacingOccurrences(of: "'", with: "\\'")
                js("window.__iosLocationError && window.__iosLocationError('Share failed: \(msg)');")
            }
        }

        private func presentTop(_ vc: UIViewController) {
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return }
            var top = root
            while let p = top.presentedViewController { top = p }
            top.present(vc, animated: true)
        }

        // Reverse geocode address and send back to JavaScript
        private func reverseGeocodeAddress(latitude: Double, longitude: Double) {
            let location = CLLocation(latitude: latitude, longitude: longitude)
            let geocoder = CLGeocoder()
            
            geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    
                    if let error = error {
                        print("Reverse geocoding failed:", error.localizedDescription)
                        return
                    }
                    
                    guard let placemark = placemarks?.first else {
                        print("No placemark found for coordinates")
                        return
                    }
                    
                    // Build formatted address
                    var addressComponents: [String] = []
                    
                    if let streetNumber = placemark.subThoroughfare {
                        addressComponents.append(streetNumber)
                    }
                    if let streetName = placemark.thoroughfare {
                        addressComponents.append(streetName)
                    }
                    if let suburb = placemark.locality {
                        addressComponents.append(suburb)
                    }
                    if let postalCode = placemark.postalCode {
                        addressComponents.append(postalCode)
                    }
                    
                    let address = addressComponents.joined(separator: " ")
                    
                    // Send address back to JavaScript
                    if !address.isEmpty {
                        let escapedAddress = address.replacingOccurrences(of: "'", with: "\\'")
                        let js = "window.receiveAddress('\(escapedAddress)');"
                        self.webView?.evaluateJavaScript(js) { _, error in
                            if let error = error {
                                print("JavaScript execution error:", error.localizedDescription)
                            }
                        }
                    }
                }
            }
        }
        
        // Handle AR coordinates from web view
        private func handleARSwitch(arData: [String: Any]) {
            print("[INFO] Received AR data from web view")
            print("[DEBUG] AR data keys: \(arData.keys)")
            
            // The coordinates data is directly in arData["coordinates"]
            guard let coordinatesData = arData["coordinates"] as? [String: Any] else {
                print("[ERROR] Invalid AR coordinates data structure - missing coordinates key")
                print("[DEBUG] Available keys: \(arData.keys)")
                return
            }
            
            // Log the data type and structure for debugging
            if let dataType = coordinatesData["type"] as? String {
                print("[INFO] AR data type: \(dataType)")
            }
            
            if let metadata = coordinatesData["metadata"] as? [String: Any],
               let conversionMethod = metadata["conversionMethod"] as? String {
                print("[INFO] AR conversion method: \(conversionMethod)")
                
                if let boundaryPointCount = metadata["boundaryPointCount"] as? Int {
                    print("[INFO] Total boundary points: \(boundaryPointCount)")
                }
            }
            
            // Extract subject property boundaries from fullBoundaries structure
            if let subjectProperty = coordinatesData["subjectProperty"] as? [String: Any],
               let boundaries = subjectProperty["boundaries"] as? [[String: Any]],
               let appellation = subjectProperty["appellation"] as? String {
                
                print("[INFO] AR subject property: \(appellation) with \(boundaries.count) boundary points")
                
                // Extract neighbor properties
                if let neighborProperties = coordinatesData["neighborProperties"] as? [[String: Any]] {
                    print("[INFO] AR neighbor properties: \(neighborProperties.count)")
                }
                
                // Parse origin coordinates for AR positioning
                if let origin = coordinatesData["origin"] as? [String: Any],
                   let originLat = origin["latitude"] as? Double,
                   let originLon = origin["longitude"] as? Double {
                    print("[INFO] AR origin: \(originLat), \(originLon)")
                }
                
                // Switch to AR tab and pass the full boundary data
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("SwitchToARTab"), 
                        object: coordinatesData,
                        userInfo: [
                            "appellation": appellation,
                            "boundaryCount": boundaries.count
                        ]
                    )
                }
            } else {
                print("[ERROR] Failed to extract subject property boundaries from AR data")
                if let subjectProperty = coordinatesData["subjectProperty"] as? [String: Any] {
                    print("[DEBUG] Subject property keys: \(subjectProperty.keys)")
                }
            }
        }
    }
}
