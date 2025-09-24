// GPSTab.swift
// PropertyView-Enhanced

import SwiftUI
import CoreLocation

/// Lightweight GPS tab that does not depend on AppState.
/// Shows current coordinates, accuracy, altitude, speed, and heading.
/// You can wire this to AppState later if needed.
struct GPSTab: View {
    @Binding var selectedTab: Int
    @StateObject private var loc = SimpleLocationManager()

    var body: some View {
        NavigationView {
            List {
                Section("Permission") {
                    HStack {
                        Text("Authorization")
                        Spacer()
                        Text(loc.authDescription)
                            .foregroundColor(.secondary)
                    }
                    Button("Request When-In-Use Permission") {
                        loc.requestAuthorization()
                    }
                }

                Section("Position") {
                    HStack {
                        Text("Latitude")
                        Spacer()
                        Text(loc.latitudeString)
                            .monospaced()
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Longitude")
                        Spacer()
                        Text(loc.longitudeString)
                            .monospaced()
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Horizontal Accuracy")
                        Spacer()
                        Text(loc.hAccuracyString)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Altitude")
                        Spacer()
                        Text(loc.altitudeString)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Speed")
                        Spacer()
                        Text(loc.speedString)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Course/Heading")
                        Spacer()
                        Text(loc.courseString)
                            .foregroundColor(.secondary)
                    }

                    Button("Get Current Location") {
                        loc.requestOneShot()
                    }
                }

                Section("Debug") {
                    HStack {
                        Text("Last Update")
                        Spacer()
                        Text(loc.lastUpdateString)
                            .foregroundColor(.secondary)
                    }
                    if let err = loc.lastError {
                        Text("Error: \(err.localizedDescription)")
                            .foregroundColor(.orange)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .navigationTitle("GPS")
        }
        .onAppear { loc.start() }
        .onDisappear { loc.stop() }
    }
}

// MARK: - SimpleLocationManager (ObservableObject)
@MainActor
final class SimpleLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    // Published state
    @Published var location: CLLocation?
    @Published var heading: CLHeading?
    @Published var status: CLAuthorizationStatus = .notDetermined
    @Published var lastError: Error?
    @Published var lastUpdate: Date?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 5
    }

    // Control
    func start() {
        if #available(iOS 14.0, *) {
            status = manager.authorizationStatus
        } else {
            status = type(of: manager).authorizationStatus()
        }
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.startUpdatingLocation()
            manager.startUpdatingHeading()
        }
    }

    func stop() {
        manager.stopUpdatingHeading()
        manager.stopUpdatingLocation()
    }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func requestOneShot() {
        manager.requestLocation()
    }

    // CLLocationManagerDelegate
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if #available(iOS 14.0, *) {
            status = manager.authorizationStatus
        } else {
            status = type(of: manager).authorizationStatus()
        }
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            start()
        } else {
            stop()
        }
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        // iOS 13-
        self.status = status
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            start()
        } else {
            stop()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastError = nil
        if let loc = locations.last {
            location = loc
            lastUpdate = Date()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        heading = newHeading
        lastUpdate = Date()
    }

    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        true
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        lastError = error
        lastUpdate = Date()
    }

    // MARK: - Display helpers
    var authDescription: String {
        switch status {
        case .authorizedAlways: return "Authorized Always"
        case .authorizedWhenInUse: return "Authorized When In Use"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not Determined"
        @unknown default: return "Unknown"
        }
    }

    var latitudeString: String {
        guard let c = location?.coordinate else { return "—" }
        return String(format: "%.6f°", c.latitude)
    }

    var longitudeString: String {
        guard let c = location?.coordinate else { return "—" }
        return String(format: "%.6f°", c.longitude)
    }

    var hAccuracyString: String {
        guard let a = location?.horizontalAccuracy, a >= 0 else { return "—" }
        return String(format: "±%.0f m", a)
    }

    var altitudeString: String {
        guard let alt = location?.altitude else { return "—" }
        return String(format: "%.1f m", alt)
    }

    var speedString: String {
        guard let s = location?.speed, s >= 0 else { return "—" }
        return String(format: "%.1f m/s", s)
    }

    var courseString: String {
        if let h = heading?.trueHeading, h >= 0 {
            return String(format: "Heading %.0f°", h)
        }
        if let c = location?.course, c >= 0 {
            return String(format: "Course %.0f°", c)
        }
        return "—"
    }

    var lastUpdateString: String {
        guard let t = lastUpdate else { return "—" }
        let f = DateFormatter()
        f.timeStyle = .medium
        f.dateStyle = .none
        return f.string(from: t)
    }
}

// MARK: - Preview
#Preview {
    GPSTab(selectedTab: .constant(2))
}
