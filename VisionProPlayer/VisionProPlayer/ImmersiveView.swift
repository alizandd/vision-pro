import SwiftUI
import RealityKit
import AVFoundation
import Combine

/// Immersive view for full-screen video playback in visionOS.
/// Creates a large curved screen in front of the user for an immersive video experience.
/// Supports 2D, stereoscopic 3D, 180°, and 360° video formats.
struct ImmersiveView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var videoManager: VideoPlayerManager

    @State private var videoEntity: Entity?
    @State private var screenEntity: ModelEntity?
    @State private var lastVideoURL: String?
    @State private var lastVideoFormat: VideoFormat?

    var body: some View {
        RealityView { content in
            // Create the immersive environment
            let rootEntity = Entity()
            rootEntity.name = "VideoRoot"

            // Add ambient lighting
            let lightEntity = createAmbientLight()
            rootEntity.addChild(lightEntity)

            // Create the video screen holder
            // Position depends on format - for immersive content, center at origin
            let screenHolder = Entity()
            screenHolder.name = "ScreenHolder"
            // Default position for flat screens, will be adjusted in updateVideoScreen
            screenHolder.position = SIMD3<Float>(0, 1.5, -3)
            rootEntity.addChild(screenHolder)

            content.add(rootEntity)

            // Store reference for updates - defer to avoid state modification during view update
            Task { @MainActor in
                self.videoEntity = screenHolder
            }

        } update: { content in
            // Update video content when videoManager changes
            Task { @MainActor in
                updateVideoScreen()
            }
        }
        .onChange(of: videoManager.playbackState) { _, newState in
            if newState == .playing {
                Task { @MainActor in
                    updateVideoScreen()
                }
            } else if newState == .stopped || newState == .idle {
                // Reset tracking when video stops
                Task { @MainActor in
                    lastVideoURL = nil
                    lastVideoFormat = nil
                    if let existingScreen = screenEntity {
                        existingScreen.removeFromParent()
                        screenEntity = nil
                    }
                }
            }
        }
        .onChange(of: videoManager.currentFormat) { _, _ in
            Task { @MainActor in
                updateVideoScreen()
            }
        }
        .onAppear {
            print("[ImmersiveView] Appeared")
        }
        .onDisappear {
            print("[ImmersiveView] Disappeared")
            // Note: Video continues playing in background
        }
    }

    /// Updates the video screen with current video material
    /// Adjusts positioning and mesh based on video format
    private func updateVideoScreen() {
        guard let videoEntity = videoEntity else {
            print("[ImmersiveView] No video entity yet, skipping update")
            return
        }
        
        // Only update if we have a video material ready
        guard videoManager.videoMaterial != nil else {
            print("[ImmersiveView] Waiting for video material...")
            return
        }
        
        // Only proceed if video is actually playing or loading
        guard videoManager.playbackState == .playing || videoManager.playbackState == .loading else {
            print("[ImmersiveView] Playback state is \(videoManager.playbackState.rawValue), skipping update")
            return
        }
        
        let currentURL = videoManager.currentURL
        let format = videoManager.currentFormat
        
        // Check if we already have a screen for this video and format
        if screenEntity != nil && lastVideoURL == currentURL && lastVideoFormat == format {
            print("[ImmersiveView] Screen already exists for this video/format, skipping")
            return
        }

        // Remove existing screen if any
        if let existingScreen = screenEntity {
            existingScreen.removeFromParent()
            print("[ImmersiveView] Removed existing screen")
        }
        
        print("[ImmersiveView] Creating screen for format: \(format.displayName)")
        
        // Adjust holder position based on format
        // For immersive content (180°/360°), center at origin so user is inside the dome/sphere
        // For flat content, position in front of user
        if format.isImmersive {
            // For 180°/360° content, center at eye level
            videoEntity.position = SIMD3<Float>(0, 1.5, 0)
            print("[ImmersiveView] Immersive format - centering at origin")
        } else {
            // For flat screens, position in front of user
            videoEntity.position = SIMD3<Float>(0, 1.5, -3)
            print("[ImmersiveView] Flat format - positioning screen in front")
        }
        
        // Calculate screen dimensions based on format
        let (width, height) = getScreenDimensions(for: format)

        // Create new screen with video material
        guard let newScreen = videoManager.createVideoEntity(width: width, height: height) else {
            print("[ImmersiveView] Could not create video entity")
            return
        }

        newScreen.name = "VideoScreen"

        // Position the screen relative to holder
        newScreen.position = SIMD3<Float>(0, 0, 0)
        
        // For immersive content, ensure correct orientation
        if format.isImmersive {
            // Rotate 180° on Y axis so front of hemisphere faces user
            newScreen.orientation = simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 1, 0))
            print("[ImmersiveView] Applied 180° rotation for immersive content")
        }

        videoEntity.addChild(newScreen)
        
        // Update state reference after adding to scene
        Task { @MainActor in
            self.screenEntity = newScreen
            self.lastVideoURL = currentURL
            self.lastVideoFormat = format
        }

        print("[ImmersiveView] Video screen created successfully for \(format.displayName)")
    }
    
    /// Returns appropriate screen dimensions based on video format
    private func getScreenDimensions(for format: VideoFormat) -> (Float, Float) {
        switch format {
        case .mono2D:
            // Standard 16:9 flat screen
            return (4.0, 2.25)
            
        case .sideBySide3D:
            // Side-by-side 3D: video is 2:1 ratio squeezed to appear 16:9
            // Each eye sees half the width, so display at 16:9 ratio
            return (4.0, 2.25)
            
        case .overUnder3D:
            // Over-under 3D: video is 1:1 ratio when expanded
            // Each eye sees half the height
            return (4.0, 2.25)
            
        case .hemisphere180, .hemisphere180SBS:
            // 180° content uses hemisphere mesh, dimensions are radius-based
            return (5.0, 5.0)
            
        case .sphere360, .sphere360OU, .sphere360SBS:
            // 360° content uses full sphere, dimensions are radius-based
            return (5.0, 5.0)
        }
    }

    /// Creates ambient lighting for the scene
    /// Note: Simplified for visionOS 1.0 compatibility
    private func createAmbientLight() -> Entity {
        let light = Entity()
        
        // For visionOS 1.0 compatibility, we use the default lighting
        // The video material provides its own illumination
        // Additional lighting can be added in visionOS 2.0+ if needed
        
        return light
    }
}

/// A more sophisticated immersive video view with dome/sphere projection
struct ImmersiveDomeView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var videoManager: VideoPlayerManager

    var body: some View {
        RealityView { content in
            // Create a dome/hemisphere for 180-degree video
            // This is useful for VR180 content

            let rootEntity = Entity()
            rootEntity.name = "DomeRoot"

            // Position user at center
            rootEntity.position = SIMD3<Float>(0, 0, 0)

            content.add(rootEntity)
        }
    }
}

/// Helper view for debugging the immersive space
struct ImmersiveDebugView: View {
    @EnvironmentObject var videoManager: VideoPlayerManager

    var body: some View {
        VStack {
            Text("Playback: \(videoManager.playbackState.rawValue)")
            Text("Progress: \(String(format: "%.1f%%", videoManager.progress * 100))")
            if let url = videoManager.currentURL {
                Text("URL: \(url)")
                    .lineLimit(1)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
}

#Preview(immersionStyle: .full) {
    ImmersiveView()
        .environmentObject(AppState())
        .environmentObject(VideoPlayerManager())
}
