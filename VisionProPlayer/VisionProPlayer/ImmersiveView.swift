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

            // Store reference for updates
            self.videoEntity = screenHolder

        } update: { content in
            // Update video content when videoManager changes
            updateVideoScreen()
        }
        .onChange(of: videoManager.playbackState) { _, newState in
            if newState == .playing {
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
    private func updateVideoScreen() {
        guard let videoEntity = videoEntity else { return }

        // Remove existing screen if any
        if let existingScreen = screenEntity {
            existingScreen.removeFromParent()
            screenEntity = nil
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
        screenEntity = newScreen

        print("[ImmersiveView] Video screen updated")
    }

    /// Creates ambient lighting for the scene
    private func createAmbientLight() -> Entity {
        let light = Entity()

        // Add a point light for subtle illumination
        var pointLight = PointLightComponent()
        pointLight.intensity = 500
        pointLight.color = .white
        pointLight.attenuationRadius = 10

        let pointLightEntity = Entity()
        pointLightEntity.components.set(pointLight)
        pointLightEntity.position = SIMD3<Float>(0, 3, 0)
        light.addChild(pointLightEntity)

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
