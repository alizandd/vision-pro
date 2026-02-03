import SwiftUI

/// Main entry point for the Vision Pro Player application.
/// This app acts as a remote-controlled video player that receives commands
/// via WebSocket from the web controller.
///
/// VERSION: Native AVPlayer (16K Support)
/// This version uses AVPlayerViewController instead of RealityKit's VideoMaterial:
/// - No texture size limitations (supports 16K and beyond)
/// - Automatic per-eye stereoscopic rendering
/// - Memory-efficient hardware-accelerated decoding  
/// - Better simulator compatibility
///
/// LIFECYCLE for Video Playback:
/// 1. Receive play command via WebSocket
/// 2. Open immersive space
/// 3. Prepare video with native player
/// 4. Start playback when ready
@main
struct VisionProPlayerApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var webSocketManager = WebSocketManager()
    @StateObject private var nativeVideoManager = NativeVideoPlayerManager()
    @StateObject private var localVideoManager = LocalVideoManager()

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // Main window - minimal UI, just shows connection status
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(appState)
                .environmentObject(webSocketManager)
                .environmentObject(nativeVideoManager)
                .environmentObject(localVideoManager)
                .onAppear {
                    setupCommandHandling()
                    setupLocalVideoSync()
                    webSocketManager.connect()
                    
                    // Scan local videos on startup
                    localVideoManager.scanVideos()
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

        // Immersive space for native video playback (16K support)
        ImmersiveSpace(id: "ImmersiveVideoSpace") {
            NativeImmersiveView()
                .environmentObject(appState)
                .environmentObject(nativeVideoManager)
        }
        .immersionStyle(selection: .constant(.full), in: .full)
    }

    /// Sets up syncing of local videos with server when connected
    private func setupLocalVideoSync() {
        // Capture references for closure
        let wsManager = webSocketManager
        let localManager = localVideoManager
        
        // When connection state changes to connected, send local videos
        // Also periodically rescan for new/removed files
        Task { @MainActor in
            var wasConnected = false
            var scanCounter = 0
            
            while true {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // Check every second
                scanCounter += 1
                
                let isNowConnected = wsManager.isConnected
                
                // When we just connected, send local videos
                if isNowConnected && !wasConnected {
                    // Small delay to ensure registration is complete
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    wsManager.sendLocalVideos(localManager.localVideos)
                }
                
                // Rescan every 10 seconds to detect file changes
                if scanCounter >= 10 {
                    scanCounter = 0
                    let previousFilenames = Set(localManager.localVideos.map { $0.filename })
                    localManager.scanVideos()
                    let currentFilenames = Set(localManager.localVideos.map { $0.filename })
                    
                    // If files changed and we're connected, send update
                    if previousFilenames != currentFilenames && isNowConnected {
                        print("[App] Local videos changed: \(previousFilenames) -> \(currentFilenames)")
                        wsManager.sendLocalVideos(localManager.localVideos)
                    }
                }
                
                wasConnected = isNowConnected
            }
        }
    }
    
    /// Sets up the command handling pipeline between WebSocket and native video player
    private func setupCommandHandling() {
        // Capture references for closures
        let state = appState
        let vidManager = nativeVideoManager
        let wsManager = webSocketManager
        
        // Handle incoming commands from WebSocket
        webSocketManager.onCommand = { command in
            Task { @MainActor in
                await self.handleCommand(command, appState: state, videoManager: vidManager)
            }
        }

        // Send status updates when video state changes
        nativeVideoManager.onStateChange = { playbackState in
            wsManager.sendStatus(
                state: playbackState.rawValue,
                currentVideo: state.currentVideoURL,
                immersiveMode: state.isImmersiveActive,
                currentTime: vidManager.currentTime
            )
        }
        
        // Handle player ready callback for proper lifecycle
        nativeVideoManager.onPlayerReady = {
            print("[App] Native video player ready, starting playback")
            vidManager.startPlayback()
            
            // Update status
            wsManager.sendStatus(
                state: PlaybackState.playing.rawValue,
                currentVideo: state.currentVideoURL,
                immersiveMode: state.isImmersiveActive,
                currentTime: 0
            )
        }
    }

    /// Handles commands received from the WebSocket server.
    /// Uses native AVPlayer for 16K video support.
    @MainActor
    private func handleCommand(
        _ command: ServerCommand,
        appState: AppState,
        videoManager: NativeVideoPlayerManager
    ) async {
        print("[App] Received command: \(command.action)")

        switch command.action {
        case .play:
            await handlePlayCommand(command: command, appState: appState, videoManager: videoManager)

        case .pause:
            videoManager.pause()

        case .resume:
            videoManager.resume()

        case .change:
            // Change is similar to play but may already have immersive space open
            await handlePlayCommand(command: command, appState: appState, videoManager: videoManager)

        case .stop:
            videoManager.stop()

            // Close immersive space and restore main window
            if appState.isImmersiveActive {
                await dismissImmersiveSpace()
                appState.isImmersiveActive = false
                print("[App] Immersive space closed")
                
                // Reopen the main window
                openWindow(id: "main")
                print("[App] Main window reopened")
            }
        }
    }
    
    /// Handles play and change commands using native AVPlayer for 16K support.
    /// 
    /// LIFECYCLE ORDER:
    /// 1. Open immersive space
    /// 2. Wait for immersive space to be ready
    /// 3. Prepare video with native player (no texture size limits)
    /// 4. Playback starts when video is ready (via callback)
    @MainActor
    private func handlePlayCommand(
        command: ServerCommand,
        appState: AppState,
        videoManager: NativeVideoPlayerManager
    ) async {
        guard let videoUrl = command.videoUrl else {
            print("[App] Play/Change command missing video URL")
            return
        }

        // Get video format (default to hemisphere180SBS for VR content)
        let format = command.videoFormat ?? .hemisphere180SBS
        
        print("[App] ========== PLAY COMMAND ==========")
        print("[App] Video URL: \(videoUrl)")
        print("[App] Format: \(format.displayName)")
        print("[App] Is Immersive: \(format.isImmersive)")
        print("[App] Is Stereoscopic: \(format.isStereoscopic)")
        
        // Update app state
        appState.currentVideoURL = videoUrl
        appState.currentVideoFormat = format
        
        // STEP 1: Open immersive space FIRST (before initializing video)
        if !appState.isImmersiveActive {
            print("[App] Step 1: Opening immersive space...")
            let result = await openImmersiveSpace(id: "ImmersiveVideoSpace")
            switch result {
            case .opened:
                appState.isImmersiveActive = true
                print("[App] Immersive space opened successfully")
                
                // Hide the main window for full immersion (like native player)
                dismissWindow(id: "main")
                print("[App] Main window dismissed for full immersion")
                
            case .error:
                print("[App] ERROR: Failed to open immersive space")
                appState.setError("Failed to open immersive space")
                return
            case .userCancelled:
                print("[App] User cancelled immersive space")
                return
            @unknown default:
                return
            }
        } else {
            print("[App] Immersive space already active")
        }
        
        // STEP 2: Wait for immersive space to be fully ready
        // This is CRITICAL for large files - initializing video before
        // the immersive space is ready causes memory pressure and crashes
        print("[App] Step 2: Waiting for immersive space to be ready...")
        let immersiveSpaceReady = await waitForImmersiveSpaceReady()
        
        if !immersiveSpaceReady {
            print("[App] WARNING: Immersive space readiness timeout, proceeding anyway")
        } else {
            print("[App] Immersive space is ready")
        }
        
        // STEP 3: Prepare video (does NOT start playback - that happens via callback)
        print("[App] Step 3: Preparing video...")
        let prepared = await videoManager.prepareVideo(url: videoUrl, format: format)
        
        if !prepared {
            print("[App] ERROR: Failed to prepare video")
            appState.setError("Failed to prepare video")
            return
        }
        
        // STEP 4: Playback will start automatically via onPlayerReady callback
        print("[App] Video prepared, waiting for player ready callback...")
        print("[App] ========================================")
    }
    
    /// Waits for the immersive space to be fully initialized.
    /// This includes:
    /// - RealityKit content added to scene
    /// - Rendering context initialized
    /// - GPU resources allocated
    @MainActor
    private func waitForImmersiveSpaceReady() async -> Bool {
        // Minimum wait time for immersive space initialization
        // For large videos, we need the rendering context to be fully ready
        // before initializing video decoding to prevent memory pressure
        let minimumWaitTime: TimeInterval = 1.5
        let maxWaitTime: TimeInterval = 5.0
        let checkInterval: TimeInterval = 0.1
        
        let startTime = Date()
        
        // First, wait for minimum time to ensure RealityKit is ready
        try? await Task.sleep(nanoseconds: UInt64(minimumWaitTime * 1_000_000_000))
        
        // Then check for additional readiness indicators
        while Date().timeIntervalSince(startTime) < maxWaitTime {
            // For now, we rely on timing - future improvement could check
            // for actual RealityKit scene readiness if such an API exists
            if Date().timeIntervalSince(startTime) >= minimumWaitTime {
                return true
            }
            
            try? await Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))
        }
        
        return false
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
            
            // Rescan local videos when app becomes active
            print("[App] Rescanning local videos...")
            localVideoManager.scanVideos()
            
            // Send updated list to server if connected
            if webSocketManager.isConnected {
                Task {
                    try? await Task.sleep(nanoseconds: 500_000_000) // Small delay
                    webSocketManager.sendLocalVideos(localVideoManager.localVideos)
                }
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
