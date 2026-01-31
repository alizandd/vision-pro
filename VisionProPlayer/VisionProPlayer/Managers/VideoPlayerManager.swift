import Foundation
import AVFoundation
import Combine
import RealityKit

/// Manages video playback for the immersive experience.
/// Handles loading, playing, pausing, and controlling video content.
/// Optimized for large stereoscopic immersive videos.
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
    
    /// Whether the player is ready and immersive space can safely initialize video
    @Published var isPlayerReady: Bool = false
    
    /// Whether the video has native stereoscopic metadata
    @Published var hasNativeStereoMetadata: Bool = false

    /// Callback for state changes
    var onStateChange: ((PlaybackState) -> Void)?
    
    /// Callback when player is ready for playback (after asset preparation)
    var onPlayerReady: (() -> Void)?

    /// The AVPlayer instance
    private(set) var player: AVPlayer?
    
    /// The current AVURLAsset for the video
    private(set) var currentAsset: AVURLAsset?

    /// Player item observer
    private var playerItemObserver: NSKeyValueObservation?
    
    /// Player item error observer
    private var playerItemErrorObserver: NSKeyValueObservation?

    /// Time observer token
    private var timeObserver: Any?

    /// Cancellables for Combine subscriptions
    private var cancellables = Set<AnyCancellable>()

    /// Video material for RealityKit (used for custom rendering fallback)
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
    
    /// Prepares a video for playback without starting it.
    /// This is used to ensure the video is ready before the immersive space initializes.
    /// CRITICAL: For large files, this must be called AFTER the immersive space is ready.
    func prepareVideo(url: String, format: VideoFormat = .mono2D) async -> Bool {
        print("[VideoPlayer] Preparing video: \(url) with format: \(format.displayName)")
        
        // Stop any existing playback first
        stop()
        
        guard let videoURL = URL(string: url) else {
            print("[VideoPlayer] Invalid URL: \(url)")
            updateState(.error)
            return false
        }
        
        currentURL = url
        currentFormat = format
        isPlayerReady = false
        hasNativeStereoMetadata = false
        updateState(.loading)
        
        // Create optimized asset for large immersive videos
        let asset = createOptimizedAsset(url: videoURL, format: format)
        currentAsset = asset
        
        // Check for native stereo metadata (important for proper rendering path)
        hasNativeStereoMetadata = await StereoVideoCompositor.hasNativeStereoMetadata(asset: asset)
        print("[VideoPlayer] Native stereo metadata: \(hasNativeStereoMetadata)")
        
        // Load essential properties asynchronously (doesn't load full video into memory)
        do {
            let isPlayable = try await asset.load(.isPlayable)
            if !isPlayable {
                print("[VideoPlayer] Asset is not playable")
                updateState(.error)
                return false
            }
            
            // Get duration without loading full video
            let assetDuration = try await asset.load(.duration)
            duration = assetDuration.seconds.isNaN ? 0 : assetDuration.seconds
            print("[VideoPlayer] Video duration: \(duration)s")
            
        } catch {
            print("[VideoPlayer] Failed to load asset properties: \(error)")
            updateState(.error)
            return false
        }
        
        // Create player item with buffer settings optimized for large files
        let playerItem = createOptimizedPlayerItem(asset: asset)
        
        // Create player
        player = AVPlayer(playerItem: playerItem)
        player?.volume = volume
        player?.isMuted = isMuted
        
        // IMPORTANT: Disable automatic waiting to prevent memory pressure
        player?.automaticallyWaitsToMinimizeStalling = true
        
        // Setup observers
        setupPlayerObservers(playerItem: playerItem)
        
        // Wait for player to be ready
        let ready = await waitForPlayerReadiness()
        
        if ready {
            // Create video material for RealityKit rendering
            videoMaterial = VideoMaterial(avPlayer: player!)
            print("[VideoPlayer] Video material created successfully")
            isPlayerReady = true
            onPlayerReady?()
        }
        
        return ready
    }

    /// Plays a video from the given URL with specified format.
    /// For immersive videos, prefer using prepareVideo() first, then startPlayback().
    func play(url: String, format: VideoFormat = .mono2D) {
        print("[VideoPlayer] Playing: \(url) with format: \(format.displayName)")
        
        // For non-immersive content or when called directly, use legacy path
        Task {
            let prepared = await prepareVideo(url: url, format: format)
            if prepared {
                startPlayback()
            }
        }
    }
    
    /// Starts playback of an already prepared video.
    /// MUST call prepareVideo() first.
    func startPlayback() {
        guard let player = player else {
            print("[VideoPlayer] Cannot start playback - no player prepared")
            return
        }
        
        guard isPlayerReady else {
            print("[VideoPlayer] Cannot start playback - player not ready")
            return
        }
        
        print("[VideoPlayer] Starting playback")
        player.play()
    }
    
    /// Creates an optimized AVURLAsset for large immersive video files.
    private func createOptimizedAsset(url: URL, format: VideoFormat) -> AVURLAsset {
        var options: [String: Any] = [:]
        
        // For file URLs (local videos), use direct file access
        if url.isFileURL {
            // No special options needed for local files
            // The system will handle streaming from disk efficiently
            print("[VideoPlayer] Creating asset for local file: \(url.lastPathComponent)")
        } else {
            // For remote URLs, configure network options
            options[AVURLAssetAllowsCellularAccessKey] = true
            options[AVURLAssetHTTPCookiesKey] = HTTPCookieStorage.shared.cookies ?? []
            print("[VideoPlayer] Creating asset for remote URL")
        }
        
        // Don't require precise duration - allows faster initial load
        options[AVURLAssetPreferPreciseDurationAndTimingKey] = false
        
        return AVURLAsset(url: url, options: options)
    }
    
    /// Creates an optimized AVPlayerItem for large files.
    private func createOptimizedPlayerItem(asset: AVURLAsset) -> AVPlayerItem {
        let playerItem = AVPlayerItem(asset: asset)
        
        // Configure buffer sizes for large immersive videos
        // Smaller buffers = less memory usage but more potential stalling
        // For 20GB files, we want minimal buffering to prevent memory pressure
        playerItem.preferredForwardBufferDuration = 30  // 30 seconds forward buffer
        
        // Allow video to start before full buffer
        playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = false
        
        return playerItem
    }
    
    /// Sets up all observers for the player item.
    private func setupPlayerObservers(playerItem: AVPlayerItem) {
        // Observe player item status
        playerItemObserver = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                self?.handlePlayerItemStatus(item.status)
            }
        }
        
        // Observe player item errors
        playerItemErrorObserver = playerItem.observe(\.error, options: [.new]) { [weak self] item, _ in
            if let error = item.error {
                Task { @MainActor in
                    print("[VideoPlayer] Player item error: \(error.localizedDescription)")
                    self?.updateState(.error)
                }
            }
        }
        
        // Add time observer for progress updates
        let interval = CMTime(seconds: 1.0, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
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
        
        // Observe playback stalls (important for large files)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidStall),
            name: .AVPlayerItemPlaybackStalled,
            object: playerItem
        )
    }
    
    /// Waits for the player to become ready for playback.
    private func waitForPlayerReadiness() async -> Bool {
        guard let playerItem = player?.currentItem else { return false }
        
        let maxWaitTime: TimeInterval = 30.0  // Increased for large files
        let checkInterval: TimeInterval = 0.1
        let startTime = Date()
        
        while Date().timeIntervalSince(startTime) < maxWaitTime {
            if playerItem.status == .readyToPlay {
                print("[VideoPlayer] Player ready after \(Date().timeIntervalSince(startTime))s")
                return true
            } else if playerItem.status == .failed {
                print("[VideoPlayer] Player failed: \(playerItem.error?.localizedDescription ?? "unknown")")
                return false
            }
            
            try? await Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))
        }
        
        print("[VideoPlayer] Timeout waiting for player readiness")
        return false
    }
    
    /// Called when playback stalls (buffering)
    @objc private func playerDidStall() {
        print("[VideoPlayer] Playback stalled - buffering")
        // Don't change state to loading here to avoid UI flicker
        // The player will automatically resume when buffer is sufficient
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
        playerItemErrorObserver?.invalidate()
        playerItemErrorObserver = nil

        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemPlaybackStalled, object: nil)

        // Stop and clear player
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        videoMaterial = nil
        currentAsset = nil

        // Reset state
        currentURL = nil
        currentFormat = .mono2D
        progress = 0.0
        currentTime = 0.0
        duration = 0.0
        isPlayerReady = false
        hasNativeStereoMetadata = false

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
}
