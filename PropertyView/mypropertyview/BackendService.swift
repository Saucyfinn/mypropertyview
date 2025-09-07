import Foundation
import CoreLocation

/// Backend client for your Replit microservice.
/// It returns rings as arrays of CLLocationCoordinate2D (outer rings only),
/// and can also download a KML to a temporary file for sharing.
enum BackendService {
    /// ⬇️ SET THIS to your HTTPS Replit URL, e.g.
    /// https://linz-parcels-saucyfinn.replit.app  OR  https://...repl.co / .replit.dev
    static var API_BASE = URL(string: "https://parcel-service-Saucyfinn,replit.app")!

    private struct FeatureCollection: Decodable { let features: [Feature] }
    private struct Feature: Decodable { let geometry: Geometry }
    private struct Geometry: Decodable {
        let type: String
        let coordinates: Coordinates

        struct Coordinates: Decodable {
            let value: Any
            init(from decoder: Decoder) throws {
                let c = try decoder.singleValueContainer()
                if let v = try? c.decode([[[Double]]].self) { value = v; return }       // Polygon
                if let v = try? c.decode([[[[Double]]]].self) { value = v; return }     // MultiPolygon
                value = []
            }
        }
    }

    /// GeoJSON → rings
    static func parcelsByPoint(lon: Double, lat: Double, radiusM: Double = 150) async throws -> [[CLLocationCoordinate2D]] {
        var comps = URLComponents(url: API_BASE.appendingPathComponent("/api/parcels/by-point"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "lon", value: String(lon)),
            .init(name: "lat", value: String(lat)),
            .init(name: "radius_m", value: String(Int(radiusM)))
        ]
        guard let url = comps.url else { throw URLError(.badURL) }

        let (data, resp) = try await URLSession.shared.data(from: url)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        // Accept both your JSON envelope { rings:[ [ [lon,lat],... ] ] } OR raw GeoJSON FC
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let ringsRaw = obj["rings"] as? [[[Double]]] {
            return ringsRaw.map { $0.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) } }
        }

        // Fallback: decode FeatureCollection GeoJSON
        let fc = try JSONDecoder().decode(FeatureCollection.self, from: data)
        var rings: [[CLLocationCoordinate2D]] = []
        for f in fc.features {
            switch f.geometry.type {
            case "Polygon":
                if let poly = f.geometry.coordinates.value as? [[[Double]]],
                   let outer = poly.first {
                    rings.append(outer.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) })
                }
            case "MultiPolygon":
                if let mp = f.geometry.coordinates.value as? [[[[Double]]]] {
                    for poly in mp {
                        if let outer = poly.first {
                            rings.append(outer.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) })
                        }
                    }
                }
            default: break
            }
        }
        return rings
    }

    /// Downloads KML for the same point to a temp file and returns its URL (for share sheet).
    static func parcelsByPointKML(lon: Double, lat: Double, radiusM: Double = 150) async throws -> URL {
        var comps = URLComponents(url: API_BASE.appendingPathComponent("/api/parcels/by-point.kml"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "lon", value: String(lon)),
            .init(name: "lat", value: String(lat)),
            .init(name: "radius_m", value: String(Int(radiusM)))
        ]
        guard let url = comps.url else { throw URLError(.badURL) }

        let (data, resp) = try await URLSession.shared.data(from: url)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("parcel.kml")
        try? FileManager.default.removeItem(at: tmp)
        try data.write(to: tmp, options: .atomic)
        return tmp
    }
}

//  BackendService.swift
//  PropertyView
//
//  Created by Brendon Hogg on 28/08/2025.
//
