import WebKit
import CoreLocation
import UIKit

final class WebViewLocationBridge: NSObject, WKScriptMessageHandler, CLLocationManagerDelegate {
    private weak var webView: WKWebView?
    private let manager = CLLocationManager()
    private var askedAuth = false

    static func install(on webView: WKWebView) {
        let bridge = WebViewLocationBridge(webView)
        // retain the bridge for the lifetime of the webView
        objc_setAssociatedObject(webView, Unmanaged.passUnretained(bridge).toOpaque(), bridge, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    private init(_ webView: WKWebView) {
        super.init()
        self.webView = webView
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        webView.configuration.userContentController.add(self, name: "ios.requestLocation")
    }

    // JS → native
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "ios.requestLocation" else { return }
        if #available(iOS 14.0, *) {
            switch manager.authorizationStatus {
            case .notDetermined:
                askedAuth = true
                manager.requestWhenInUseAuthorization()
            case .denied:
                js("window.__iosLocationError && window.__iosLocationError('Location permission denied');")
            case .restricted:
                js("window.__iosLocationError && window.__iosLocationError('Location restricted');")
            default:
                manager.requestLocation()
            }
        } else {
            type(of: manager).authorizationStatus() == .notDetermined ? manager.requestWhenInUseAuthorization() : manager.requestLocation()
        }
    }

    // Native → JS
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let c = locations.first?.coordinate else {
            js("window.__iosLocationError && window.__iosLocationError('No location');"); return
        }
        js("window.__iosProvideLocation && window.__iosProvideLocation(\(c.latitude), \(c.longitude));")
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let msg = (error.localizedDescription as NSString).replacingOccurrences(of: "'", with: "\\'")
        js("window.__iosLocationError && window.__iosLocationError('\(msg)');")
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if #available(iOS 14.0, *), (manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways),
           askedAuth {
            self.manager.requestLocation()
        }
    }

    private func js(_ script: String) { webView?.evaluateJavaScript(script, completionHandler: nil) }
}

//  WebViewLocationBridge.swift
//  PropertyView-Enhanced
//
//  Created by Brendon Hogg on 16/09/2025.
//

