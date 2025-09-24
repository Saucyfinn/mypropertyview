import SwiftUI

/// AR screen with overlay controls
struct ARTab: View {
    /// Binding from ContentView’s TabView (0 = Map)
    @Binding var selectedTab: Int

    /// Show neighbouring parcels? (we pass this as a radius hint)
    @State private var showNeighbours = false

    /// Tweak the AR fetch radius based on the toggle
    private var arRadius: Double { showNeighbours ? 300 : 80 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Your ARKit view
            ParcelsARView(radiusMeters: arRadius)
                .ignoresSafeArea() // AR full-bleed

            // Top overlay: Back + Neighbours toggle
            HStack(spacing: 12) {
                // Back to Map
                Button {
                    selectedTab = 0 // switch TabView to Map tab
                } label: {
                    Label("Map", systemImage: "map")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)

                // Neighbours toggle
                Button {
                    showNeighbours.toggle()
                } label: {
                    Label(showNeighbours ? "Neighbours On" : "Neighbours Off",
                          systemImage: showNeighbours ? "person.3.fill" : "person.3")
                }
                .buttonStyle(.bordered)
                .tint(.secondary)

                Spacer()
            }
            .padding(.top, 12)
            .padding(.leading, 12)
            .padding(.trailing, 12)
        }
    }
}
