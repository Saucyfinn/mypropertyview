//import CoreLocation

struct SubjectProperty: Identifiable {
    let id = UUID()
    let appellation: String
    let arPoints: [CLLocationCoordinate2D]
    let area: Double
}

struct ARCoordinateData {
    let subjectProperty: SubjectProperty
    let neighborProperties: [SubjectProperty]
}
//  Models.swift
//  PropertyView-Enhanced
//
//  Created by Brendon Hogg on 20/09/2025.
//

