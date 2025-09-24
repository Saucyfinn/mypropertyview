import SwiftUI

struct ContentView: View {
    @StateObject private var appState = AppState()
    
    var body: some View {
        TabView {
            MapView()
                .ignoresSafeArea()
                .tabItem {
                    Image(systemName: "map")
                    Text("Map")
                }
                .environmentObject(appState)
            
            ARView()
                .ignoresSafeArea()
                .tabItem {
                    Image(systemName: "arkit")
                    Text("AR View")
                }
                .environmentObject(appState)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}