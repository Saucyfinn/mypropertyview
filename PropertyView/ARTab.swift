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

    // Share sheet
    @State private var shareURL: URL?
    @State private var showShare = false

    @ViewBuilder
    private var coreARView: some View {
        if ARWorldTrackingConfiguration.isSupported {
            if #available(iOS 17.0, *) {
                ARKMLViewContainer(
                    rings: .constant([]),
                    origin: $origin,
                    status: $status,
                    showNeighbours: .constant(false),
                    showCorners: .constant(false),
                    guidanceActive: .constant(false),
                    yawDegrees: .constant(0),
                    offsetE: .constant(0),
                    offsetN: .constant(0),
                    setAID: .constant(0),
                    setBID: .constant(0),
                    solveID: .constant(0),
                    kmlRings: $rings,               // 🔵 AR renders these
                    showKML: .constant(true),
                    useKMLAsSubject: .constant(true)
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
                }
                // Auto-fetch once when we get a location
                .onChange(of: origin) { _, newLoc in
                    guard !didAutoFetch, newLoc != nil else { return }
                    didAutoFetch = true
                    getParcelsFromBackend()
                }
            } else {
                // Fallback on earlier versions
            };if #available(iOS 17.0, *) {
                ARKMLViewContainer(
                    rings: .constant([]),
                    origin: $origin,
                    status: $status,
                    showNeighbours: .constant(false),
                    showCorners: .constant(false),
                    guidanceActive: .constant(false),
                    yawDegrees: .constant(0),
                    offsetE: .constant(0),
                    offsetN: .constant(0),
                    setAID: .constant(0),
                    setBID: .constant(0),
                    solveID: .constant(0),
                    kmlRings: $rings,               // 🔵 AR renders these
                    showKML: .constant(true),
                    useKMLAsSubject: .constant(true)
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
                }
                // Auto-fetch once when we get a location
                .onChange(of: origin) { _, newLoc in
                    guard !didAutoFetch, newLoc != nil else { return }
                    didAutoFetch = true
                    getParcelsFromBackend()
                }
            } else {
                // Fallback on earlier versions
            };if #available(iOS 17.0, *) {
                ARKMLViewContainer(
                    rings: .constant([]),
                    origin: $origin,
                    status: $status,
                    showNeighbours: .constant(false),
                    showCorners: .constant(false),
                    guidanceActive: .constant(false),
                    yawDegrees: .constant(0),
                    offsetE: .constant(0),
                    offsetN: .constant(0),
                    setAID: .constant(0),
                    setBID: .constant(0),
                    solveID: .constant(0),
                    kmlRings: $rings,               // 🔵 AR renders these
                    showKML: .constant(true),
                    useKMLAsSubject: .constant(true)
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
                }
                // Auto-fetch once when we get a location
                .onChange(of: origin) { _, newLoc in
                    guard !didAutoFetch, newLoc != nil else { return }
                    didAutoFetch = true
                    getParcelsFromBackend()
                }
            } else {
                // Fallback on earlier versions
            };if #available(iOS 17.0, *) {
                ARKMLViewContainer(
                    rings: .constant([]),
                    origin: $origin,
                    status: $status,
                    showNeighbours: .constant(false),
                    showCorners: .constant(false),
                    guidanceActive: .constant(false),
                    yawDegrees: .constant(0),
                    offsetE: .constant(0),
                    offsetN: .constant(0),
                    setAID: .constant(0),
                    setBID: .constant(0),
                    solveID: .constant(0),
                    kmlRings: $rings,               // 🔵 AR renders these
                    showKML: .constant(true),
                    useKMLAsSubject: .constant(true)
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
                }
                // Auto-fetch once when we get a location
                .onChange(of: origin) { _, newLoc in
                    guard !didAutoFetch, newLoc != nil else { return }
                    didAutoFetch = true
                    getParcelsFromBackend()
                }
            } else {
                // Fallback on earlier versions
            };if #available(iOS 17.0, *) {
                ARKMLViewContainer(
                    rings: .constant([]),
                    origin: $origin,
                    status: $status,
                    showNeighbours: .constant(false),
                    showCorners: .constant(false),
                    guidanceActive: .constant(false),
                    yawDegrees: .constant(0),
                    offsetE: .constant(0),
                    offsetN: .constant(0),
                    setAID: .constant(0),
                    setBID: .constant(0),
                    solveID: .constant(0),
                    kmlRings: $rings,               // 🔵 AR renders these
                    showKML: .constant(true),
                    useKMLAsSubject: .constant(true)
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
                }
                // Auto-fetch once when we get a location
                .onChange(of: origin) { _, newLoc in
                    guard !didAutoFetch, newLoc != nil else { return }
                    didAutoFetch = true
                    getParcelsFromBackend()
                }
            } else {
                // Fallback on earlier versions
            };if #available(iOS 17.0, *) {
                ARKMLViewContainer(
                    rings: .constant([]),
                    origin: $origin,
                    status: $status,
                    showNeighbours: .constant(false),
                    showCorners: .constant(false),
                    guidanceActive: .constant(false),
                    yawDegrees: .constant(0),
                    offsetE: .constant(0),
                    offsetN: .constant(0),
                    setAID: .constant(0),
                    setBID: .constant(0),
                    solveID: .constant(0),
                    kmlRings: $rings,               // 🔵 AR renders these
                    showKML: .constant(true),
                    useKMLAsSubject: .constant(true)
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
                }
                // Auto-fetch once when we get a location
                .onChange(of: origin) { _, newLoc in
                    guard !didAutoFetch, newLoc != nil else { return }
                    didAutoFetch = true
                    getParcelsFromBackend()
                }
            } else {
                // Fallback on earlier versions
            };if #available(iOS 17.0, *) {
                ARKMLViewContainer(
                    rings: .constant([]),
                    origin: $origin,
                    status: $status,
                    showNeighbours: .constant(false),
                    showCorners: .constant(false),
                    guidanceActive: .constant(false),
                    yawDegrees: .constant(0),
                    offsetE: .constant(0),
                    offsetN: .constant(0),
                    setAID: .constant(0),
                    setBID: .constant(0),
                    solveID: .constant(0),
                    kmlRings: $rings,               // 🔵 AR renders these
                    showKML: .constant(true),
                    useKMLAsSubject: .constant(true)
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
                }
                // Auto-fetch once when we get a location
                .onChange(of: origin) { _, newLoc in
                    guard !didAutoFetch, newLoc != nil else { return }
                    didAutoFetch = true
                    getParcelsFromBackend()
                }
            } else {
                // Fallback on earlier versions
            };if #available(iOS 17.0, *) {
                ARKMLViewContainer(
                    rings: .constant([]),
                    origin: $origin,
                    status: $status,
                    showNeighbours: .constant(false),
                    showCorners: .constant(false),
                    guidanceActive: .constant(false),
                    yawDegrees: .constant(0),
                    offsetE: .constant(0),
                    offsetN: .constant(0),
                    setAID: .constant(0),
                    setBID: .constant(0),
                    solveID: .constant(0),
                    kmlRings: $rings,               // 🔵 AR renders these
                    showKML: .constant(true),
                    useKMLAsSubject: .constant(true)
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
                }
                // Auto-fetch once when we get a location
                .onChange(of: origin) { _, newLoc in
                    guard !didAutoFetch, newLoc != nil else { return }
                    didAutoFetch = true
                    getParcelsFromBackend()
                }
            } else {
                // Fallback on earlier versions
            };if #available(iOS 17.0, *) {
                ARKMLViewContainer(
                    rings: .constant([]),
                    origin: $origin,
                    status: $status,
                    showNeighbours: .constant(false),
                    showCorners: .constant(false),
                    guidanceActive: .constant(false),
                    yawDegrees: .constant(0),
                    offsetE: .constant(0),
                    offsetN: .constant(0),
                    setAID: .constant(0),
                    setBID: .constant(0),
                    solveID: .constant(0),
                    kmlRings: $rings,               // 🔵 AR renders these
                    showKML: .constant(true),
                    useKMLAsSubject: .constant(true)
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
                }
                // Auto-fetch once when we get a location
                .onChange(of: origin) { _, newLoc in
                    guard !didAutoFetch, newLoc != nil else { return }
                    didAutoFetch = true
                    getParcelsFromBackend()
                }
            } else {
                // Fallback on earlier versions
            };if #available(iOS 17.0, *) {
                ARKMLViewContainer(
                    rings: .constant([]),
                    origin: $origin,
                    status: $status,
                    showNeighbours: .constant(false),
                    showCorners: .constant(false),
                    guidanceActive: .constant(false),
                    yawDegrees: .constant(0),
                    offsetE: .constant(0),
                    offsetN: .constant(0),
                    setAID: .constant(0),
                    setBID: .constant(0),
                    solveID: .constant(0),
                    kmlRings: $rings,               // 🔵 AR renders these
                    showKML: .constant(true),
                    useKMLAsSubject: .constant(true)
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
                }
                // Auto-fetch once when we get a location
                .onChange(of: origin) { _, newLoc in
                    guard !didAutoFetch, newLoc != nil else { return }
                    didAutoFetch = true
                    getParcelsFromBackend()
                }
            } else {
                // Fallback on earlier versions
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
