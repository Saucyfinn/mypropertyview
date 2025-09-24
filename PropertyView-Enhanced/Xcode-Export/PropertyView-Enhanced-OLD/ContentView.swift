import SwiftUI
import ARKit

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

struct SettingsTab: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("App Information")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("PropertyView Enhanced 1.0")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Properties Loaded")
                        Spacer()
                        Text("0")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("Data Sources")) {
                    HStack {
                        Text("LINZ Integration")
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                    
                    HStack {
                        Text("AR Support")
                        Spacer()
                        Image(systemName: ARWorldTrackingConfiguration.isSupported ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(ARWorldTrackingConfiguration.isSupported ? .green : .red)
                    }
                }
                
                Section(header: Text("Help")) {
                    Button("How to Use AR View") { }
                    Button("Property Boundary Guide") { }
                    Button("Contact Support") { }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    ContentView()
}