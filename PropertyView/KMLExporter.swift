import Foundation
import CoreLocation
import UniformTypeIdentifiers

struct KMLImporter {
    /// Parse first polygon outer rings from a KML file.
    static func parse(data: Data) -> [[CLLocationCoordinate2D]] {
        // very lightweight extraction of <coordinates>...</coordinates>
        guard let xml = String(data: data, encoding: .utf8) else { return [] }
        var rings: [[CLLocationCoordinate2D]] = []

        // Grab all <coordinates> ... </coordinates> blocks
        let pattern = #"<coordinates>([\s\S]*?)</coordinates>"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let ns = xml as NSString
        let matches = regex?.matches(in: xml, range: NSRange(location: 0, length: ns.length)) ?? []

        for m in matches {
            let r = m.range(at: 1)
            if r.location == NSNotFound { continue }
            let coordsText = ns.substring(with: r)
            var ring: [CLLocationCoordinate2D] = []
            // Coordinates are "lon,lat[,alt]" separated by spaces/newlines
            for token in coordsText.split(whereSeparator: { $0.isWhitespace }) {
                let parts = token.split(separator: ",")
                if parts.count >= 2,
                   let lon = Double(parts[0]),
                   let lat = Double(parts[1]) {
                    ring.append(.init(latitude: lat, longitude: lon))
                }
            }
            if ring.count >= 3 { rings.append(ring) }
        }
        return rings
    }
}
