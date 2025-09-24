import SwiftUI

struct ContentView: View {
    @StateObject private var appState = AppState()
    
    var body: some View {
        if appState.isAppReady {
            TabView {
                MapTab()
                    .tabItem {
                        Image(systemName: "map")
                        Text("Map")
                    }
                    .environmentObject(appState)
                
                ARTab()
                    .tabItem {
                        Image(systemName: "camera.viewfinder")
                        Text("AR View")
                    }
                    .environmentObject(appState)
                
                SettingsTab()
                    .tabItem {
                        Image(systemName: "gear")
                        Text("Settings")
                    }
                    .environmentObject(appState)
            }
            .accentColor(.blue)
        } else {
            LoadingScreen()
                .environmentObject(appState)
        }
    }
}

struct LoadingScreen: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 30) {
            // Enhanced logo/icon
            Image(systemName: "map.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.blue)
                .padding()
            
            VStack(spacing: 16) {
                Text("PropertyView Enhanced")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("Advanced Property Boundary Visualization")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(.blue)
                
                Text(appState.loadingMessage)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .animation(.easeInOut(duration: 0.3), value: appState.loadingMessage)
            }
            .padding(.top, 20)
            
            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

#Preview {
    ContentView()
}