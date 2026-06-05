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

    /// Debug/test settings (live UV override + diagnostics panel).
    @ObservedObject private var debug = StereoDebugSettings.shared

    @State private var videoEntity: Entity?
    @State private var screenEntity: ModelEntity?
    @State private var diagnosticsEntity: Entity?
    @State private var lastVideoURL: String?
    @State private var lastVideoFormat: VideoFormat?
    @State private var lastUVOverride: UVOverride = .auto
    @State private var isViewReady: Bool = false
    @State private var videoMaterial: VideoMaterial?

    /// Active APMP stereo renderer (visionOS 26+), stored type-erased so the
    /// property itself needs no availability annotation.
    @State private var stereoRenderer: AnyObject?

    /// Identity of the video+format the live stereo renderer is currently
    /// rendering. Used to keep `updateVideoScreen()` idempotent independently of
    /// the `lastVideo*` fields (which several `onChange` handlers reset mid-play),
    /// so a working per-eye pipeline is never torn down and rebuilt while the same
    /// video keeps playing.
    @State private var activeStereoKey: String?
    
    /// ARKit session for head tracking
    @State private var arkitSession = ARKitSession()
    @State private var worldTracking = WorldTrackingProvider()
    @State private var isARKitReady = false
    
    // MARK: - Constants
    
    /// Rotation offset to align hemisphere front with user's gaze direction.
    /// This is needed because:
    /// 1. Hemisphere mesh is generated facing -Z
    /// 2. Mesh is flipped with scale.x = -1 for inside-out viewing
    /// Result: -yaw + π places video center directly in front of user
    private let meshAlignmentOffset: Float = .pi
    
    var body: some View {
        RealityView { content, attachments in
            // Create the immersive environment
            let rootEntity = Entity()
            rootEntity.name = "VideoRoot"
            
            // Create the video screen holder centered on viewer
            let screenHolder = Entity()
            screenHolder.name = "ScreenHolder"
            screenHolder.position = SIMD3<Float>(0, 0, 0)
            rootEntity.addChild(screenHolder)

            // Attach the debug diagnostics panel (fixed in front of the user).
            if let diagEntity = attachments.entity(for: "diagnostics") {
                diagEntity.name = "DiagnosticsPanel"
                diagEntity.position = SIMD3<Float>(0, 1.2, -1.5)
                diagEntity.isEnabled = debug.testModeEnabled && debug.showDiagnostics
                rootEntity.addChild(diagEntity)
                self.diagnosticsEntity = diagEntity
            }

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
        } update: { content, attachments in
            Task { @MainActor in
                if isViewReady {
                    diagnosticsEntity?.isEnabled = debug.testModeEnabled && debug.showDiagnostics
                    updateVideoScreen()
                }
            }
        } attachments: {
            Attachment(id: "diagnostics") {
                StereoDiagnosticsPanel(debug: debug,
                                       currentFormat: videoManager.currentFormat)
            }
        }
        .onChange(of: debug.uvOverride) { _, _ in
            // Live re-map of the screen when the QA override changes.
            Task { @MainActor in
                if isViewReady {
                    lastUVOverride = .auto  // force recreation
                    lastVideoFormat = nil
                    updateVideoScreen()
                }
            }
        }
        .onChange(of: debug.eyeCompareEnabled) { _, _ in
            // Rebuild the screen to enter/leave the debug comparison view.
            Task { @MainActor in
                if isViewReady {
                    teardownStereoRenderer()
                    if let existing = screenEntity {
                        existing.removeFromParent()
                        screenEntity = nil
                    }
                    lastVideoFormat = nil
                    updateVideoScreen()
                }
            }
        }
        .onChange(of: debug.trueStereoEnabled) { _, _ in
            // Switch between the APMP stereo path and the legacy path live.
            Task { @MainActor in
                if isViewReady {
                    teardownStereoRenderer()
                    if let existing = screenEntity {
                        existing.removeFromParent()
                        screenEntity = nil
                    }
                    lastVideoFormat = nil
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
            isARKitReady = false
            teardownStereoRenderer()
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
        teardownStereoRenderer()
        if let existingScreen = screenEntity {
            existingScreen.removeFromParent()
            screenEntity = nil
        }
    }

    /// Stops and releases any active APMP stereo renderer.
    private func teardownStereoRenderer() {
        if #available(visionOS 26.0, *) {
            (stereoRenderer as? APMPStereoRenderer)?.stop()
        }
        stereoRenderer = nil
        activeStereoKey = nil
    }

    /// Stable identity for a video+format pairing, used to detect when an already
    /// running stereo renderer is still correct for the current content.
    private func stereoKey(url: String?, format: VideoFormat) -> String {
        "\(url ?? "nil")|\(format.displayName)"
    }

    /// Builds a `VideoPlayerComponent`-backed entity driven by an APMP stereo
    /// renderer, when the opt-in true-stereo mode is on and the format is a
    /// frame-packed stereo type. Returns nil to fall back to the legacy path.
    private func makeStereoScreenIfEnabled(format: VideoFormat, player: AVPlayer) -> ModelEntity? {
        guard debug.trueStereoEnabled else {
            RemoteLog("APMP", "Skipped: True 3D toggle is OFF → using legacy single-view (NO depth). Format=\(format.displayName)")
            return nil
        }
        guard #available(visionOS 26.0, *) else {
            RemoteLog("APMP", "FALLBACK: device is below visionOS 26 → per-eye APMP unavailable → legacy single-view (NO depth). Format=\(format.displayName)")
            return nil
        }
        #if targetEnvironment(simulator)
        // The simulator's VideoPlayerComponent + AVSampleBufferVideoRenderer pipeline
        // emits IQ-CA(-19230)/VRP(-12852) errors and shows NO image (audio only).
        // It also renders a single eye, so stereo can't be verified here anyway.
        // Use the legacy path on simulator so the picture is visible for local dev.
        RemoteLog("APMP", "FALLBACK: SIMULATOR detected → APMP renders no image here. Using legacy path (picture visible, mono). Stereo is only testable on a real device.")
        return nil
        #else
        guard let config = APMPStereoRenderer.configuration(for: format) else {
            // Not a frame-packed stereo format (e.g. mono) — nothing to inject.
            RemoteLog("APMP", "Skipped: format \(format.displayName) is not frame-packed stereo (no SBS/OU half to split). Legacy path used.")
            return nil
        }
        RemoteLog("APMP", "Engaging true per-eye stereo. packing=\(config.packing), projection=\(config.projection), format=\(format.displayName)")
        if videoManager.hasNativeStereoMetadata {
            RemoteLog("APMP", "WARNING: video already has NATIVE stereo metadata (likely MV-HEVC). Injecting SBS/OU packing on top is probably WRONG — the system may already split eyes. If depth looks bad, set format to mono2D so the native pipeline handles per-eye.")
        }

        // Replace any previous renderer.
        teardownStereoRenderer()

        let renderer = APMPStereoRenderer(packing: config.packing, projection: config.projection)
        let entity = ModelEntity()
        // The APMP projection metadata (rectilinear / 180° / 360°) drives the
        // geometry and per-eye stereo automatically.
        let component = VideoPlayerComponent(videoRenderer: renderer.videoRenderer)
        entity.components.set(component)

        renderer.start(player: player)
        stereoRenderer = renderer
        return entity
        #endif
    }

    // MARK: - Debug: Eye Comparison (simulator)

    /// Builds two flat panels showing the left-eye and right-eye source crops
    /// side-by-side (or top/bottom for OU), with labels. Both are visible to
    /// the single simulator eye, so you can confirm the two eyes get different,
    /// correctly-cropped images. Debug only.
    private func createEyeCompareScreen(format: VideoFormat, player: AVPlayer) -> ModelEntity? {
        let container = ModelEntity()

        let isOverUnder = (format == .overUnder3D || format == .sphere360OU)
        let leftMode: UVMode = isOverUnder ? .topHalf : .leftHalf
        let rightMode: UVMode = isOverUnder ? .bottomHalf : .rightHalf

        let panelW: Float = 1.6
        let panelH: Float = 1.6
        let centerY: Float = 1.5
        let z: Float = -2.6
        let offsetX: Float = panelW / 2 + 0.12  // small gap between panels

        let leftPanel = ModelEntity(mesh: createFlatMesh(width: panelW, height: panelH, uvMode: leftMode),
                                    materials: [VideoMaterial(avPlayer: player)])
        leftPanel.position = SIMD3<Float>(-offsetX, centerY, z)

        let rightPanel = ModelEntity(mesh: createFlatMesh(width: panelW, height: panelH, uvMode: rightMode),
                                     materials: [VideoMaterial(avPlayer: player)])
        rightPanel.position = SIMD3<Float>(offsetX, centerY, z)

        container.addChild(leftPanel)
        container.addChild(rightPanel)

        let labelY = centerY + panelH / 2 + 0.12
        container.addChild(makeLabel(isOverUnder ? "LEFT EYE (top, layer 0)" : "LEFT EYE (layer 0)",
                                     x: -offsetX, y: labelY, z: z))
        container.addChild(makeLabel(isOverUnder ? "RIGHT EYE (bottom, layer 1)" : "RIGHT EYE (layer 1)",
                                     x: offsetX, y: labelY, z: z))
        return container
    }

    /// A flat quad facing the user, with UV cropped per `uvMode`.
    private func createFlatMesh(width: Float, height: Float, uvMode: UVMode) -> MeshResource {
        let hw = width / 2
        let hh = height / 2
        let positions: [SIMD3<Float>] = [
            SIMD3<Float>(-hw, -hh, 0), // bottom-left
            SIMD3<Float>( hw, -hh, 0), // bottom-right
            SIMD3<Float>( hw,  hh, 0), // top-right
            SIMD3<Float>(-hw,  hh, 0)  // top-left
        ]
        let normals = [SIMD3<Float>](repeating: SIMD3<Float>(0, 0, 1), count: 4)

        // Video texture origin (0,0) is top-left, so top vertices map to v=0.
        func uv(_ u: Float, _ v: Float) -> SIMD2<Float> {
            switch uvMode {
            case .full:       return SIMD2<Float>(u, v)
            case .leftHalf:   return SIMD2<Float>(u * 0.5, v)
            case .rightHalf:  return SIMD2<Float>(0.5 + u * 0.5, v)
            case .topHalf:    return SIMD2<Float>(u, v * 0.5)
            case .bottomHalf: return SIMD2<Float>(u, 0.5 + v * 0.5)
            }
        }
        let uvs = [uv(0, 1), uv(1, 1), uv(1, 0), uv(0, 0)]
        let indices: [UInt32] = [0, 1, 2, 0, 2, 3]

        var descriptor = MeshDescriptor()
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        descriptor.primitives = .triangles(indices)

        return (try? MeshResource.generate(from: [descriptor]))
            ?? MeshResource.generatePlane(width: width, height: height)
    }

    /// A small white 3D text label centered roughly at the given position.
    private func makeLabel(_ text: String, x: Float, y: Float, z: Float) -> ModelEntity {
        let mesh = MeshResource.generateText(
            text,
            extrusionDepth: 0.005,
            font: .systemFont(ofSize: 0.1),
            containerFrame: CGRect(x: -0.8, y: -0.1, width: 1.6, height: 0.2),
            alignment: .center,
            lineBreakMode: .byTruncatingTail
        )
        let material = SimpleMaterial(color: .white, isMetallic: false)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = SIMD3<Float>(x, y, z)
        return entity
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
            
            // Wait a moment for tracking to stabilize
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            
            isARKitReady = true
            print("[NativeImmersiveView] ARKit session started and ready")
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
    
    /// Updates the video screen with recentering to face the user's current direction.
    /// Waits for ARKit to be ready and provides the most accurate head position.
    private func updateVideoScreenWithRecentering() async {
        guard let videoEntity = videoEntity else {
            print("[NativeImmersiveView] No video entity yet, skipping update")
            return
        }
        
        // Wait for ARKit to be ready (max 2 seconds)
        var waitCount = 0
        while !isARKitReady && waitCount < 20 {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            waitCount += 1
            print("[NativeImmersiveView] Waiting for ARKit... (\(waitCount))")
        }
        
        if !isARKitReady {
            print("[NativeImmersiveView] WARNING: ARKit not ready after waiting, proceeding anyway")
        }
        
        // Small additional delay to get the freshest head position
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
        // Get the user's CURRENT head transform (freshest data)
        if let headTransform = await getCurrentHeadTransform() {
            let headPosition = getPosition(from: headTransform)
            let yaw = getYawRotation(from: headTransform)
            
            // Position video sphere at user's head (user is at center)
            videoEntity.position = headPosition
            
            // Orient video to face user's gaze direction
            videoEntity.orientation = simd_quatf(angle: -yaw + meshAlignmentOffset, axis: .init(0, 1, 0))
            
            print("[NativeImmersiveView] Recentered: pos=(\(headPosition.x), \(headPosition.y), \(headPosition.z)), yaw=\(yaw * 180 / .pi)°")
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

        // If a true-stereo (APMP) renderer is already live for this exact
        // video+format, leave it running. Rebuilding it mid-playback tears down a
        // working per-eye pipeline, and while the (often huge) file is still
        // buffering the fresh renderer receives no frames — which looks like the
        // immersive player "closing" a second or two after it starts. This check
        // is intentionally independent of the `lastVideo*` fields below, because
        // several `onChange` handlers reset those while the same video keeps
        // playing, which previously triggered the destructive rebuild.
        if stereoRenderer != nil,
           activeStereoKey == stereoKey(url: currentURL, format: format),
           debug.uvOverride == lastUVOverride {
            return
        }

        // Check if we already have a screen for this video/format/override
        if screenEntity != nil && lastVideoURL == currentURL && lastVideoFormat == format
            && lastUVOverride == debug.uvOverride {
            return
        }
        
        // Remove existing screen
        if let existingScreen = screenEntity {
            existingScreen.removeFromParent()
            print("[NativeImmersiveView] Removed existing screen")
        }
        
        print("[NativeImmersiveView] Creating screen for format: \(format.displayName)")
        print("[NativeImmersiveView] Is Immersive: \(format.isImmersive), Is Stereo: \(format.isStereoscopic)")
        RemoteLog("Settings", "Render decision for \(format.displayName): trueStereo=\(debug.trueStereoEnabled) eyeCompare=\(debug.eyeCompareEnabled) uvOverride=\(debug.uvOverride.rawValue) testMode=\(debug.testModeEnabled) nativeStereoMeta=\(videoManager.hasNativeStereoMetadata)")

        // --- Debug: side-by-side eye comparison (simulator-friendly) ---------
        // Shows the LEFT-eye and RIGHT-eye source crops on two flat panels at
        // once, so per-eye extraction can be verified even though the simulator
        // renders only a single eye. Debug only — disable to remove.
        if debug.testModeEnabled, debug.eyeCompareEnabled,
           let compare = createEyeCompareScreen(format: format, player: player) {
            compare.name = "VideoScreen"
            videoEntity.addChild(compare)
            screenEntity = compare
            lastVideoURL = currentURL
            lastVideoFormat = format
            lastUVOverride = debug.uvOverride
            print("[NativeImmersiveView] Eye-compare debug screen created")
            RemoteLog("RenderPath", "EYE-COMPARE debug screen active (two flat L/R panels). This is a diagnostic view, not stereo depth.")
            if videoManager.playbackState != .playing {
                videoManager.startPlayback()
            }
            return
        }
        // ---------------------------------------------------------------------

        // --- True per-eye stereo path (opt-in, visionOS 26+) -----------------
        // Injects APMP metadata so the system renders each eye from the
        // correct half of the frame. Falls through to the legacy path below
        // if unavailable or not applicable.
        if let stereoScreen = makeStereoScreenIfEnabled(format: format, player: player) {
            stereoScreen.name = "VideoScreen"
            videoEntity.addChild(stereoScreen)
            screenEntity = stereoScreen
            lastVideoURL = currentURL
            lastVideoFormat = format
            lastUVOverride = debug.uvOverride
            activeStereoKey = stereoKey(url: currentURL, format: format)
            print("[NativeImmersiveView] True-stereo (APMP) screen created")
            RemoteLog("RenderPath", "TRUE STEREO (APMP per-eye) active for \(format.displayName) — depth expected on device.")
            if videoManager.playbackState != .playing {
                videoManager.startPlayback()
            }
            return
        }
        // ---------------------------------------------------------------------

        // Create video material from the player
        RemoteLog("RenderPath", "LEGACY single-texture VideoMaterial for \(format.displayName) — same image to BOTH eyes, NO stereo depth.")
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
        lastUVOverride = debug.uvOverride
        
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
            mesh = createHemisphereMesh(radius: 10.0, segments: 128, uvMode: effectiveUVMode(base: .full))
            scale = SIMD3<Float>(-1, 1, 1) // Flip for inside-out view
            
        case .hemisphere180SBS:
            // 180° Stereo SBS - map LEFT half only for mono view from left eye
            print("[NativeImmersiveView] Creating 180° Stereo SBS hemisphere (left eye view)")
            let uv = effectiveUVMode(base: .leftHalf)
            RemoteLog("Mesh", "LEGACY 180°SBS hemisphere, uvMode=\(uv) (single texture → both eyes identical → NO depth). This branch should NOT run on visionOS 26 with True 3D on.")
            mesh = createHemisphereMesh(radius: 10.0, segments: 128, uvMode: uv)
            scale = SIMD3<Float>(-1, 1, 1) // Flip for inside-out view
            
        case .sphere360:
            // 360° mono sphere
            mesh = createSphereMesh(radius: 10.0, segments: 128, uvMode: effectiveUVMode(base: .full))
            scale = SIMD3<Float>(-1, 1, 1)
            
        case .sphere360OU:
            // 360° Stereo Over-Under - map TOP half for left eye
            print("[NativeImmersiveView] Creating 360° Stereo OU sphere (left eye view)")
            mesh = createSphereMesh(radius: 10.0, segments: 128, uvMode: effectiveUVMode(base: .topHalf))
            scale = SIMD3<Float>(-1, 1, 1)
            
        case .sphere360SBS:
            // 360° Stereo SBS - map LEFT half for left eye
            print("[NativeImmersiveView] Creating 360° Stereo SBS sphere (left eye view)")
            mesh = createSphereMesh(radius: 10.0, segments: 128, uvMode: effectiveUVMode(base: .leftHalf))
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

    /// Returns the UV mapping to use, honoring the debug test-mode override.
    /// When the test mode is off (or set to `.auto`), the format-derived
    /// `base` mapping is used unchanged.
    private func effectiveUVMode(base: UVMode) -> UVMode {
        guard debug.testModeEnabled, debug.uvOverride != .auto else { return base }
        switch debug.uvOverride {
        case .auto: return base
        case .full: return .full
        case .leftHalf: return .leftHalf
        case .rightHalf: return .rightHalf
        case .topHalf: return .topHalf
        case .bottomHalf: return .bottomHalf
        }
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

// MARK: - Diagnostics Panel

/// Floating panel rendered inside the immersive space when test mode is on.
/// Shows the measurable facts about the current video plus the live UV override,
/// so the bug ("both eyes show the same half") can be reasoned about and proven.
struct StereoDiagnosticsPanel: View {
    @ObservedObject var debug: StereoDebugSettings
    let currentFormat: VideoFormat

    private var d: VideoDiagnostics { debug.diagnostics }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Stereo Test Mode", systemImage: "eye.trianglebadge.exclamationmark")
                .font(.title2.bold())

            Divider()

            row("Resolution", d.width > 0 ? "\(d.width) × \(d.height)" : "—")
            row("Aspect ratio", d.aspectRatio > 0 ? String(format: "%.3f : 1", d.aspectRatio) : "—")
            row("Codec", d.codec)
            row("Native stereo metadata", d.hasNativeStereoMetadata ? "YES (MV-HEVC/spatial)" : "no")
            row("Selected format", currentFormat.displayName)
            row("Suggested packing", d.suggestedLayout.displayName)

            Text(d.suggestedNote)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Text("Eye mapping (live): \(debug.uvOverride.displayName)")
                .font(.headline)
            Text("Cycle this in Settings. With a real SBS video, Left half ≠ Right half. If they look identical, it isn't truly SBS. On device, the current build feeds the SAME half to BOTH eyes → no depth.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Label("Simulator shows ONE eye only — depth is only verifiable on a real Vision Pro.",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 460, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
        .font(.callout)
    }
}

// MARK: - Preview

#Preview(immersionStyle: .full) {
    NativeImmersiveView()
        .environmentObject(AppState())
        .environmentObject(NativeVideoPlayerManager())
}
