import SwiftUI

struct LoadingView: View {
    @EnvironmentObject var appState: AppState
    @State private var isAnimating = false
    @State private var opacity = 0.0

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color.blue.opacity(0.8), Color.green.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 30) {
                // App Icon/Logo
                Image(systemName: "map.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.white)
                    .scaleEffect(isAnimating ? 1.1 : 1.0)
                    .animation(
                        Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                        value: isAnimating
                    )

                // App Name
                Text("PropertyView")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .opacity(opacity)

                // Dynamic Loading Text
                Text(appState.loadingMessage)
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.9))
                    .opacity(opacity)
                    .animation(.easeInOut(duration: 0.3), value: appState.loadingMessage)

                // Loading Indicator
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
                    .opacity(opacity)
            }
        }
        .onAppear {
            // Start animations
            isAnimating = true
            withAnimation(.easeIn(duration: 0.8)) {
                opacity = 1.0
            }
        }
    }
}

#Preview {
    LoadingView()
}
//  LoadingView.swift
//  PropertyView
//
//  Created by Brendon Hogg on 30/08/2025.
//
