import CoreLocation
import simd

enum Geo {
    // WGS84 ellipsoid
    private static let a = 6378137.0
    private static let f = 1.0 / 298.257223563
    private static let b = a * (1 - f)
    private static let e2 = 1 - (b*b)/(a*a)

    private static func ecef(from cl: CLLocation) -> SIMD3<Double> {
        let lat = cl.coordinate.latitude * .pi / 180
        let lon = cl.coordinate.longitude * .pi / 180
        let h = cl.altitude
        let sinLat = sin(lat), cosLat = cos(lat)
        let sinLon = sin(lon), cosLon = cos(lon)
        let N = a / sqrt(1 - e2 * sinLat * sinLat)
        let x = (N + h) * cosLat * cosLon
        let y = (N + h) * cosLat * sinLon
        let z = (N * (1 - e2) + h) * sinLat
        return .init(x, y, z)
    }

    /// ENU delta (east, north) from `origin` to `coord` in meters.
    static func enuDelta(from origin: CLLocation, to coord: CLLocationCoordinate2D) -> (x: Double, y: Double) {
        // Build a CLLocation for the target using the origin altitude (flatten AR to ground later)
        let t = CLLocation(
            coordinate: coord,
            altitude: origin.altitude,
            horizontalAccuracy: 1.0,
            verticalAccuracy: 1.0,
            timestamp: Date()
        )

        let oECEF = ecef(from: origin)
        let pECEF = ecef(from: t)
        let d = pECEF - oECEF

        let lat = origin.coordinate.latitude * .pi / 180
        let lon = origin.coordinate.longitude * .pi / 180
        let sinLat = sin(lat), cosLat = cos(lat)
        let sinLon = sin(lon), cosLon = cos(lon)

        let east  = -sinLon * d.x +  cosLon * d.y
        let north = -sinLat * cosLon * d.x - sinLat * sinLon * d.y + cosLat * d.z
        return (east, north)
    }
}
