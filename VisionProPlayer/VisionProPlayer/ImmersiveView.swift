import SwiftUI
import RealityKit
import AVFoundation
import Combine

/// Immersive view for full-screen video playback in visionOS.
/// Creates a large curved screen in front of the user for an immersive video experience.
struct ImmersiveView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var videoManager: VideoPlayerManager

    @State private var videoEntity: Entity?
    @State private var screenEntity: ModelEntity?

    var body: some View {
        RealityView { content in
            // Create the immersive environment
            let rootEntity = Entity()
            rootEntity.name = "VideoRoot"

            // Add ambient lighting
            let lightEntity = createAmbientLight()
            rootEntity.addChild(lightEntity)

            // Create the video screen holder
            let screenHolder = Entity()
            screenHolder.name = "ScreenHolder"
            screenHolder.position = SIMD3<Float>(0, 1.5, -3) // 3 meters in front, at eye level
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
    private func updateVideoScreen() {
        guard let videoEntity = videoEntity else { return }

        // Remove existing screen if any
        if let existingScreen = screenEntity {
            existingScreen.removeFromParent()
        }

        // Create new screen with video material
        guard let newScreen = videoManager.createVideoEntity(width: 4.0, height: 2.25) else {
            print("[ImmersiveView] Could not create video entity")
            return
        }

        newScreen.name = "VideoScreen"

        // Position the screen
        newScreen.position = SIMD3<Float>(0, 0, 0)

        // Add slight curve effect by rotating edges (optional enhancement)
        // For a flat screen, we just use the plane as-is

        videoEntity.addChild(newScreen)
        
        // Update state reference after adding to scene
        Task { @MainActor in
            self.screenEntity = newScreen
        }

        print("[ImmersiveView] Video screen updated")
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
