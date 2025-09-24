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
    }
}
