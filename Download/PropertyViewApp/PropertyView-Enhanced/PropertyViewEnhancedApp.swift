import SwiftUI

@main
struct PropertyViewEnhancedApp: App {
    @StateObject private var appState = AppLoadingState()
    
    var body: some Scene {
        WindowGroup {
            if appState.isLoading {
                LoadingView(appState: appState)
            } else {
                ContentView()
                    .preferredColorScheme(.none)
            }
        }
    }
}

// MARK: - App Loading State
@MainActor
class AppLoadingState: ObservableObject {
    @Published var isLoading = true
    @Published var loadingProgress = 0.0
    @Published var loadingMessage = "Starting PropertyView Enhanced..."
    
    func startLoading() {
        Task { @MainActor in
            await performLoadingSteps()
        }
    }
    
    private func performLoadingSteps() async {
        let steps = [
            ("Loading map components...", 0.2),
            ("Initializing location services...", 0.4),
            ("Setting up AR framework...", 0.6),
            ("Preparing LINZ integration...", 0.8),
            ("Ready!", 1.0)
        ]
        
        for (message, progress) in steps {
            loadingMessage = message
            loadingProgress = progress
            try? await Task.sleep(nanoseconds: 600_000_000)
        }
        
        try? await Task.sleep(nanoseconds: 300_000_000)
        isLoading = false
    }
}

// MARK: - Loading View
struct LoadingView: View {
    @ObservedObject var appState: AppLoadingState
    
    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color.blue.opacity(0.8), Color.cyan.opacity(0.6)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 30) {
                Image(systemName: "map.fill")
                    .font(.system(size: 80, weight: .light))
                    .foregroundColor(.white)
                
                VStack(spacing: 16) {
                    Text("PropertyView Enhanced")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("Interactive Property Mapping with AR")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }
                
                VStack(spacing: 12) {
                    ProgressView(value: appState.loadingProgress)
                        .progressViewStyle(LinearProgressViewStyle(tint: .white))
                        .scaleEffect(y: 2)
                        .frame(width: 200)
                    
                    Text(appState.loadingMessage)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                        .frame(height: 20)
                }
            }
            .padding()
        }
        .onAppear {
            appState.startLoading()
        }
    }
}
