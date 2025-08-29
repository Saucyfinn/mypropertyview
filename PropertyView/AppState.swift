import Foundation
import CoreLocation

final class AppState: ObservableObject {
    func bundledWebURL(with origin: CLLocation?) -> URL {
        // Try Web/index.html (blue folder), then root/index.html (yellow group)
        let url: URL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Web")
            ?? Bundle.main.url(forResource: "index", withExtension: "html")
            ?? { preconditionFailure("index.html not found in app bundle") }()

        if let o = origin {
            var c = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            c.queryItems = [
                .init(name: "lat", value: String(o.coordinate.latitude)),
                .init(name: "lng", value: String(o.coordinate.longitude)),
                .init(name: "z",   value: "17")
            ]
            return c.url!
        }
        return url
    }
}


