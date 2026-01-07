import SwiftUI

/// Main entry point for the Vision Pro Player application.
/// This app acts as a remote-controlled video player that receives commands
/// via WebSocket from the web controller.
@main
struct VisionProPlayerApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var webSocketManager = WebSocketManager()
    @StateObject private var videoManager = VideoPlayerManager()

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    var body: some Scene {
        // Main window - minimal UI, just shows connection status
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(webSocketManager)
                .environmentObject(videoManager)
                .onAppear {
                    setupCommandHandling()
                    webSocketManager.connect()
                }
        }
        .windowStyle(.plain)
        .defaultSize(width: 400, height: 300)
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(from: oldPhase, to: newPhase)
        }

        // Settings window for configuration
        WindowGroup(id: "settings") {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(webSocketManager)
        }
        .windowStyle(.plain)
        .defaultSize(width: 500, height: 400)

        // Immersive space for video playback
        ImmersiveSpace(id: "ImmersiveVideoSpace") {
            ImmersiveView()
                .environmentObject(appState)
                .environmentObject(videoManager)
        }
        .immersionStyle(selection: .constant(.full), in: .full)
    }

    /// Sets up the command handling pipeline between WebSocket and video player
    private func setupCommandHandling() {
        // Handle incoming commands from WebSocket
        webSocketManager.onCommand = { [weak appState, weak videoManager] command in
            guard let appState = appState, let videoManager = videoManager else { return }

            Task { @MainActor in
                await handleCommand(command, appState: appState, videoManager: videoManager)
            }
        }

        // Send status updates when video state changes
        videoManager.onStateChange = { [weak webSocketManager, weak appState, weak videoManager] state in
            guard let webSocketManager = webSocketManager, let appState = appState, let videoManager = videoManager else { return }

            webSocketManager.sendStatus(
                state: state.rawValue,
                currentVideo: appState.currentVideoURL,
                immersiveMode: appState.isImmersiveActive,
                currentTime: videoManager.currentTime
            )
        }
    }

    /// Handles commands received from the WebSocket server
    @MainActor
    private func handleCommand(
        _ command: ServerCommand,
        appState: AppState,
        videoManager: VideoPlayerManager
    ) async {
        print("[App] Received command: \(command.action)")

        switch command.action {
        case .play:
            guard let videoUrl = command.videoUrl else {
                print("[App] Play command missing video URL")
                return
            }

            appState.currentVideoURL = videoUrl
            
            // Set video format (default to mono2D if not specified)
            let format = command.videoFormat ?? .mono2D
            appState.currentVideoFormat = format
            print("[App] Video format: \(format.displayName)")

            // Open immersive space if not already open
            if !appState.isImmersiveActive {
                let result = await openImmersiveSpace(id: "ImmersiveVideoSpace")
                switch result {
                case .opened:
                    appState.isImmersiveActive = true
                    print("[App] Immersive space opened")
                case .error:
                    print("[App] Failed to open immersive space")
                    return
                case .userCancelled:
                    print("[App] User cancelled immersive space")
                    return
                @unknown default:
                    return
                }
            }

            // Start video playback with format
            try? await Task.sleep(nanoseconds: 500_000_000) // Brief delay for space to initialize
            videoManager.play(url: videoUrl, format: format)

        case .pause:
            videoManager.pause()

        case .resume:
            videoManager.resume()

        case .change:
            guard let videoUrl = command.videoUrl else {
                print("[App] Change command missing video URL")
                return
            }

            appState.currentVideoURL = videoUrl
            
            // Set video format (default to mono2D if not specified)
            let format = command.videoFormat ?? .mono2D
            appState.currentVideoFormat = format

            // Open immersive space if not already open
            if !appState.isImmersiveActive {
                let result = await openImmersiveSpace(id: "ImmersiveVideoSpace")
                if case .opened = result {
                    appState.isImmersiveActive = true
                }
            }

            try? await Task.sleep(nanoseconds: 300_000_000)
            videoManager.play(url: videoUrl, format: format)

        case .stop:
            videoManager.stop()

            // Close immersive space
            if appState.isImmersiveActive {
                await dismissImmersiveSpace()
                appState.isImmersiveActive = false
            }
        }
    }
    
    /// Handles scene phase changes (app lifecycle events)
    /// This ensures WebSocket stays connected when headset is passed between users
    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        print("[App] Scene phase changed: \(oldPhase) -> \(newPhase)")
        
        switch newPhase {
        case .active:
            // App became active (user put on headset or returned to app)
            print("[App] App became active - checking WebSocket connection")
            
            // If not connected, reconnect
            if !webSocketManager.isConnected {
                print("[App] WebSocket disconnected, reconnecting...")
                webSocketManager.connect()
            }
            
        case .inactive:
            // App became inactive (transitioning state)
            print("[App] App became inactive")
            // Keep connection alive during brief inactive states
            
        case .background:
            // App went to background (headset removed or app minimized)
            print("[App] App went to background")
            // Keep connection alive - will auto-reconnect when active
            // Note: WebSocket has built-in reconnection logic
            
        @unknown default:
            break
        }
    }
}
