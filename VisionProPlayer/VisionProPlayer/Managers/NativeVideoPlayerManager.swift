import Foundation
import AVFoundation
import AVKit
import Combine

/// Native video player manager using AVPlayerViewController for optimal 16K video support.
/// 
/// This implementation uses the native visionOS video player which provides:
/// - Support for 16K and higher resolutions (no texture size limits)
/// - Automatic per-eye stereoscopic rendering for spatial videos
/// - Memory-efficient streaming with hardware-accelerated decoding
/// - Proper handling of MV-HEVC and other spatial video formats
/// - Better simulator compatibility
///
/// Unlike VideoMaterial in RealityKit, the native player doesn't have GPU texture limitations.
@MainActor
class NativeVideoPlayerManager: ObservableObject {
    /// Current playback state
    @Published var playbackState: PlaybackState = .idle
    
    /// Current video URL
    @Published var currentURL: String?
    
    /// Current video format
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
    
    /// Whether the player is ready for playback
    @Published var isPlayerReady: Bool = false
    
    /// Whether the video has native stereoscopic metadata
    @Published var hasNativeStereoMetadata: Bool = false
    
    /// Whether we're currently in immersive mode
    @Published var isImmersiveActive: Bool = false
    
    /// Callback for state changes
    var onStateChange: ((PlaybackState) -> Void)?
    
    /// Callback when player is ready for playback
    var onPlayerReady: (() -> Void)?
    
    /// The AVPlayer instance - exposed for AVPlayerViewController
    @Published private(set) var player: AVPlayer?
    
    /// The current AVURLAsset
    private(set) var currentAsset: AVURLAsset?
    
    /// Player item observer
    private var playerItemObserver: NSKeyValueObservation?
    
    /// Player item error observer
    private var playerItemErrorObserver: NSKeyValueObservation?
    
    /// Time observer token
    private var timeObserver: Any?
    
    /// Cancellables for Combine subscriptions
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupAudioSession()
    }
    
    deinit {
        cleanup()
    }
    
    // MARK: - Audio Session
    
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try audioSession.setActive(true)
        } catch {
            print("[NativeVideoPlayer] Failed to setup audio session: \(error)")
        }
    }
    
    // MARK: - Playback Control
    
    /// Prepares a video for playback without starting it.
    /// This is optimized for large files and doesn't have resolution limits.
    func prepareVideo(url: String, format: VideoFormat = .mono2D) async -> Bool {
        print("[NativeVideoPlayer] Preparing video: \(url)")
        print("[NativeVideoPlayer] Format: \(format.displayName)")
        
        // Stop any existing playback
        stop()
        
        // Convert URL if needed (for simulator compatibility)
        let processedURL = convertURLForSimulator(url)
        if processedURL != url {
            print("[NativeVideoPlayer] Converted URL for simulator: \(processedURL)")
        }
        
        guard let videoURL = URL(string: processedURL) else {
            print("[NativeVideoPlayer] Invalid URL: \(processedURL)")
            updateState(.error)
            return false
        }
        
        currentURL = processedURL
        currentFormat = format
        isPlayerReady = false
        hasNativeStereoMetadata = false
        updateState(.loading)
        
        // For remote URLs, verify connectivity first
        if !videoURL.isFileURL {
            print("[NativeVideoPlayer] Checking URL accessibility...")
            let accessible = await checkURLAccessibility(url: videoURL)
            if !accessible {
                print("[NativeVideoPlayer] ERROR: URL is not accessible")
                updateState(.error)
                return false
            }
            print("[NativeVideoPlayer] URL is accessible")
        }
        
        // Create optimized asset for large files
        let asset = createOptimizedAsset(url: videoURL, format: format)
        currentAsset = asset
        
        // Check for native stereo metadata
        hasNativeStereoMetadata = await checkStereoMetadata(asset: asset)
        print("[NativeVideoPlayer] Has native stereo metadata: \(hasNativeStereoMetadata)")
        
        // Load essential properties - be lenient about isPlayable as some videos
        // can still play even if this check fails
        do {
            // First try to load tracks to get more info
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            print("[NativeVideoPlayer] Found \(videoTracks.count) video tracks")
            
            if videoTracks.isEmpty {
                print("[NativeVideoPlayer] ERROR: No video tracks found in asset")
                print("[NativeVideoPlayer] This could mean:")
                print("[NativeVideoPlayer]   - Video URL is not accessible")
                print("[NativeVideoPlayer]   - Video format is not supported")
                print("[NativeVideoPlayer]   - Network connectivity issue")
                updateState(.error)
                return false
            }
            
            // Log video resolution for debugging
            if let videoTrack = videoTracks.first {
                let naturalSize = try await videoTrack.load(.naturalSize)
                print("[NativeVideoPlayer] Video resolution: \(Int(naturalSize.width))x\(Int(naturalSize.height))")
                
                // Get codec info
                let formatDescriptions = try await videoTrack.load(.formatDescriptions)
                for formatDesc in formatDescriptions {
                    let mediaType = CMFormatDescriptionGetMediaType(formatDesc)
                    let mediaSubType = CMFormatDescriptionGetMediaSubType(formatDesc)
                    let subTypeString = String(format: "%c%c%c%c",
                                               (mediaSubType >> 24) & 0xFF,
                                               (mediaSubType >> 16) & 0xFF,
                                               (mediaSubType >> 8) & 0xFF,
                                               mediaSubType & 0xFF)
                    print("[NativeVideoPlayer] Codec: \(subTypeString) (type: \(mediaType))")
                }
            }
            
            // Check if asset is playable (but don't fail if not - try anyway)
            let isPlayable = try await asset.load(.isPlayable)
            print("[NativeVideoPlayer] Asset isPlayable: \(isPlayable)")
            
            if !isPlayable {
                print("[NativeVideoPlayer] WARNING: Asset reports not playable, but will try anyway")
            }
            
            let assetDuration = try await asset.load(.duration)
            duration = assetDuration.seconds.isNaN ? 0 : assetDuration.seconds
            print("[NativeVideoPlayer] Video duration: \(duration)s")
            
        } catch {
            print("[NativeVideoPlayer] Failed to load asset properties: \(error)")
            print("[NativeVideoPlayer] Error details: \(error.localizedDescription)")
            
            // Check if it's a network error
            let nsError = error as NSError
            print("[NativeVideoPlayer] Error domain: \(nsError.domain), code: \(nsError.code)")
            if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
                print("[NativeVideoPlayer] Underlying error: \(underlyingError)")
            }
            
            // Don't fail here - try to create player anyway
            print("[NativeVideoPlayer] Will attempt to create player despite load errors")
        }
        
        // Create player item with optimized settings for large files
        let playerItem = createOptimizedPlayerItem(asset: asset)
        
        // Create player
        player = AVPlayer(playerItem: playerItem)
        player?.volume = volume
        player?.isMuted = isMuted
        
        // Enable automatic waiting for better streaming performance
        player?.automaticallyWaitsToMinimizeStalling = true
        
        // Setup observers
        setupPlayerObservers(playerItem: playerItem)
        
        // Wait for player readiness
        let ready = await waitForPlayerReadiness()
        
        if ready {
            print("[NativeVideoPlayer] Player is ready")
            isPlayerReady = true
            onPlayerReady?()
        }
        
        return ready
    }
    
    /// Starts playback of prepared video
    func startPlayback() {
        guard let player = player else {
            print("[NativeVideoPlayer] Cannot start - no player prepared")
            return
        }
        
        guard isPlayerReady else {
            print("[NativeVideoPlayer] Cannot start - player not ready")
            return
        }
        
        print("[NativeVideoPlayer] Starting playback")
        player.play()
        updateState(.playing)
    }
    
    /// Pauses playback
    func pause() {
        guard playbackState == .playing else { return }
        print("[NativeVideoPlayer] Pausing")
        player?.pause()
        updateState(.paused)
    }
    
    /// Resumes paused playback
    func resume() {
        guard playbackState == .paused else { return }
        print("[NativeVideoPlayer] Resuming")
        player?.play()
        updateState(.playing)
    }
    
    /// Stops playback and cleans up
    func stop() {
        print("[NativeVideoPlayer] Stopping")
        
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
    
    /// Seeks to a specific progress position
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
    
    /// Converts a URL to use localhost if running on simulator.
    /// This is needed because the simulator cannot access the host's LAN IP directly.
    private func convertURLForSimulator(_ urlString: String) -> String {
        #if targetEnvironment(simulator)
        // On simulator, convert LAN IPs to localhost
        // This allows the simulator to access servers running on the Mac
        guard let url = URL(string: urlString),
              let host = url.host else {
            return urlString
        }
        
        // Check if it's a private/local IP address
        let privateIPPatterns = [
            "192.168.", // Class C private
            "10.",      // Class A private
            "172.16.", "172.17.", "172.18.", "172.19.",  // Class B private
            "172.20.", "172.21.", "172.22.", "172.23.",
            "172.24.", "172.25.", "172.26.", "172.27.",
            "172.28.", "172.29.", "172.30.", "172.31."
        ]
        
        let isPrivateIP = privateIPPatterns.contains { host.hasPrefix($0) }
        
        if isPrivateIP {
            // Replace the host with localhost
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.host = "localhost"
            
            if let newURL = components?.url?.absoluteString {
                print("[NativeVideoPlayer] SIMULATOR: Converting \(host) -> localhost")
                return newURL
            }
        }
        #endif
        
        return urlString
    }
    
    /// Checks if a URL is accessible via HTTP HEAD request
    private func checkURLAccessibility(url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("[NativeVideoPlayer] URL check status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    if let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length") {
                        print("[NativeVideoPlayer] Content-Length: \(contentLength) bytes")
                    }
                    if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") {
                        print("[NativeVideoPlayer] Content-Type: \(contentType)")
                    }
                    return true
                } else {
                    print("[NativeVideoPlayer] URL returned status \(httpResponse.statusCode)")
                    return false
                }
            }
            return false
        } catch {
            print("[NativeVideoPlayer] URL accessibility check failed: \(error.localizedDescription)")
            
            // Log more details about the network error
            let nsError = error as NSError
            print("[NativeVideoPlayer] Network error - domain: \(nsError.domain), code: \(nsError.code)")
            
            return false
        }
    }
    
    /// Creates an optimized asset for large video files
    private func createOptimizedAsset(url: URL, format: VideoFormat) -> AVURLAsset {
        var options: [String: Any] = [:]
        
        if url.isFileURL {
            print("[NativeVideoPlayer] Loading from local file: \(url.lastPathComponent)")
        } else {
            options[AVURLAssetAllowsCellularAccessKey] = true
            options[AVURLAssetHTTPCookiesKey] = HTTPCookieStorage.shared.cookies ?? []
            print("[NativeVideoPlayer] Loading from remote URL")
        }
        
        // Don't require precise duration for faster initial load
        options[AVURLAssetPreferPreciseDurationAndTimingKey] = false
        
        return AVURLAsset(url: url, options: options)
    }
    
    /// Creates optimized player item for large files
    private func createOptimizedPlayerItem(asset: AVURLAsset) -> AVPlayerItem {
        let playerItem = AVPlayerItem(asset: asset)
        
        // Configure buffer for large files
        // 30 second forward buffer balances memory and smooth playback
        playerItem.preferredForwardBufferDuration = 30
        playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = false
        
        return playerItem
    }
    
    /// Checks if asset has native stereo metadata
    private func checkStereoMetadata(asset: AVURLAsset) async -> Bool {
        do {
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = videoTracks.first else { return false }
            
            let formatDescriptions = try await track.load(.formatDescriptions)
            
            for formatDesc in formatDescriptions {
                let extensions = CMFormatDescriptionGetExtensions(formatDesc) as? [String: Any] ?? [:]
                
                if extensions["StereoInfo"] != nil ||
                   extensions["MVHEVCConfiguration"] != nil ||
                   extensions["CMStereoVideoMode"] != nil {
                    return true
                }
            }
        } catch {
            print("[NativeVideoPlayer] Error checking stereo metadata: \(error)")
        }
        
        return false
    }
    
    /// Sets up observers for the player item
    private func setupPlayerObservers(playerItem: AVPlayerItem) {
        // Observe status
        playerItemObserver = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                self?.handlePlayerItemStatus(item.status)
            }
        }
        
        // Observe errors
        playerItemErrorObserver = playerItem.observe(\.error, options: [.new]) { [weak self] item, _ in
            if let error = item.error {
                Task { @MainActor in
                    print("[NativeVideoPlayer] Player item error: \(error.localizedDescription)")
                    self?.updateState(.error)
                }
            }
        }
        
        // Time observer for progress
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.updateProgress(time: time)
            }
        }
        
        // Playback end notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )
        
        // Stall notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidStall),
            name: .AVPlayerItemPlaybackStalled,
            object: playerItem
        )
    }
    
    /// Waits for player to become ready
    private func waitForPlayerReadiness() async -> Bool {
        guard let playerItem = player?.currentItem else { return false }
        
        let maxWaitTime: TimeInterval = 30.0
        let checkInterval: TimeInterval = 0.1
        let startTime = Date()
        
        while Date().timeIntervalSince(startTime) < maxWaitTime {
            if playerItem.status == .readyToPlay {
                print("[NativeVideoPlayer] Ready after \(String(format: "%.2f", Date().timeIntervalSince(startTime)))s")
                return true
            } else if playerItem.status == .failed {
                print("[NativeVideoPlayer] Failed: \(playerItem.error?.localizedDescription ?? "unknown")")
                return false
            }
            
            try? await Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))
        }
        
        print("[NativeVideoPlayer] Timeout waiting for readiness")
        return false
    }
    
    /// Handles player item status changes
    private func handlePlayerItemStatus(_ status: AVPlayerItem.Status) {
        switch status {
        case .readyToPlay:
            print("[NativeVideoPlayer] Ready to play")
            if let item = player?.currentItem {
                duration = item.duration.seconds.isNaN ? 0 : item.duration.seconds
            }
            
        case .failed:
            print("[NativeVideoPlayer] Failed: \(player?.currentItem?.error?.localizedDescription ?? "Unknown")")
            updateState(.error)
            
        case .unknown:
            print("[NativeVideoPlayer] Status unknown")
            
        @unknown default:
            break
        }
    }
    
    /// Updates progress
    private func updateProgress(time: CMTime) {
        currentTime = time.seconds.isNaN ? 0 : time.seconds
        if duration > 0 {
            progress = currentTime / duration
        }
    }
    
    @objc private func playerDidFinishPlaying() {
        print("[NativeVideoPlayer] Finished playing")
        updateState(.stopped)
    }
    
    @objc private func playerDidStall() {
        print("[NativeVideoPlayer] Playback stalled - buffering")
    }
    
    /// Updates state and notifies observers
    private func updateState(_ state: PlaybackState) {
        playbackState = state
        onStateChange?(state)
    }
    
    /// Cleanup resources
    nonisolated private func cleanup() {
        Task { @MainActor in
            self.stop()
            try? AVAudioSession.sharedInstance().setActive(false)
        }
    }
}
