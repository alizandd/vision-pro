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

    /// Plays a video from the given URL
    func play(url: String) {
        print("[VideoPlayer] Playing: \(url)")

        // Stop any existing playback
        stop()

        guard let videoURL = URL(string: url) else {
            print("[VideoPlayer] Invalid URL: \(url)")
            updateState(.error)
            return
        }

        currentURL = url
        updateState(.loading)

        // Create player item and player
        let playerItem = AVPlayerItem(url: videoURL)
        player = AVPlayer(playerItem: playerItem)
        player?.volume = volume
        player?.isMuted = isMuted

        // Create video material for RealityKit
        videoMaterial = VideoMaterial(avPlayer: player!)

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
    func createVideoEntity(width: Float = 4.0, height: Float = 2.25) -> ModelEntity? {
        guard let videoMaterial = videoMaterial else {
            print("[VideoPlayer] No video material available")
            return nil
        }

        // Create a plane mesh for the video
        let mesh = MeshResource.generatePlane(width: width, height: height)

        // Create and return the entity
        let entity = ModelEntity(mesh: mesh, materials: [videoMaterial])
        return entity
    }
}
