import SwiftUI
import RealityKit
import AVKit
import AVFoundation
import ARKit

/// Native immersive view for stereo 180° SBS video playback.
/// 
/// This view renders video on a hemisphere mesh for proper VR immersion.
/// For SBS (Side-by-Side) stereo content, it maps only the LEFT half of the
/// video texture to create a mono view from the left eye's perspective.
///
/// Note: True per-eye stereoscopic rendering requires either:
/// - MV-HEVC encoded video with spatial metadata
/// - Or custom Metal shaders (not implemented here)
///
/// HEAD TRACKING: Uses ARKit to recenter video in front of user when:
/// - A new video starts playing
/// - Video resumes after being stopped
struct NativeImmersiveView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var videoManager: NativeVideoPlayerManager
    
    @State private var videoEntity: Entity?
    @State private var screenEntity: ModelEntity?
    @State private var lastVideoURL: String?
    @State private var lastVideoFormat: VideoFormat?
    @State private var isViewReady: Bool = false
    @State private var videoMaterial: VideoMaterial?
    
    /// ARKit session for head tracking
    @State private var arkitSession = ARKitSession()
    @State private var worldTracking = WorldTrackingProvider()
    
    var body: some View {
        RealityView { content in
            // Create the immersive environment
            let rootEntity = Entity()
            rootEntity.name = "VideoRoot"
            
            // Create the video screen holder centered on viewer
            let screenHolder = Entity()
            screenHolder.name = "ScreenHolder"
            screenHolder.position = SIMD3<Float>(0, 0, 0)
            rootEntity.addChild(screenHolder)
            
            content.add(rootEntity)
            
            // Mark as ready and start head tracking
            Task { @MainActor in
                self.videoEntity = screenHolder
                self.isViewReady = true
                print("[NativeImmersiveView] Immersive space ready")
                
                // Start ARKit session for head tracking
                await startARKitSession()
                
                // If video is already ready, create the screen with recentering
                if videoManager.isPlayerReady {
                    await updateVideoScreenWithRecentering()
                }
            }
        } update: { content in
            Task { @MainActor in
                if isViewReady {
                    updateVideoScreen()
                }
            }
        }
        .onChange(of: videoManager.isPlayerReady) { _, isReady in
            if isReady && isViewReady {
                Task { @MainActor in
                    // New video ready - recenter to face user
                    await updateVideoScreenWithRecentering()
                }
            }
        }
        .onChange(of: videoManager.playbackState) { _, newState in
            if newState == .playing && isViewReady {
                Task { @MainActor in
                    // Only update without recentering during regular playback
                    updateVideoScreen()
                }
            } else if newState == .stopped || newState == .idle {
                Task { @MainActor in
                    cleanupVideoScreen()
                }
            }
        }
        .onChange(of: videoManager.currentFormat) { _, _ in
            Task { @MainActor in
                if isViewReady {
                    lastVideoFormat = nil
                    await updateVideoScreenWithRecentering()
                }
            }
        }
        .onChange(of: videoManager.currentURL) { oldURL, newURL in
            // When video URL changes, force recenter on next update
            if oldURL != newURL && newURL != nil && isViewReady {
                Task { @MainActor in
                    print("[NativeImmersiveView] Video URL changed - will recenter when ready")
                    lastVideoURL = nil
                    lastVideoFormat = nil
                }
            }
        }
        .onAppear {
            print("[NativeImmersiveView] View appeared")
            isViewReady = true
        }
        .onDisappear {
            print("[NativeImmersiveView] View disappeared")
            isViewReady = false
            cleanupVideoScreen()
            // Stop ARKit session
            arkitSession.stop()
            print("[NativeImmersiveView] ARKit session stopped")
        }
    }
    
    // MARK: - Video Screen Management
    
    private func cleanupVideoScreen() {
        lastVideoURL = nil
        lastVideoFormat = nil
        videoMaterial = nil
        if let existingScreen = screenEntity {
            existingScreen.removeFromParent()
            screenEntity = nil
        }
    }
    
    // MARK: - ARKit Head Tracking
    
    /// Starts the ARKit session for head tracking
    private func startARKitSession() async {
        do {
            // Check if world tracking is supported
            guard WorldTrackingProvider.isSupported else {
                print("[NativeImmersiveView] World tracking not supported on this device")
                return
            }
            
            try await arkitSession.run([worldTracking])
            print("[NativeImmersiveView] ARKit session started successfully")
        } catch {
            print("[NativeImmersiveView] Failed to start ARKit session: \(error)")
        }
    }
    
    /// Gets the current head (device) transform from ARKit
    private func getCurrentHeadTransform() async -> simd_float4x4? {
        guard let deviceAnchor = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) else {
            print("[NativeImmersiveView] Could not get device anchor")
            return nil
        }
        return deviceAnchor.originFromAnchorTransform
    }
    
    /// Extracts the position from a transform matrix
    private func getPosition(from transform: simd_float4x4) -> SIMD3<Float> {
        return SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
    }
    
    /// Extracts the yaw rotation (horizontal rotation) from a transform
    private func getYawRotation(from transform: simd_float4x4) -> Float {
        let forward = SIMD3<Float>(-transform.columns.2.x, 0, -transform.columns.2.z)
        let yaw = atan2(forward.x, forward.z)
        return yaw
    }
    
    /// Updates the video screen with recentering to face the user's current direction
    private func updateVideoScreenWithRecentering() async {
        guard let videoEntity = videoEntity else {
            print("[NativeImmersiveView] No video entity yet, skipping update")
            return
        }
        
        // Get the user's current head transform
        if let headTransform = await getCurrentHeadTransform() {
            // Get user's head position and yaw
            let headPosition = getPosition(from: headTransform)
            let yaw = getYawRotation(from: headTransform)
            
            // Position video entity at user's head (user is at center of sphere)
            videoEntity.position = headPosition
            
            // Rotate to face user's direction
            // The hemisphere center should align with where user is looking
            // Add π to flip from behind to front
            let rotation = simd_quatf(angle: -yaw + .pi, axis: SIMD3<Float>(0, 1, 0))
            videoEntity.orientation = rotation
            
            print("[NativeImmersiveView] Recentered video:")
            print("  - Position: (\(headPosition.x), \(headPosition.y), \(headPosition.z))")
            print("  - User Yaw: \(yaw * 180 / .pi)°")
        } else {
            // Fallback: reset to default
            print("[NativeImmersiveView] Could not get head transform, using default")
            videoEntity.position = SIMD3<Float>(0, 0, 0)
            videoEntity.orientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        }
        
        // Now update the screen
        updateVideoScreen()
    }
    
    private func updateVideoScreen() {
        guard let videoEntity = videoEntity else {
            print("[NativeImmersiveView] No video entity yet")
            return
        }
        
        guard isViewReady else {
            print("[NativeImmersiveView] View not ready")
            return
        }
        
        guard let player = videoManager.player else {
            print("[NativeImmersiveView] No player available")
            return
        }
        
        guard videoManager.isPlayerReady || videoManager.playbackState == .playing else {
            print("[NativeImmersiveView] Player not ready, state: \(videoManager.playbackState.rawValue)")
            return
        }
        
        let currentURL = videoManager.currentURL
        let format = videoManager.currentFormat
        
        // Check if we already have a screen for this video/format
        if screenEntity != nil && lastVideoURL == currentURL && lastVideoFormat == format {
            return
        }
        
        // Remove existing screen
        if let existingScreen = screenEntity {
            existingScreen.removeFromParent()
            print("[NativeImmersiveView] Removed existing screen")
        }
        
        print("[NativeImmersiveView] Creating screen for format: \(format.displayName)")
        print("[NativeImmersiveView] Is Immersive: \(format.isImmersive), Is Stereo: \(format.isStereoscopic)")
        
        // Create video material from the player
        let material = VideoMaterial(avPlayer: player)
        videoMaterial = material
        
        // Create appropriate mesh based on format
        guard let newScreen = createVideoScreen(format: format, material: material) else {
            print("[NativeImmersiveView] Failed to create video screen")
            return
        }
        
        newScreen.name = "VideoScreen"
        videoEntity.addChild(newScreen)
        
        screenEntity = newScreen
        lastVideoURL = currentURL
        lastVideoFormat = format
        
        print("[NativeImmersiveView] Video screen created successfully")
        
        // Start playback if not already playing
        if videoManager.playbackState != .playing {
            videoManager.startPlayback()
        }
    }
    
    // MARK: - Screen Creation
    
    private func createVideoScreen(format: VideoFormat, material: VideoMaterial) -> ModelEntity? {
        let mesh: MeshResource
        var position = SIMD3<Float>(0, 0, 0)
        var scale = SIMD3<Float>(1, 1, 1)
        
        switch format {
        case .mono2D:
            // Flat screen in front of user
            mesh = MeshResource.generatePlane(width: 4.0, height: 2.25)
            position = SIMD3<Float>(0, 1.5, -3)
            
        case .sideBySide3D, .overUnder3D:
            // Flat 3D content
            mesh = MeshResource.generatePlane(width: 4.0, height: 2.25)
            position = SIMD3<Float>(0, 1.5, -3)
            
        case .hemisphere180:
            // 180° mono hemisphere
            mesh = createHemisphereMesh(radius: 10.0, segments: 128, uvMode: .full)
            scale = SIMD3<Float>(-1, 1, 1) // Flip for inside-out view
            
        case .hemisphere180SBS:
            // 180° Stereo SBS - map LEFT half only for mono view from left eye
            print("[NativeImmersiveView] Creating 180° Stereo SBS hemisphere (left eye view)")
            mesh = createHemisphereMesh(radius: 10.0, segments: 128, uvMode: .leftHalf)
            scale = SIMD3<Float>(-1, 1, 1) // Flip for inside-out view
            
        case .sphere360:
            // 360° mono sphere
            mesh = createSphereMesh(radius: 10.0, segments: 128, uvMode: .full)
            scale = SIMD3<Float>(-1, 1, 1)
            
        case .sphere360OU:
            // 360° Stereo Over-Under - map TOP half for left eye
            print("[NativeImmersiveView] Creating 360° Stereo OU sphere (left eye view)")
            mesh = createSphereMesh(radius: 10.0, segments: 128, uvMode: .topHalf)
            scale = SIMD3<Float>(-1, 1, 1)
            
        case .sphere360SBS:
            // 360° Stereo SBS - map LEFT half for left eye
            print("[NativeImmersiveView] Creating 360° Stereo SBS sphere (left eye view)")
            mesh = createSphereMesh(radius: 10.0, segments: 128, uvMode: .leftHalf)
            scale = SIMD3<Float>(-1, 1, 1)
        }
        
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = position
        entity.scale = scale
        
        return entity
    }
    
    // MARK: - UV Mapping Mode
    
    enum UVMode {
        case full       // Full texture
        case leftHalf   // Left half (for SBS left eye)
        case rightHalf  // Right half (for SBS right eye)
        case topHalf    // Top half (for OU left eye)
        case bottomHalf // Bottom half (for OU right eye)
    }
    
    // MARK: - Hemisphere Mesh Generation
    
    /// Creates a hemisphere mesh for 180° video content.
    /// The hemisphere covers the front 180° FOV.
    private func createHemisphereMesh(radius: Float, segments: Int, uvMode: UVMode) -> MeshResource {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        
        let horizontalSegments = segments
        let verticalSegments = segments / 2
        
        // Generate vertices for hemisphere (front 180°)
        for y in 0...verticalSegments {
            let v = Float(y) / Float(verticalSegments)
            let phi = v * .pi  // 0 to π (top to bottom)
            
            for x in 0...horizontalSegments {
                let u = Float(x) / Float(horizontalSegments)
                let theta = (u - 0.5) * .pi  // -π/2 to +π/2
                
                let sinPhi = sin(phi)
                let cosPhi = cos(phi)
                let sinTheta = sin(theta)
                let cosTheta = cos(theta)
                
                let px = radius * sinPhi * sinTheta
                let py = radius * cosPhi
                let pz = -radius * sinPhi * cosTheta
                
                positions.append(SIMD3<Float>(px, py, pz))
                normals.append(SIMD3<Float>(sinPhi * sinTheta, cosPhi, -sinPhi * cosTheta))
                
                // UV mapping based on mode
                let (uvU, uvV) = calculateUV(u: u, v: v, mode: uvMode)
                uvs.append(SIMD2<Float>(uvU, uvV))
            }
        }
        
        // Generate triangle indices
        let vertsPerRow = horizontalSegments + 1
        for y in 0..<verticalSegments {
            for x in 0..<horizontalSegments {
                let topLeft = UInt32(y * vertsPerRow + x)
                let topRight = topLeft + 1
                let bottomLeft = UInt32((y + 1) * vertsPerRow + x)
                let bottomRight = bottomLeft + 1
                
                indices.append(contentsOf: [topLeft, bottomLeft, topRight])
                indices.append(contentsOf: [topRight, bottomLeft, bottomRight])
            }
        }
        
        var meshDescriptor = MeshDescriptor()
        meshDescriptor.positions = MeshBuffers.Positions(positions)
        meshDescriptor.normals = MeshBuffers.Normals(normals)
        meshDescriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        meshDescriptor.primitives = .triangles(indices)
        
        do {
            return try MeshResource.generate(from: [meshDescriptor])
        } catch {
            print("[NativeImmersiveView] Failed to create hemisphere mesh: \(error)")
            return MeshResource.generatePlane(width: 4.0, height: 2.25)
        }
    }
    
    // MARK: - Sphere Mesh Generation
    
    /// Creates a sphere mesh for 360° video content.
    private func createSphereMesh(radius: Float, segments: Int, uvMode: UVMode) -> MeshResource {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        
        let horizontalSegments = segments
        let verticalSegments = segments / 2
        
        // Generate vertices for full sphere
        for y in 0...verticalSegments {
            let v = Float(y) / Float(verticalSegments)
            let phi = v * .pi  // 0 to π
            
            for x in 0...horizontalSegments {
                let u = Float(x) / Float(horizontalSegments)
                let theta = u * 2 * .pi  // 0 to 2π
                
                let sinPhi = sin(phi)
                let cosPhi = cos(phi)
                let sinTheta = sin(theta)
                let cosTheta = cos(theta)
                
                let px = radius * sinPhi * sinTheta
                let py = radius * cosPhi
                let pz = radius * sinPhi * cosTheta
                
                positions.append(SIMD3<Float>(px, py, pz))
                normals.append(SIMD3<Float>(sinPhi * sinTheta, cosPhi, sinPhi * cosTheta))
                
                // UV mapping based on mode
                let (uvU, uvV) = calculateUV(u: u, v: v, mode: uvMode)
                uvs.append(SIMD2<Float>(uvU, uvV))
            }
        }
        
        // Generate triangle indices
        let vertsPerRow = horizontalSegments + 1
        for y in 0..<verticalSegments {
            for x in 0..<horizontalSegments {
                let topLeft = UInt32(y * vertsPerRow + x)
                let topRight = topLeft + 1
                let bottomLeft = UInt32((y + 1) * vertsPerRow + x)
                let bottomRight = bottomLeft + 1
                
                indices.append(contentsOf: [topLeft, bottomLeft, topRight])
                indices.append(contentsOf: [topRight, bottomLeft, bottomRight])
            }
        }
        
        var meshDescriptor = MeshDescriptor()
        meshDescriptor.positions = MeshBuffers.Positions(positions)
        meshDescriptor.normals = MeshBuffers.Normals(normals)
        meshDescriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        meshDescriptor.primitives = .triangles(indices)
        
        do {
            return try MeshResource.generate(from: [meshDescriptor])
        } catch {
            print("[NativeImmersiveView] Failed to create sphere mesh: \(error)")
            return MeshResource.generateSphere(radius: radius)
        }
    }
    
    // MARK: - UV Calculation
    
    /// Calculates UV coordinates based on mapping mode.
    /// For SBS stereo, maps hemisphere to only left half of texture (left eye view).
    private func calculateUV(u: Float, v: Float, mode: UVMode) -> (Float, Float) {
        // Flip V for correct vertical orientation (equirectangular videos have V=0 at top)
        let flippedV = 1.0 - v
        
        switch mode {
        case .full:
            return (u, flippedV)
        case .leftHalf:
            // Map U: 0-1 to 0-0.5 (left half of SBS video)
            return (u * 0.5, flippedV)
        case .rightHalf:
            // Map U: 0-1 to 0.5-1.0 (right half of SBS video)
            return (0.5 + u * 0.5, flippedV)
        case .topHalf:
            // Map V: 0-1 to 0-0.5 (top half of OU video)
            return (u, flippedV * 0.5)
        case .bottomHalf:
            // Map V: 0-1 to 0.5-1.0 (bottom half of OU video)
            return (u, 0.5 + flippedV * 0.5)
        }
    }
}

// MARK: - Preview

#Preview(immersionStyle: .full) {
    NativeImmersiveView()
        .environmentObject(AppState())
        .environmentObject(NativeVideoPlayerManager())
}
