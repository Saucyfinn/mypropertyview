import Foundation
import CoreLocation

struct FeatureCollection: Decodable { let features: [Feature] }
struct Feature: Decodable { let geometry: Geometry }

struct Geometry: Decodable {
    let type: String
    let coordinates: AnyDecodable

    /// Returns outer rings as [CLLocationCoordinate2D] (lon,lat -> lat,lon)
    func rings() -> [[CLLocationCoordinate2D]] {
        switch type {
        case "Polygon":
            guard let arr = coordinates.value as? [[[Double]]] else { return [] }
            return arr.map { ring in
                ring.compactMap { coord in
                    guard coord.count >= 2 else { return nil }
                    return .init(latitude: coord[1], longitude: coord[0])
                }
            }
        case "MultiPolygon":
            guard let arr = coordinates.value as? [[[[Double]]]] else { return [] }
            return arr.flatMap { poly in
                poly.map { ring in
                    ring.compactMap { coord in
                        guard coord.count >= 2 else { return nil }
                        return .init(latitude: coord[1], longitude: coord[0])
                    }
                }
            }
        default:
            return []
        }
    }
}

/// Tiny type-erased decoder for Polygon/MultiPolygon coordinate arrays.
struct AnyDecodable: Decodable {
    let value: Any
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode([[[[Double]]]].self) { value = v; return } // MultiPolygon
        if let v = try? c.decode([[[Double]]].self)  { value = v; return }   // Polygon
        value = []
    }
}


