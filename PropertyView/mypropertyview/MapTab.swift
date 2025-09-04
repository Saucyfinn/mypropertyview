import SwiftUI
import CoreLocation

struct MapTab: View {
    @EnvironmentObject var state: AppState
    @StateObject private var loc = LocationModel()

    @State private var webURL: URL?
    @State private var didSeed = false

    var body: some View {
        WebMapView(url: webURL ?? state.bundledWebURL(with: nil))
            .ignoresSafeArea()
            .navigationTitle("Map")
            .onAppear {
                webURL = state.bundledWebURL(with: nil)        // load immediately
            }
            .onChange(of: loc.last) { newLoc in
                guard !didSeed, let newLoc else { return }     // seed once
                webURL = state.bundledWebURL(with: newLoc)
                didSeed = true
            }
    }
}
