// CompatLayer.swift
// Minimal legacy shim so older references don't break the build.
// If you still need legacy behavior, wire it through NotificationCenter instead of AppState.

import Foundation
import CoreLocation
import SwiftUI

// MARK: - Legacy notifications (optional)
extension Notification.Name {
    /// Post when you want AR to refresh (legacy "forceARUpdate()")
    static let ForceARUpdate = Notification.Name("ForceARUpdate")
    /// Post when coordinates have been updated (legacy "updateCoordinates")
    static let CoordinatesUpdated = Notification.Name("CoordinatesUpdated")
}

// MARK: - Legacy helpers (safe stubs)

// If some old code calls a global `centroid(rings:)`, keep a safe stub here.
// Prefer using SubjectProperty.centroid in new code.
@inline(__always)
public func centroid(rings: [[CLLocationCoordinate2D]]) -> CLLocationCoordinate2D {
    guard let outer = rings.first, !outer.isEmpty else {
        return CLLocationCoordinate2D(latitude: 0, longitude: 0)
    }
    let sum = outer.reduce(into: (lat: 0.0, lon: 0.0)) { acc, c in
        acc.lat += c.latitude; acc.lon += c.longitude
    }
    let n = Double(outer.count)
    return .init(latitude: sum.lat / n, longitude: sum.lon / n)
}

// Distance helper for convenience if older code used it.
@inline(__always)
public func distance(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> CLLocationDistance {
    CLLocation(latitude: a.latitude, longitude: a.longitude)
        .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
}

// MARK: - DO NOT DEFINE AppState OR MODEL DUPLICATES HERE
// This file must not declare SubjectProperty, ARCoordinateData, ARPoint, etc.
// Keep this file minimal to avoid "Invalid redeclaration" errors.
