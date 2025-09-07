import CoreLocation

/// Returns true if two coordinates are within `meters` of each other.
@inline(__always)
func coordinatesEqual(_ a: CLLocationCoordinate2D,
                      _ b: CLLocationCoordinate2D,
                      within meters: CLLocationDistance = 1.0) -> Bool {
    let la = CLLocation(latitude: a.latitude, longitude: a.longitude)
    let lb = CLLocation(latitude: b.latitude, longitude: b.longitude)
    return la.distance(from: lb) <= meters
}

//  CoordinateCompare.swift
//  PropertyView
//
//  Created by Brendon Hogg on 07/09/2025.
//

