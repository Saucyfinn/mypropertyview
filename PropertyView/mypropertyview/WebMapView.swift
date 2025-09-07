import SwiftUI
import WebKit
import CoreLocation
import UIKit

struct WebMapView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let ucc = WKUserContentController()
        ucc.add(context.coordinator, name: "getParcels")     // JS -> Swift
        ucc.add(context.coordinator, name: "exportKML")      // JS -> Swift
        ucc.add(context.coordinator, name: "saveCoordinates") // JS -> Swift
        config.userContentController = ucc
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        context.coordinator.webView = web

        load(web, url: url)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        if web.url != url { load(web, url: url) }
    }

    private func load(_ web: WKWebView, url: URL) {
        if url.isFileURL {
            let dir = url.deletingLastPathComponent()
            web.loadFileURL(url, allowingReadAccessTo: dir)
        } else {
            let req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
            web.load(req)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        private let linzKey: String =
            (Bundle.main.object(forInfoDictionaryKey: "LINZ_API_KEY") as? String) ?? ""

        // JS -> Swift bridge
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "getParcels":
                guard let body = message.body as? [String: Any],
                      let lon = body["lon"] as? Double,
                      let lat = body["lat"] as? Double,
                      let radius = body["radius"] as? Double else { return }
                fetchParcels(lon: lon, lat: lat, radiusM: radius)

            case "exportKML":
                guard let dict = message.body as? [String: Any],
                      let base64 = dict["base64"] as? String,
                      let data = Data(base64Encoded: base64),
                      let filename = dict["filename"] as? String else { return }
                shareKML(data: data, suggestedName: filename)

            case "saveCoordinates":
                guard let coordinateData = message.body as? [String: Any] else { return }
                saveCoordinatesFile(coordinateData)

            default:
                break
            }
        }

        // Call LINZ WFS and send raw GeoJSON to JS as base64
        private func fetchParcels(lon: Double, lat: Double, radiusM: Double) {
            guard !linzKey.isEmpty else {
                print("LINZ_API_KEY missing from Info.plist")
                return
            }
            let dLat = radiusM / 111_320.0
            let dLon = radiusM / (111_320.0 * cos(lat * .pi/180.0))
            let minLon = lon - dLon, minLat = lat - dLat, maxLon = lon + dLon, maxLat = lat + dLat

            var comps = URLComponents(string: "https://data.linz.govt.nz/services;key=\(linzKey)/wfs")!
            comps.queryItems = [
                .init(name: "service", value: "WFS"),
                .init(name: "version", value: "2.0.0"),
                .init(name: "request", value: "GetFeature"),
                .init(name: "typeNames", value: "layer-50823"),
                .init(name: "outputFormat", value: "application/json"),
                .init(name: "srsName", value: "EPSG:4326"),
                .init(name: "bbox", value: "\(minLon),\(minLat),\(maxLon),\(maxLat),EPSG:4326"),
                .init(name: "count", value: "100")
            ]
            guard let url = comps.url else { return }

            URLSession.shared.dataTask(with: url) { [weak self] data, resp, err in
                guard let self = self, let web = self.webView else { return }
                guard err == nil, let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode), let data else {
                    print("LINZ fetch error:", err?.localizedDescription ?? "HTTP \( (resp as? HTTPURLResponse)?.statusCode ?? -1)")
                    return
                }
                let b64 = data.base64EncodedString()
                DispatchQueue.main.async {
                    web.evaluateJavaScript("window.renderParcelsFromBase64('\(b64)')", completionHandler: nil)
                }
            }.resume()
        }

        // Present share sheet (Google Earth, Files, etc.)
        private func shareKML(data: Data, suggestedName: String) {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(suggestedName)
            do { try data.write(to: url, options: .atomic) } catch {
                print("KML write failed:", error.localizedDescription); return
            }
            let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            av.excludedActivityTypes = [.assignToContact, .postToFacebook, .postToTwitter]
            presentTop(av)
        }

        // Save coordinates to app bundle Resources folder
        private func saveCoordinatesFile(_ coordinateData: [String: Any]) {
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: coordinateData, options: .prettyPrinted)
                guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                    print("Could not find Documents directory")
                    return
                }
                let coordinatesURL = documentsURL.appendingPathComponent("coordinates.json")
                try jsonData.write(to: coordinatesURL)
                print("Coordinates saved to:", coordinatesURL.path)

                // Notify AR system that new coordinates are available
                NotificationCenter.default.post(name: NSNotification.Name("coordinatesUpdated"), object: coordinateData)
            } catch {
                print("Failed to save coordinates:", error.localizedDescription)
            }
        }

        private func presentTop(_ vc: UIViewController) {
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return }
            var top = root
            while let presented = top.presentedViewController { top = presented }
            top.present(vc, animated: true)
        }

        // WKNavigationDelegate (optional logs)
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("Loaded:", webView.url?.absoluteString ?? "")
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("Web load failed:", error.localizedDescription)
        }
    }
}
