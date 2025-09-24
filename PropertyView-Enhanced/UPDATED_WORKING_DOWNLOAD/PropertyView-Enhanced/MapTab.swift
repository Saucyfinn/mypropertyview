import SwiftUI

struct MapTab: View {
    @Binding var selectedTab: Int

    var body: some View {
        // Clean map view without duplicate AR button (AR access via tab bar)
        WebMapView()
            .ignoresSafeArea()
    }
}
