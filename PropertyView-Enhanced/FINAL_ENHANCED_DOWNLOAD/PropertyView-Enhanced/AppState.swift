import SwiftUI
import CoreLocation

/// Global app model used by the tabs.
/// Keep this lightweight — the Web/AR layers fetch their own data.
@MainActor
final class AppState: ObservableObject {

    // MARK: - App lifecycle / UI
    /// ✅ Keep this `true` so the TabView shows immediately (no endless loader).
    @Published var isAppReady: Bool = true

    /// Small status line you can show in a HUD if you want.
    @Published var loadingMessage: String = "Starting…"

    // MARK: - Positioning (for Settings tab display)
    enum PositioningStatus {
        case idle
        case locating
        case ready
        case error(String)

        var displayText: String {
            switch self {
            case .idle: return "Idle"
            case .locating: return "Locating…"
            case .ready: return "Ready"
            case .error(let m): return "Error: \(m)"
            }
        }

        var color: Color {
            switch self {
            case .idle: return .secondary
            case .locating: return .orange
            case .ready: return .green
            case .error: return .red
            }
        }
    }

    @Published var positioningStatus: PositioningStatus = .idle

    // MARK: - Optional bits some views may read
    /// Last known device coordinate (if you want to reflect it somewhere).
    @Published var lastLocation: CLLocationCoordinate2D?

    /// UI toggles (e.g., neighbours on the map).
    @Published var neighboursOn: Bool = false

    // MARK: - No-op compatibility shims (avoid build errors in legacy code)
    func forceARUpdate() { /* intentionally empty */ }
    func updateCoordinates() { /* intentionally empty */ }
}
