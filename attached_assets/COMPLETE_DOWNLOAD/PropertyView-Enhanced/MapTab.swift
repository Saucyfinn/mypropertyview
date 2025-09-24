import SwiftUI

struct MapTab: View {
    @Binding var selectedTab: Int

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Leaflet + LINZ lives in the web view
            WebMapView()
                .ignoresSafeArea()

            // Quick switch to AR (now at bottom right, more visible)
            Button {
                selectedTab = 1
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "camera.viewfinder")
                    Text("Open in AR")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.regularMaterial, in: Capsule())
                .foregroundColor(.accentColor)
                .shadow(color: Color.black.opacity(0.18), radius: 9, x: 0, y: 2)
            }
            .padding(.trailing, 22)
            .padding(.bottom, 32)
            .accessibilityIdentifier("openInARButton")
        }
    }
}
