import SwiftUI

struct MainTabs: View {
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            MapTab()
                .tabItem { Label("Map", systemImage: "map") }
                .tag(0)

            ARTab(selection: $selection)
                .tabItem { Label("AR", systemImage: "camera.viewfinder") }
                .tag(1)
        }
    }
}
