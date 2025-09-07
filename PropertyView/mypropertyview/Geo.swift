import Foundation
import CoreLocation
import simd

struct Geo {
    /// Convert GPS coordinate to ENU (East-North-Up) meters relative to origin
    /// Uses simplified but accurate conversion for AR positioning
    static func enu(from origin: CLLocationCoordinate2D, to p: CLLocationCoordinate2D) -> SIMD3<Float> {
        let latRad = origin.latitude * .pi/180
        let mPerDegLat = 111_132.0
        let mPerDegLon = 111_320.0 * cos(latRad)
        let dLat = p.latitude  - origin.latitude
        let dLon = p.longitude - origin.longitude
        let north = dLat * mPerDegLat
        let east  = dLon * mPerDegLon
        return SIMD3<Float>(Float(east), 0, Float(-north))  // x=east, y=up, z=south(-north)
    }

    /// Legacy function for backward compatibility
    static func enuDelta(from origin: CLLocation, to target: CLLocationCoordinate2D) -> (x: Double, y: Double) {
        let result = enu(from: origin.coordinate, to: target)
        return (x: Double(result.x), y: Double(-result.z)) // Convert back to north-positive
    }

    /// Legacy function for backward compatibility
    static func enuDelta(from origin: CLLocationCoordinate2D, to target: CLLocationCoordinate2D) -> (x: Double, y: Double) {
        let result = enu(from: origin, to: target)
        return (x: Double(result.x), y: Double(-result.z)) // Convert back to north-positive
    }
}
