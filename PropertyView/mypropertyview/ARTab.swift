import SwiftUI
import CoreLocation
import ARKit
import UIKit

struct ARTab: View {
    @Binding var selection: Int

    @State private var origin: CLLocation?
    @State private var status: String = "Starting…"
    @State private var rings: [[CLLocationCoordinate2D]] = []
    @State private var didAutoFetch = false

    @State private var bootstrap: ARBootstrap?
    @State private var savedCoordinates: [[CLLocationCoordinate2D]] = []

    // Share sheet
    @State private var shareURL: URL?
    @State private var showShare = false

    @ViewBuilder
    private var coreARView: some View {
        if ARWorldTrackingConfiguration.isSupported {
            if #available(iOS 17.0, *) {
                ARKMLViewContainer(
                    kmlRings: $savedCoordinates,
                    userLocation: $origin,
                    showRings: .constant(true),
                    status: $status
                )
                .ignoresSafeArea()
                .onAppear {
                    if bootstrap == nil {
                        bootstrap = ARBootstrap(
                            onStatus: { self.status = $0 },
                            onResult: { _, o in self.origin = o }
                        )
                        bootstrap?.start()
                    }
                    loadSavedCoordinates()
                    setupCoordinateListener()
                }
                // Load coordinates when they're updated from web
                .onChange(of: origin) { _, newLoc in
                    guard !didAutoFetch, newLoc != nil else { return }
                    didAutoFetch = true
                    loadSavedCoordinates() // Try to load saved coordinates first
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                    Text("AR not supported on this device.")
                    Text("Run on a physical iPhone that supports ARKit.")
                        .foregroundColor(.secondary).font(.footnote)
                }
                .padding()
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                Text("AR not supported on this device.")
                Text("Run on a physical iPhone that supports ARKit.")
                    .foregroundColor(.secondary).font(.footnote)
            }
            .padding()
        }
    }

    var body: some View {
        coreARView
            .navigationTitle("AR")
            // Top bar
            .overlay(alignment: .top) {
                HStack {
                    Button { selection = 0 } label: { Label("Map", systemImage: "map").padding(8) }
                        .buttonStyle(.borderedProminent)
                    Spacer()
                    Text(status)
                        .font(.footnote).padding(8)
                        .background(.ultraThinMaterial).cornerRadius(10)
                }
                .padding()
            }
            // Bottom bar: Refresh + Export KML
            .overlay(alignment: .bottom) {
                HStack(spacing: 12) {
                    Button(action: getParcelsFromBackend) {
                        Label("Refresh parcel", systemImage: "globe")
                    }
                    .buttonStyle(.borderedProminent)

                    Button(action: exportKML) {
                        Label("Export KML", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .disabled(origin == nil)
                }
                .padding(.bottom, 16)
            }
            .sheet(isPresented: $showShare) {
                if let url = shareURL {
                    ShareSheet(items: [url])
                }
            }
    }

    // MARK: - Actions

    private func getParcelsFromBackend() {
        guard let o = origin else {
            status = "Waiting for location…"
            return
        }
        status = "Fetching parcel…"
        Task {
            do {
                let out = try await BackendService.parcelsByPoint(
                    lon: o.coordinate.longitude,
                    lat: o.coordinate.latitude,
                    radiusM: 150
                )
                await MainActor.run {
                    if out.isEmpty {
                        status = "No parcel found here"
                    } else {
                        rings = out
                        status = "Loaded \(out.count) ring(s)"
                    }
                }
            } catch {
                await MainActor.run {
                    status = "Fetch failed: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Coordinate Management

    private func loadSavedCoordinates() {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("Could not find Documents directory")
            return
        }
        let coordinatesURL = documentsURL.appendingPathComponent("coordinates.json")

        do {
            let data = try Data(contentsOf: coordinatesURL)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

            if let subjectProperty = json?["subject_property"] as? [String: Any],
               let coordinates = subjectProperty["coordinates"] as? [[String: Double]] {

                let coords = coordinates.compactMap { coord -> CLLocationCoordinate2D? in
                    guard let lat = coord["latitude"], let lon = coord["longitude"] else { return nil }
                    return CLLocationCoordinate2D(latitude: lat, longitude: lon)
                }

                if !coords.isEmpty {
                    savedCoordinates = [coords]
                    status = "Loaded saved property boundaries (\(coords.count) points)"
                    print("Loaded \(coords.count) boundary coordinates from web selection")
                    print("First coordinate: \(coords.first!)")
                    print("Last coordinate: \(coords.last!)")
                }
            }
        } catch {
            print("Failed to load saved coordinates:", error.localizedDescription)
        }
    }

    private func setupCoordinateListener() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("coordinatesUpdated"),
            object: nil,
            queue: .main
        ) { notification in
            if let coordinateData = notification.object as? [String: Any] {
                self.processNewCoordinates(coordinateData)
            }
        }
    }

    private func processNewCoordinates(_ coordinateData: [String: Any]) {
        guard let subjectProperty = coordinateData["subject_property"] as? [String: Any],
              let coordinates = subjectProperty["coordinates"] as? [[String: Double]] else {
            return
        }

        let coords = coordinates.compactMap { coord -> CLLocationCoordinate2D? in
            guard let lat = coord["latitude"], let lon = coord["longitude"] else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }

        if !coords.isEmpty {
            savedCoordinates = [coords]
            if let appellation = subjectProperty["appellation"] as? String {
                status = "AR ready: \(appellation) (\(coords.count) points)"
            } else {
                status = "AR ready with property boundaries (\(coords.count) points)"
            }
            print("Updated AR with \(coords.count) boundary coordinates from web")
            print("Coordinates range: \(coords.first!) to \(coords.last!)")
        }
    }

    private func exportKML() {
        guard let o = origin else { return }
        status = "Preparing KML…"
        Task {
            do {
                let url = try await BackendService.parcelsByPointKML(
                    lon: o.coordinate.longitude,
                    lat: o.coordinate.latitude,
                    radiusM: 150
                )
                await MainActor.run {
                    self.shareURL = url
                    self.showShare = true
                    self.status = "KML ready"
                }
            } catch {
                await MainActor.run {
                    self.status = "KML export failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

// Simple ShareSheet for KML export
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
