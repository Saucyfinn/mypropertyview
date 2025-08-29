import Foundation
import CoreLocation

/// Direct LINZ (LDS) WFS client returning GeoJSON polygons as coordinate rings.
/// Layer: 50823 (NZ Primary Land Parcels)
enum LDSService {
    // 🔑 Your LINZ API key
    static let API_KEY = "de04650882284851be0e406906a0914b"

    // Base WFS endpoint – key goes in the path segment per LDS format.
    private static var base: URL {
        URL(string: "https://data.linz.govt.nz/services;key=\(API_KEY)/wfs")!
    }

    /// Fetch parcel rings near a point using a small BBOX (degrees), output GeoJSON.
    /// Returns outer rings only (WGS84 / EPSG:4326).
    static func fetchParcelsNear(lon: Double, lat: Double, radiusM: Double = 120) async throws -> [[CLLocationCoordinate2D]] {
        // Convert meters to degrees (approx)
        let dLat = radiusM / 111_320.0
        let dLon = radiusM / (cos(lat * .pi / 180.0) * 111_320.0)
        let minLon = lon - dLon, maxLon = lon + dLon
        let minLat = lat - dLat, maxLat = lat + dLat

        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "service", value: "WFS"),
            .init(name: "version", value: "2.0.0"),
            .init(name: "request", value: "GetFeature"),
            .init(name: "typeNames", value: "layer-50823"),
            .init(name: "srsName", value: "EPSG:4326"),
            .init(name: "bbox", value: "\(minLon),\(minLat),\(maxLon),\(maxLat),EPSG:4326"),
            .init(name: "outputFormat", value: "application/json")
        ]
        guard let url = comps.url else { throw URLError(.badURL) }

        let (data, resp) = try await URLSession.shared.data(from: url)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        guard let rings = try decodeRings(fromGeoJSON: data) else {
            throw URLError(.cannotParseResponse)
        }
        return rings
    }

    // MARK: - Minimal GeoJSON decoding

    private struct FC: Decodable { let features: [Feature] }
    private struct Feature: Decodable { let geometry: Geometry }

    private struct Geometry: Decodable {
        let type: String
        let coordinates: LDSAnyDecodable
    }

    /// Avoid name clashes with any other AnyDecodable in your project.
    private struct LDSAnyDecodable: Decodable {
        let value: Any
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let v = try? c.decode([[[Double]]].self) { value = v; return }       // Polygon
            if let v = try? c.decode([[[[Double]]]].self) { value = v; return }     // MultiPolygon
            value = []
        }
    }

    /// Returns outer rings only as [CLLocationCoordinate2D].
    private static func decodeRings(fromGeoJSON data: Data) throws -> [[CLLocationCoordinate2D]]? {
        let fc = try JSONDecoder().decode(FC.self, from: data)
        var out: [[CLLocationCoordinate2D]] = []

        for f in fc.features {
            switch f.geometry.type {
            case "Polygon":
                if let poly = f.geometry.coordinates.value as? [[[Double]]],
                   let outer = poly.first {
                    out.append(outer.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) })
                }
            case "MultiPolygon":
                if let mp = f.geometry.coordinates.value as? [[[[Double]]]] {
                    for poly in mp {
                        if let outer = poly.first {
                            out.append(outer.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) })
                        }
                    }
                }
            default:
                continue
            }
        }
        return out
    }
}
