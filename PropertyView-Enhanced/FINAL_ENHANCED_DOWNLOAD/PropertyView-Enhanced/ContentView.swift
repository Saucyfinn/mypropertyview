// ContentView.swift
// PropertyView-Enhanced

import SwiftUI

struct ContentView: View {
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Map
            MapTab(selectedTab: $selectedTab)
                .tabItem {
                    Image(systemName: "map")
                    Text("Map")
                }
                .tag(0)

            // AR
            ARTab(selectedTab: $selectedTab)
                .tabItem {
                    Image(systemName: "camera.viewfinder")
                    Text("AR View")
                }
                .tag(1)

            // GPS
            GPSTab(selectedTab: $selectedTab)
                .tabItem {
                    Image(systemName: "location.north.circle")
                    Text("GPS")
                }
                .tag(2)

            // Settings (standalone – no AppState)
            SettingsTab()
                .tabItem {
                    Image(systemName: "gear")
                    Text("Settings")
                }
                .tag(3)
        }
        .accentColor(.blue)
    }
}

// MARK: - Simple Settings tab (no AppState)
struct SettingsTab: View {
    @State private var linzConfigured: Bool = {
        let v = Bundle.main.object(forInfoDictionaryKey: "LINZ_API_KEY") as? String
        return (v?.isEmpty == false)
    }()

    var body: some View {
        NavigationView {
            List {
                Section("App Information") {
                    KeyValueRow(key: "Version", value: "1.0")
                    KeyValueRow(key: "Build", value: "September 2025")
                }

                Section("Features") {
                    FeatureRow(icon: "map", title: "Interactive Map", enabled: true)
                    FeatureRow(icon: "camera.viewfinder", title: "AR Boundary View", enabled: true)
                    FeatureRow(icon: "location", title: "GPS Positioning", enabled: true)
                }

                Section("Data Integration") {
                    FeatureRow(icon: "cloud", title: "LINZ Data Service", enabled: true)
                    HStack {
                        Image(systemName: "key")
                            .foregroundColor(.orange)
                        Text("API Key Status")
                        Spacer()
                        Text(linzConfigured ? "Configured" : "Missing")
                            .foregroundColor(linzConfigured ? .green : .red)
                    }
                }

                Section("Support") {
                    Button("How to Use AR View") { /* hook up help */ }
                    Button("Property Boundary Guide") { /* hook up doc */ }
                    Button("Contact Support") { /* hook up email */ }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

private struct KeyValueRow: View {
    let key: String
    let value: String
    var body: some View {
        HStack {
            Text(key)
            Spacer()
            Text(value).foregroundColor(.secondary)
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let enabled: Bool
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
            Text(title)
            Spacer()
            Image(systemName: enabled ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .foregroundColor(enabled ? .green : .red)
        }
    }
}

// MARK: - Preview
#Preview {
    ContentView()
}
