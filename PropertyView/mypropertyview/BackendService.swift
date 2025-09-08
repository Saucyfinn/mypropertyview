import Foundation
import CoreLocation

// MARK: - Public service

/// Simple client that fetches boundary rings (GeoJSON → [[CLLocationCoordinate2D]]).
final class BackendService {

    static let shared = BackendService()

    /// Base URL of your backend. Update this to your actual host.
    /// Example: https://your-host.example.com
    private let apiBaseURL: URL
    private let urlSession: URLSession

    init(apiBaseURL: URL = URL(string: "https://example.invalid")!,
         urlSession: URLSession = .shared) {
        self.apiBaseURL = apiBaseURL
        self.urlSession = urlSession
    }

    // MARK: - Fetch (adjust to match your backend)

    /// Fetch rings for a map center + radius (customize query to match your API).
    func fetchRings(center: CLLocationCoordinate2D,
                    radiusMeters: Double = 200,
                    completion: @escaping (Result<[[CLLocationCoordinate2D]], Error>) -> Void) {
        do {
            let url = try buildRingsURL(center: center, radiusMeters: radiusMeters)
            fetchRings(from: url, completion: completion)
        } catch {
            completion(.failure(error))
        }
    }

    /// Fetch rings from a fully-formed URL (handy for testing).
    func fetchRings(from url: URL,
                    completion: @escaping (Result<[[CLLocationCoordinate2D]], Error>) -> Void) {

        let task = urlSession.dataTask(with: url) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                completion(.failure(BackendError.httpStatus(http.statusCode)))
                return
            }
            guard let data else {
                completion(.failure(BackendError.emptyResponse))
                return
            }

            do {
                let rings = try GeoJSONDecoder.decodeRings(from: data)
                completion(.success(rings))
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }

    // MARK: - URL builder (edit to match your server routes & params)

    /// Build the request URL to your backend. Change path/params to your API.
    private func buildRingsURL(center: CLLocationCoordinate2D,
                               radiusMeters: Double) throws -> URL {
        // Example endpoint:  GET /api/rings?lat=..&lon=..&radius=..
        var components = URLComponents(url: apiBaseURL, resolvingAgainstBaseURL: false)
        components?.path = "/api/rings"
        components?.queryItems = [
            .init(name: "lat", value: String(center.latitude)),
            .init(name: "lon", value: String(center.longitude)),
            .init(name: "radius", value: String(radiusMeters))
        ]
        guard let url = components?.url else { throw BackendError.invalidURL }
        return url
    }
}

// MARK: - Errors

enum BackendError: Error, LocalizedError {
    case invalidURL
    case httpStatus(Int)
    case emptyResponse
    case badGeoJSON

    var errorDescription: String? {
        switch self {
        case .invalidURL:        return "Invalid URL."
        case .httpStatus(let s): return "Server returned HTTP \(s)."
        case .emptyResponse:     return "The server returned no data."
        case .badGeoJSON:        return "Unexpected GeoJSON shape."
        }
    }
}

// MARK: - Namespaced GeoJSON models (avoid collisions with other files)

enum BackendGeoJSON {
    struct FeatureCollection: Decodable {
        let features: [Feature]
    }

    struct Feature: Decodable {
        let geometry: Geometry
    }

    struct Geometry: Decodable {
        let type: String
        let coordinates: Coordinates
    }

    /// Supports Polygon and MultiPolygon coordinate nesting.
    enum Coordinates: Decodable {
        case polygon([[[Double]]])        // [ring][point][lon/lat]
        case multiPolygon([[[[Double]]]]) // [poly][ring][point][lon/lat]

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()

            // Try MultiPolygon (depth 4)
            if let multi = try? container.decode([[[[Double]]]].self) {
                self = .multiPolygon(multi)
                return
            }
            // Try Polygon (depth 3)
            if let poly = try? container.decode([[[Double]]].self) {
                self = .polygon(poly)
                return
            }
            throw BackendError.badGeoJSON
        }
    }
}

// MARK: - GeoJSON → rings decoder

private enum GeoJSONDecoder {

    static func decodeRings(from data: Data) throws -> [[CLLocationCoordinate2D]] {
        let decoder = JSONDecoder()

        if let collection = try? decoder.decode(BackendGeoJSON.FeatureCollection.self, from: data) {
            return flatten(collection: collection)
        }

        if let single = try? decoder.decode(BackendGeoJSON.Feature.self, from: data) {
            return flatten(feature: single)
        }

        throw BackendError.badGeoJSON
    }

    private static func flatten(collection: BackendGeoJSON.FeatureCollection) -> [[CLLocationCoordinate2D]] {
        collection.features.flatMap { flatten(feature: $0) }
    }

    private static func flatten(feature: BackendGeoJSON.Feature) -> [[CLLocationCoordinate2D]] {
        switch feature.geometry.coordinates {
        case .polygon(let rings3d):
            return rings3d.compactMap(ring(from:))
        case .multiPolygon(let polys4d):
            return polys4d.flatMap { poly in
                poly.compactMap(ring(from:))
            }
        }
    }

    /// Convert a GeoJSON ring ([[lon, lat], …]) to CLLocationCoordinate2D[].
    private static func ring(from rawRing: [[Double]]) -> [CLLocationCoordinate2D]? {
        guard !rawRing.isEmpty else { return nil }
        var coords: [CLLocationCoordinate2D] = []
        coords.reserveCapacity(rawRing.count)

        for point in rawRing {
            guard point.count >= 2 else { continue }
            let lon = point[0]
            let lat = point[1]
            coords.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }

        // Remove duplicate closing coordinate if present
        if let first = coords.first, let last = coords.last,
           first.latitude == last.latitude && first.longitude == last.longitude {
            _ = coords.popLast()
        }
        return coords
    }
}

