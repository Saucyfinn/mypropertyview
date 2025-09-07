import SwiftUI

@main
struct PropertyviewApp: App {
    @StateObject var state = AppState()
    var body: some Scene {
        WindowGroup {
            MainTabs()                 // ✅ your TabView, not ContentView()
                .environmentObject(state)
        }
    }
}
