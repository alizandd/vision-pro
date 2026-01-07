import SwiftUI
import Combine

/// Central app state manager that tracks the current state of the application
@MainActor
class AppState: ObservableObject {
    /// Whether the immersive space is currently active
    @Published var isImmersiveActive: Bool = false

    /// The URL of the currently playing or queued video
    @Published var currentVideoURL: String?
    
    /// Current video format (stereoscopic type, projection, etc.)
    @Published var currentVideoFormat: VideoFormat = .mono2D

    /// Current playback state
    @Published var playbackState: PlaybackState = .idle

    /// Connection status to WebSocket server
    @Published var isConnected: Bool = false

    /// Last error message if any
    @Published var lastError: String?

    /// Unique device identifier
    let deviceId: String

    /// Device name for display
    var deviceName: String {
        get { AppConfiguration.deviceName }
        set { AppConfiguration.deviceName = newValue }
    }

    init() {
        // Generate or retrieve persistent device ID
        if let storedId = UserDefaults.standard.string(forKey: "device_id") {
            self.deviceId = storedId
        } else {
            let newId = UUID().uuidString
            UserDefaults.standard.set(newId, forKey: "device_id")
            self.deviceId = newId
        }
    }

    /// Updates the playback state and clears any error
    func updatePlaybackState(_ state: PlaybackState) {
        self.playbackState = state
        if state != .error {
            self.lastError = nil
        }
    }

    /// Sets an error state with message
    func setError(_ message: String) {
        self.playbackState = .error
        self.lastError = message
        print("[AppState] Error: \(message)")
    }

    /// Resets the state to idle
    func reset() {
        self.isImmersiveActive = false
        self.currentVideoURL = nil
        self.currentVideoFormat = .mono2D
        self.playbackState = .idle
        self.lastError = nil
    }
}
