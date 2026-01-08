import Foundation
import AVFoundation
import Combine
import RealityKit

/// Manages video playback for the immersive experience.
/// Handles loading, playing, pausing, and controlling video content.
@MainActor
class VideoPlayerManager: ObservableObject {
    /// Current playback state
    @Published var playbackState: PlaybackState = .idle

    /// Current video URL
    @Published var currentURL: String?
    
    /// Current video format (stereoscopic type, projection)
    @Published var currentFormat: VideoFormat = .mono2D

    /// Playback progress (0.0 to 1.0)
    @Published var progress: Double = 0.0

    /// Current playback time in seconds
    @Published var currentTime: Double = 0.0

    /// Total duration in seconds
    @Published var duration: Double = 0.0

    /// Whether the video is muted
    @Published var isMuted: Bool = false

    /// Volume level (0.0 to 1.0)
    @Published var volume: Float = 1.0 {
        didSet {
            player?.volume = volume
        }
    }

    /// Callback for state changes
    var onStateChange: ((PlaybackState) -> Void)?

    /// The AVPlayer instance
    private(set) var player: AVPlayer?

    /// Player item observer
    private var playerItemObserver: NSKeyValueObservation?

    /// Time observer token
    private var timeObserver: Any?

    /// Cancellables for Combine subscriptions
    private var cancellables = Set<AnyCancellable>()

    /// Video material for RealityKit
    private(set) var videoMaterial: VideoMaterial?

    init() {
        setupAudioSession()
    }

    deinit {
        cleanup()
    }

    // MARK: - Audio Session

    /// Configures the audio session for video playback
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .moviePlayback)
            try audioSession.setActive(true)
        } catch {
            print("[VideoPlayer] Failed to setup audio session: \(error)")
        }
    }

    // MARK: - Playback Control

    /// Plays a video from the given URL with specified format
    func play(url: String, format: VideoFormat = .mono2D) {
        print("[VideoPlayer] Playing: \(url) with format: \(format.displayName)")

        // Stop any existing playback
        stop()

        guard let videoURL = URL(string: url) else {
            print("[VideoPlayer] Invalid URL: \(url)")
            updateState(.error)
            return
        }

        currentURL = url
        currentFormat = format
        updateState(.loading)

        // Create player item and player
        let playerItem = AVPlayerItem(url: videoURL)
        player = AVPlayer(playerItem: playerItem)
        player?.volume = volume
        player?.isMuted = isMuted

        // Create video material for RealityKit
        videoMaterial = VideoMaterial(avPlayer: player!)
        print("[VideoPlayer] Video material created successfully")

        // Observe player item status
        playerItemObserver = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                self?.handlePlayerItemStatus(item.status)
            }
        }

        // Add time observer for progress updates
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.updateProgress(time: time)
            }
        }

        // Observe playback end
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )

        // Start playback
        player?.play()
    }

    /// Pauses the current video
    func pause() {
        guard playbackState == .playing else { return }
        print("[VideoPlayer] Pausing")
        player?.pause()
        updateState(.paused)
    }

    /// Resumes paused video
    func resume() {
        guard playbackState == .paused else { return }
        print("[VideoPlayer] Resuming")
        player?.play()
        updateState(.playing)
    }

    /// Stops playback and resets
    func stop() {
        print("[VideoPlayer] Stopping")

        // Remove observers
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        playerItemObserver?.invalidate()
        playerItemObserver = nil

        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)

        // Stop and clear player
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        videoMaterial = nil

        // Reset state
        currentURL = nil
        currentFormat = .mono2D
        progress = 0.0
        currentTime = 0.0
        duration = 0.0

        updateState(.stopped)
    }

    /// Seeks to a specific time
    func seek(to progress: Double) {
        guard let player = player, duration > 0 else { return }

        let targetTime = CMTime(seconds: progress * duration, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Toggles mute state
    func toggleMute() {
        isMuted.toggle()
        player?.isMuted = isMuted
    }

    // MARK: - Private Methods

    /// Handles player item status changes
    private func handlePlayerItemStatus(_ status: AVPlayerItem.Status) {
        switch status {
        case .readyToPlay:
            print("[VideoPlayer] Ready to play")
            if let item = player?.currentItem {
                duration = item.duration.seconds.isNaN ? 0 : item.duration.seconds
            }
            updateState(.playing)

        case .failed:
            print("[VideoPlayer] Failed to load: \(player?.currentItem?.error?.localizedDescription ?? "Unknown error")")
            updateState(.error)

        case .unknown:
            print("[VideoPlayer] Status unknown")

        @unknown default:
            break
        }
    }

    /// Updates playback progress
    private func updateProgress(time: CMTime) {
        currentTime = time.seconds.isNaN ? 0 : time.seconds
        if duration > 0 {
            progress = currentTime / duration
        }
    }

    /// Called when video finishes playing
    @objc private func playerDidFinishPlaying() {
        print("[VideoPlayer] Finished playing")
        updateState(.stopped)
    }

    /// Updates the playback state and notifies observers
    private func updateState(_ state: PlaybackState) {
        playbackState = state
        onStateChange?(state)
    }

    /// Cleans up resources
    nonisolated private func cleanup() {
        // Schedule cleanup on MainActor
        // Note: This may not complete before deallocation in deinit context
        Task { @MainActor in
            self.stop()
            try? AVAudioSession.sharedInstance().setActive(false)
        }
    }

    // MARK: - RealityKit Integration

    /// Creates a mesh entity with the video material for RealityKit scenes
    /// For stereoscopic formats, creates appropriate mesh based on format
    func createVideoEntity(width: Float = 4.0, height: Float = 2.25) -> ModelEntity? {
        guard let videoMaterial = videoMaterial else {
            print("[VideoPlayer] No video material available")
            return nil
        }
        
        print("[VideoPlayer] Creating entity for format: \(currentFormat.displayName)")
        
        // Create appropriate mesh based on video format
        // Note: In simulator, stereoscopic 3D won't look correct but mesh shape will be visible
        #if targetEnvironment(simulator)
        print("[VideoPlayer] Running in Simulator - mesh will be created but stereoscopic 3D won't render correctly")
        #endif
        
        let mesh: MeshResource
        
        switch currentFormat {
        case .hemisphere180, .hemisphere180SBS:
            // 180° hemisphere mesh for VR180 content
            print("[VideoPlayer] ✅ Creating HEMISPHERE mesh (radius: 5.0, segments: 64) for 180° VR content")
            mesh = createHemisphereMesh(radius: 5.0, segments: 64)
            
        case .sphere360, .sphere360OU:
            // Full sphere for 360° content
            print("[VideoPlayer] ✅ Creating SPHERE mesh (radius: 5.0) for 360° VR content")
            mesh = MeshResource.generateSphere(radius: 5.0)
            
        default:
            // Flat plane for 2D and flat 3D content
            print("[VideoPlayer] ✅ Creating FLAT PLANE mesh (width: \(width), height: \(height)) for 2D/flat content")
            mesh = MeshResource.generatePlane(width: width, height: height)
        }

        // Create and return the entity
        let entity = ModelEntity(mesh: mesh, materials: [videoMaterial])
        
        // For hemisphere/sphere, flip normals inward (we're inside looking out)
        if currentFormat.isImmersive {
            entity.scale = SIMD3<Float>(-1, 1, 1) // Mirror X to flip normals
        }
        
        return entity
    }
    
    /// Creates a hemisphere mesh for 180° VR content
    /// - Parameters:
    ///   - radius: The radius of the hemisphere
    ///   - segments: Number of horizontal and vertical segments
    /// - Returns: A MeshResource for the hemisphere
    private func createHemisphereMesh(radius: Float, segments: Int) -> MeshResource {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        
        let horizontalSegments = segments
        let verticalSegments = segments / 2
        
        // Generate vertices for hemisphere (front half of sphere)
        for y in 0...verticalSegments {
            let v = Float(y) / Float(verticalSegments)
            let phi = v * .pi // 0 to π (top to bottom)
            
            for x in 0...horizontalSegments {
                let u = Float(x) / Float(horizontalSegments)
                let theta = (u - 0.5) * .pi // -π/2 to π/2 (left to right, hemisphere)
                
                // Spherical to Cartesian
                let sinPhi = sin(phi)
                let cosPhi = cos(phi)
                let sinTheta = sin(theta)
                let cosTheta = cos(theta)
                
                let px = radius * sinPhi * sinTheta
                let py = radius * cosPhi
                let pz = -radius * sinPhi * cosTheta // Negative Z so it's in front
                
                positions.append(SIMD3<Float>(px, py, pz))
                
                // Normal pointing inward (we're inside the hemisphere)
                normals.append(SIMD3<Float>(-sinPhi * sinTheta, -cosPhi, sinPhi * cosTheta))
                
                // UV coordinates - map hemisphere to full texture
                uvs.append(SIMD2<Float>(u, v))
            }
        }
        
        // Generate indices for triangles
        let vertsPerRow = horizontalSegments + 1
        for y in 0..<verticalSegments {
            for x in 0..<horizontalSegments {
                let topLeft = UInt32(y * vertsPerRow + x)
                let topRight = topLeft + 1
                let bottomLeft = UInt32((y + 1) * vertsPerRow + x)
                let bottomRight = bottomLeft + 1
                
                // Two triangles per quad (counter-clockwise for inward-facing)
                indices.append(contentsOf: [topLeft, bottomLeft, topRight])
                indices.append(contentsOf: [topRight, bottomLeft, bottomRight])
            }
        }
        
        // Create mesh descriptor
        var meshDescriptor = MeshDescriptor()
        meshDescriptor.positions = MeshBuffers.Positions(positions)
        meshDescriptor.normals = MeshBuffers.Normals(normals)
        meshDescriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        meshDescriptor.primitives = .triangles(indices)
        
        do {
            return try MeshResource.generate(from: [meshDescriptor])
        } catch {
            print("[VideoPlayer] Failed to create hemisphere mesh: \(error)")
            // Fallback to plane
            return MeshResource.generatePlane(width: 4.0, height: 2.25)
        }
    }
}
