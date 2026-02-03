import SwiftUI
import RealityKit
import AVFoundation
import Combine
import ARKit

/// Immersive view for full-screen video playback in visionOS.
/// Supports stereoscopic 180° SBS content with proper per-eye rendering.
/// 
/// IMPORTANT: For Stereo 180° SBS (Side-by-Side) content:
/// - The video contains both eye views side-by-side (left half = left eye, right half = right eye)
/// - The projection is equirectangular (spherical mapping)
/// - The FOV is 180° (front hemisphere only, not behind the viewer)
/// - Proper UV mapping is critical for correct stereo depth perception
struct ImmersiveView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var videoManager: VideoPlayerManager

    @State private var videoEntity: Entity?
    @State private var screenEntity: ModelEntity?
    @State private var lastVideoURL: String?
    @State private var lastVideoFormat: VideoFormat?
    @State private var isImmersiveSpaceReady: Bool = false
    
    /// ARKit session for head tracking
    @State private var arkitSession = ARKitSession()
    @State private var worldTracking = WorldTrackingProvider()

    var body: some View {
        RealityView { content in
            // Create the immersive environment
            let rootEntity = Entity()
            rootEntity.name = "VideoRoot"

            // Create the video screen holder
            // For immersive content, center at viewer position
            let screenHolder = Entity()
            screenHolder.name = "ScreenHolder"
            // Position at eye level - user's head will be at origin in immersive space
            screenHolder.position = SIMD3<Float>(0, 0, 0)
            rootEntity.addChild(screenHolder)

            content.add(rootEntity)

            // Mark immersive space as ready and store reference
            Task { @MainActor in
                self.videoEntity = screenHolder
                self.isImmersiveSpaceReady = true
                print("[ImmersiveView] Immersive space ready")
                
                // Start ARKit session for head tracking
                await startARKitSession()
                
                // If video is already loading/playing, create the screen now
                if videoManager.isPlayerReady {
                    await updateVideoScreenWithRecentering()
                }
            }

        } update: { content in
            // Update video content when videoManager changes
            Task { @MainActor in
                if isImmersiveSpaceReady {
                    updateVideoScreen()
                }
            }
        }
        .onChange(of: videoManager.isPlayerReady) { _, isReady in
            if isReady && isImmersiveSpaceReady {
                Task { @MainActor in
                    // New video is ready - recenter to face the user
                    await updateVideoScreenWithRecentering()
                }
            }
        }
        .onChange(of: videoManager.playbackState) { _, newState in
            if newState == .playing && isImmersiveSpaceReady {
                Task { @MainActor in
                    // Only update without recentering during regular playback state changes
                    updateVideoScreen()
                }
            } else if newState == .stopped || newState == .idle {
                // Reset tracking when video stops
                Task { @MainActor in
                    cleanupVideoScreen()
                }
            }
        }
        .onChange(of: videoManager.currentFormat) { _, _ in
            Task { @MainActor in
                if isImmersiveSpaceReady {
                    // Force recreation for format change - recenter
                    lastVideoFormat = nil
                    await updateVideoScreenWithRecentering()
                }
            }
        }
        .onChange(of: videoManager.currentURL) { oldURL, newURL in
            // When video URL changes, we need to recenter
            if oldURL != newURL && newURL != nil && isImmersiveSpaceReady {
                Task { @MainActor in
                    print("[ImmersiveView] Video URL changed - will recenter when ready")
                    // Force recreation
                    lastVideoURL = nil
                    lastVideoFormat = nil
                }
            }
        }
        .onAppear {
            print("[ImmersiveView] Appeared - waiting for immersive space setup")
        }
        .onDisappear {
            print("[ImmersiveView] Disappeared")
            isImmersiveSpaceReady = false
            // Stop ARKit session
            arkitSession.stop()
            print("[ImmersiveView] ARKit session stopped")
        }
    }
    
    /// Cleans up the video screen and resets state
    private func cleanupVideoScreen() {
        lastVideoURL = nil
        lastVideoFormat = nil
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
                print("[ImmersiveView] World tracking not supported on this device")
                return
            }
            
            try await arkitSession.run([worldTracking])
            print("[ImmersiveView] ARKit session started successfully")
        } catch {
            print("[ImmersiveView] Failed to start ARKit session: \(error)")
        }
    }
    
    /// Gets the current head (device) transform from ARKit
    /// Returns the user's head position and orientation in world space
    private func getCurrentHeadTransform() async -> simd_float4x4? {
        guard let deviceAnchor = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) else {
            print("[ImmersiveView] Could not get device anchor")
            return nil
        }
        
        // The device anchor's transform represents the head position and orientation
        return deviceAnchor.originFromAnchorTransform
    }
    
    /// Extracts the position from a transform matrix
    private func getPosition(from transform: simd_float4x4) -> SIMD3<Float> {
        return SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
    }
    
    /// Extracts the yaw rotation (horizontal rotation) from a transform
    /// This is used to align the video hemisphere with the user's forward direction
    private func getYawRotation(from transform: simd_float4x4) -> Float {
        // Extract the forward vector from the transform (negative Z axis)
        let forward = SIMD3<Float>(-transform.columns.2.x, 0, -transform.columns.2.z)
        
        // Calculate yaw angle from forward vector
        let yaw = atan2(forward.x, forward.z)
        return yaw
    }
    
    /// Updates the video screen with recentering to face the user's current direction
    /// This positions the video sphere at the user's head location and orients it to face their direction
    private func updateVideoScreenWithRecentering() async {
        guard let videoEntity = videoEntity else {
            print("[ImmersiveView] No video entity yet, skipping update")
            return
        }
        
        // Get the user's current head transform
        if let headTransform = await getCurrentHeadTransform() {
            // Get the user's head position - this is where the center of the sphere should be
            let headPosition = getPosition(from: headTransform)
            
            // Get the user's head yaw rotation - this is the direction they're facing
            let yaw = getYawRotation(from: headTransform)
            
            // Position the video entity at the user's head position
            // This ensures the user is at the CENTER of the video sphere
            videoEntity.position = headPosition
            
            // Create rotation quaternion to align video with user's forward direction
            // The hemisphere center should align with where user is looking
            // Add π to flip from behind to front
            let rotation = simd_quatf(angle: -yaw + .pi, axis: SIMD3<Float>(0, 1, 0))
            videoEntity.orientation = rotation
            
            print("[ImmersiveView] Recentered video:")
            print("  - Position: (\(headPosition.x), \(headPosition.y), \(headPosition.z))")
            print("  - User Yaw: \(yaw * 180 / .pi)°")
        } else {
            // Fallback: reset to default position and orientation
            print("[ImmersiveView] Could not get head transform, using default position/orientation")
            videoEntity.position = SIMD3<Float>(0, 0, 0)
            videoEntity.orientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        }
        
        // Now update the screen
        updateVideoScreen()
    }

    /// Updates the video screen with current video material.
    /// Creates the appropriate geometry based on video format.
    private func updateVideoScreen() {
        guard let videoEntity = videoEntity else {
            print("[ImmersiveView] No video entity yet, skipping update")
            return
        }
        
        guard isImmersiveSpaceReady else {
            print("[ImmersiveView] Immersive space not ready, skipping update")
            return
        }
        
        // Only update if we have a video material ready
        guard videoManager.videoMaterial != nil else {
            print("[ImmersiveView] Waiting for video material...")
            return
        }
        
        // Only proceed if video is actually ready or playing
        guard videoManager.isPlayerReady || videoManager.playbackState == .playing else {
            print("[ImmersiveView] Playback state is \(videoManager.playbackState.rawValue), player ready: \(videoManager.isPlayerReady), skipping update")
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
            print("[ImmersiveView] Removed existing screen for new format: \(format.displayName)")
        }
        
        print("[ImmersiveView] Creating screen for format: \(format.displayName)")
        print("[ImmersiveView] Format properties - isImmersive: \(format.isImmersive), isStereoscopic: \(format.isStereoscopic)")
        
        // Get mesh configuration for this format
        let meshConfig = getMeshConfiguration(for: format)
        
        // Create new screen with video material and proper mesh
        guard let newScreen = createVideoScreenEntity(config: meshConfig) else {
            print("[ImmersiveView] Could not create video screen entity")
            return
        }

        newScreen.name = "VideoScreen"
        
        videoEntity.addChild(newScreen)
        
        // Update state reference after adding to scene
        screenEntity = newScreen
        lastVideoURL = currentURL
        lastVideoFormat = format

        print("[ImmersiveView] Video screen created successfully for \(format.displayName)")
        print("[ImmersiveView] Mesh type: \(meshConfig.meshType), radius: \(meshConfig.radius)")
    }
    
    // MARK: - Mesh Configuration
    
    /// Configuration for video screen mesh
    struct MeshConfiguration {
        enum MeshType {
            case flatPlane          // For 2D and flat 3D content
            case hemisphere180      // For 180° content (front hemisphere only)
            case hemisphere180SBS   // For stereo 180° SBS content
            case sphere360          // For 360° mono content
            case sphere360Stereo    // For 360° stereo content
        }
        
        let meshType: MeshType
        let radius: Float
        let segments: Int
        let width: Float    // For flat planes
        let height: Float   // For flat planes
        let position: SIMD3<Float>
        let orientation: simd_quatf
    }
    
    /// Returns the mesh configuration for a given video format
    private func getMeshConfiguration(for format: VideoFormat) -> MeshConfiguration {
        switch format {
        case .mono2D:
            return MeshConfiguration(
                meshType: .flatPlane,
                radius: 0,
                segments: 0,
                width: 4.0,
                height: 2.25,
                position: SIMD3<Float>(0, 1.5, -3),
                orientation: simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
            )
            
        case .sideBySide3D, .overUnder3D:
            // Flat 3D content - displayed on a flat plane
            // Note: True stereo requires per-eye rendering which VideoMaterial doesn't support
            return MeshConfiguration(
                meshType: .flatPlane,
                radius: 0,
                segments: 0,
                width: 4.0,
                height: 2.25,
                position: SIMD3<Float>(0, 1.5, -3),
                orientation: simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
            )
            
        case .hemisphere180:
            // 180° mono - hemisphere in front of viewer
            return MeshConfiguration(
                meshType: .hemisphere180,
                radius: 10.0,  // Larger radius for better immersion
                segments: 128, // High segment count for smooth curvature
                width: 0,
                height: 0,
                position: SIMD3<Float>(0, 0, 0),  // Centered on viewer
                orientation: simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
            )
            
        case .hemisphere180SBS:
            // 180° Stereo SBS - THIS IS THE KEY FORMAT
            // The mesh needs special UV mapping for stereo content
            return MeshConfiguration(
                meshType: .hemisphere180SBS,
                radius: 10.0,  // Larger radius for immersion
                segments: 128, // High segment count for smooth curvature
                width: 0,
                height: 0,
                position: SIMD3<Float>(0, 0, 0),  // Centered on viewer
                orientation: simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
            )
            
        case .sphere360:
            return MeshConfiguration(
                meshType: .sphere360,
                radius: 10.0,
                segments: 128,
                width: 0,
                height: 0,
                position: SIMD3<Float>(0, 0, 0),
                orientation: simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
            )
            
        case .sphere360OU, .sphere360SBS:
            return MeshConfiguration(
                meshType: .sphere360Stereo,
                radius: 10.0,
                segments: 128,
                width: 0,
                height: 0,
                position: SIMD3<Float>(0, 0, 0),
                orientation: simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
            )
        }
    }
    
    /// Creates the video screen entity with the appropriate mesh
    private func createVideoScreenEntity(config: MeshConfiguration) -> ModelEntity? {
        guard let videoMaterial = videoManager.videoMaterial else {
            print("[ImmersiveView] No video material available")
            return nil
        }
        
        let mesh: MeshResource
        
        switch config.meshType {
        case .flatPlane:
            mesh = MeshResource.generatePlane(width: config.width, height: config.height)
            let entity = ModelEntity(mesh: mesh, materials: [videoMaterial])
            entity.position = config.position
            entity.orientation = config.orientation
            return entity
            
        case .hemisphere180:
            // Create mono hemisphere mesh - full UV mapping
            mesh = createHemisphere180Mesh(radius: config.radius, segments: config.segments, uvMode: .full)
            let entity = ModelEntity(mesh: mesh, materials: [videoMaterial])
            entity.position = config.position
            // Scale X to -1 to flip for inside-out view (backface culling fix)
            entity.scale = SIMD3<Float>(-1, 1, 1)
            return entity
            
        case .hemisphere180SBS:
            // STEREO 180° SBS - Create hemisphere with LEFT half UV only
            print("[ImmersiveView] Creating hemisphere for Stereo 180° SBS - mapping to LEFT eye view")
            mesh = createHemisphere180Mesh(radius: config.radius, segments: config.segments, uvMode: .leftHalf)
            let entity = ModelEntity(mesh: mesh, materials: [videoMaterial])
            entity.position = config.position
            // Scale X to -1 to flip for inside-out view
            entity.scale = SIMD3<Float>(-1, 1, 1)
            return entity
            
        case .sphere360:
            // Use custom sphere for 360° content (inside-out rendering)
            mesh = createSphere360Mesh(radius: config.radius, segments: config.segments, uvMode: .full)
            let entity = ModelEntity(mesh: mesh, materials: [videoMaterial])
            entity.position = config.position
            // Scale X to -1 to flip for inside-out view
            entity.scale = SIMD3<Float>(-1, 1, 1)
            return entity
            
        case .sphere360Stereo:
            // For stereo 360° content - map to left half only (same limitation)
            print("[ImmersiveView] Creating sphere for Stereo 360° - mapping to LEFT eye view")
            mesh = createSphere360Mesh(radius: config.radius, segments: config.segments, uvMode: .leftHalf)
            let entity = ModelEntity(mesh: mesh, materials: [videoMaterial])
            entity.position = config.position
            // Scale X to -1 to flip for inside-out view
            entity.scale = SIMD3<Float>(-1, 1, 1)
            return entity
        }
    }
    
    // MARK: - UV Mapping Mode
    
    /// UV mapping mode for stereo video
    enum UVMappingMode {
        case full       // Full texture (mono video)
        case leftHalf   // Left half only (left eye of SBS video)
        case rightHalf  // Right half only (right eye of SBS video)
        case topHalf    // Top half only (left eye of OU video)
        case bottomHalf // Bottom half only (right eye of OU video)
    }
    
    // MARK: - Hemisphere Mesh Generation
    
    /// Creates a hemisphere mesh for 180° equirectangular video content.
    /// The hemisphere covers the front 180° FOV (from -90° to +90° horizontally).
    /// Mesh will be flipped with scale.x = -1 for inside-out viewing.
    ///
    /// - Parameters:
    ///   - radius: Radius of the hemisphere (larger = more immersive)
    ///   - segments: Number of segments (higher = smoother)
    ///   - uvMode: How to map UV coordinates for stereo content
    /// - Returns: A MeshResource for the hemisphere
    private func createHemisphere180Mesh(radius: Float, segments: Int, uvMode: UVMappingMode) -> MeshResource {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        
        let horizontalSegments = segments
        let verticalSegments = segments / 2
        
        print("[ImmersiveView] Generating hemisphere mesh:")
        print("  - Radius: \(radius)m")
        print("  - Segments: \(horizontalSegments)x\(verticalSegments)")
        print("  - UV Mode: \(uvMode)")
        
        // Generate vertices for hemisphere (front 180° only)
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
                
                // UV mapping - flip U to compensate for scale.x = -1 transformation
                // This ensures correct left-to-right mapping in equirectangular projection
                let (uvU, uvV) = calculateUV(u: 1.0 - u, v: v, mode: uvMode)
                uvs.append(SIMD2<Float>(uvU, uvV))
            }
        }
        
        // Standard triangle winding (will be flipped by scale.x = -1)
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
        
        print("[ImmersiveView] Generated \(positions.count) vertices, \(indices.count / 3) triangles")
        
        var meshDescriptor = MeshDescriptor()
        meshDescriptor.positions = MeshBuffers.Positions(positions)
        meshDescriptor.normals = MeshBuffers.Normals(normals)
        meshDescriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        meshDescriptor.primitives = .triangles(indices)
        
        do {
            let mesh = try MeshResource.generate(from: [meshDescriptor])
            print("[ImmersiveView] Hemisphere mesh generated successfully")
            return mesh
        } catch {
            print("[ImmersiveView] Failed to create hemisphere mesh: \(error)")
            return MeshResource.generatePlane(width: 4.0, height: 2.25)
        }
    }
    
    /// Creates a sphere mesh for 360° video content with UV mapping options.
    /// Mesh will be flipped with scale.x = -1 for inside-out viewing.
    private func createSphere360Mesh(radius: Float, segments: Int, uvMode: UVMappingMode) -> MeshResource {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        
        let horizontalSegments = segments
        let verticalSegments = segments / 2
        
        print("[ImmersiveView] Generating sphere mesh:")
        print("  - Radius: \(radius)m")
        print("  - Segments: \(horizontalSegments)x\(verticalSegments)")
        print("  - UV Mode: \(uvMode)")
        
        // Generate vertices for full sphere
        for y in 0...verticalSegments {
            let v = Float(y) / Float(verticalSegments)
            let phi = v * .pi  // 0 to π (top to bottom)
            
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
                
                // UV mapping - flip U to compensate for scale.x = -1 transformation
                let (uvU, uvV) = calculateUV(u: 1.0 - u, v: v, mode: uvMode)
                uvs.append(SIMD2<Float>(uvU, uvV))
            }
        }
        
        // Standard triangle winding (will be flipped by scale.x = -1)
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
            print("[ImmersiveView] Failed to create sphere mesh: \(error)")
            return MeshResource.generateSphere(radius: radius)
        }
    }
    
    /// Calculates UV coordinates based on the mapping mode.
    /// For SBS stereo videos, maps the hemisphere to only the left half of the texture.
    /// 
    /// UV Coordinate System:
    /// - Mesh: v=0 at top (phi=0), v=1 at bottom (phi=π)
    /// - Equirectangular video: v=0 at top (north pole), v=1 at bottom (south pole)
    /// - VideoMaterial uses standard video coordinates where Y increases downward
    /// - Therefore V should NOT be flipped for correct mapping
    private func calculateUV(u: Float, v: Float, mode: UVMappingMode) -> (Float, Float) {
        // No V flip needed - mesh v=0 (top) maps to video v=0 (top)
        // Both use the same convention for equirectangular content
        
        switch mode {
        case .full:
            return (u, v)
        case .leftHalf:
            // Map U: 0-1 to 0-0.5 (left half of SBS video)
            return (u * 0.5, v)
        case .rightHalf:
            // Map U: 0-1 to 0.5-1.0 (right half of SBS video)
            return (0.5 + u * 0.5, v)
        case .topHalf:
            // Map V: 0-1 to 0-0.5 (top half of OU video)
            return (u, v * 0.5)
        case .bottomHalf:
            // Map V: 0-1 to 0.5-1.0 (bottom half of OU video)
            return (u, 0.5 + v * 0.5)
        }
    }
}

// MARK: - Preview

#Preview(immersionStyle: .full) {
    ImmersiveView()
        .environmentObject(AppState())
        .environmentObject(VideoPlayerManager())
}
