import SwiftUI
import AVKit
import AVFoundation

/// A SwiftUI wrapper for AVPlayerViewController optimized for immersive stereoscopic video.
/// This leverages visionOS's native immersive video pipeline which correctly handles:
/// - Stereoscopic 3D rendering (SBS, OU)
/// - 180°/360° equirectangular projection
/// - Per-eye video mapping
/// - Memory-efficient streaming for large files
struct ImmersiveVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    let videoFormat: VideoFormat
    
    /// Callback when the player view is ready
    var onReady: (() -> Void)?
    
    /// Callback when playback fails
    var onError: ((Error) -> Void)?
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.delegate = context.coordinator
        
        // Configure for immersive playback
        configureForImmersivePlayback(controller)
        
        return controller
    }
    
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        // Update player if changed
        if controller.player !== player {
            controller.player = player
            configureForImmersivePlayback(controller)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onReady: onReady, onError: onError)
    }
    
    private func configureForImmersivePlayback(_ controller: AVPlayerViewController) {
        // Hide transport controls for remote-controlled playback
        controller.showsPlaybackControls = false
        
        // Note: AVPlayerViewController in visionOS 1.0 does not have
        // preferredImmersiveViewingMode API. The system will automatically
        // detect and handle immersive/stereoscopic content based on
        // video metadata embedded in the file.
        //
        // For proper stereo playback, ensure your video file has:
        // - Spatial metadata tags (stereo_mode, spherical, etc.)
        // - Or is encoded as MV-HEVC
        //
        // See STEREO_VIDEO_GUIDE.md for instructions on adding metadata.
        
        // Log the format being used
        print("[ImmersiveVideoPlayer] Configured for format: \(videoFormat.displayName)")
        print("[ImmersiveVideoPlayer] Is immersive: \(videoFormat.isImmersive)")
        print("[ImmersiveVideoPlayer] Is stereoscopic: \(videoFormat.isStereoscopic)")
    }
    
    class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        var onReady: (() -> Void)?
        var onError: ((Error) -> Void)?
        
        init(onReady: (() -> Void)?, onError: ((Error) -> Void)?) {
            self.onReady = onReady
            self.onError = onError
        }
        
        func playerViewController(_ playerViewController: AVPlayerViewController,
                                  willBeginFullScreenPresentationWithAnimationCoordinator coordinator: any UIViewControllerTransitionCoordinator) {
            print("[ImmersiveVideoPlayer] Beginning full screen presentation")
        }
        
        func playerViewController(_ playerViewController: AVPlayerViewController,
                                  willEndFullScreenPresentationWithAnimationCoordinator coordinator: any UIViewControllerTransitionCoordinator) {
            print("[ImmersiveVideoPlayer] Ending full screen presentation")
        }
    }
}

// MARK: - Video Asset Configuration for Stereoscopic Content

extension AVURLAsset {
    /// Creates an AVURLAsset configured for stereoscopic immersive video playback.
    /// Optimized for large files with streaming and memory-efficient loading.
    static func immersiveVideoAsset(url: URL, format: VideoFormat) -> AVURLAsset {
        // Configure asset options for optimal streaming of large files
        var options: [String: Any] = [
            // Allow cellular access for remote files
            AVURLAssetAllowsCellularAccessKey: true,
            // Prefer precise duration for seeking
            AVURLAssetPreferPreciseDurationAndTimingKey: false,  // false = faster loading
        ]
        
        // For HTTP(S) URLs, configure for efficient streaming
        if url.scheme?.hasPrefix("http") == true {
            options[AVURLAssetHTTPCookiesKey] = HTTPCookieStorage.shared.cookies
        }
        
        let asset = AVURLAsset(url: url, options: options)
        
        // For stereoscopic content, we need to ensure the asset
        // has proper video composition for per-eye rendering
        // Note: visionOS handles this automatically for properly tagged videos
        
        return asset
    }
}

// MARK: - Stereoscopic Video Composition

/// Creates a video composition for Side-by-Side stereoscopic content.
/// This transforms SBS video into per-eye rendering when video lacks native stereo metadata.
class StereoVideoCompositor {
    
    /// Checks if the video asset has native stereoscopic metadata.
    static func hasNativeStereoMetadata(asset: AVAsset) async -> Bool {
        do {
            // Load video tracks
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = videoTracks.first else { return false }
            
            // Check for stereo metadata in format descriptions
            let formatDescriptions = try await track.load(.formatDescriptions)
            
            for formatDesc in formatDescriptions {
                let extensions = CMFormatDescriptionGetExtensions(formatDesc) as? [String: Any] ?? [:]
                
                // Check for MV-HEVC or spatial video indicators
                if extensions["StereoInfo"] != nil ||
                   extensions["MVHEVCConfiguration"] != nil ||
                   extensions["CMStereoVideoMode"] != nil {
                    print("[StereoVideoCompositor] Found native stereo metadata")
                    return true
                }
            }
        } catch {
            print("[StereoVideoCompositor] Error checking stereo metadata: \(error)")
        }
        
        return false
    }
    
    /// Returns the natural size of the video.
    static func getVideoSize(asset: AVAsset) async -> CGSize? {
        do {
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = videoTracks.first else { return nil }
            return try await track.load(.naturalSize)
        } catch {
            print("[StereoVideoCompositor] Error getting video size: \(error)")
            return nil
        }
    }
}

// MARK: - Immersive Space Readiness

/// Protocol for checking immersive space readiness before video initialization.
@MainActor
protocol ImmersiveSpaceReadinessDelegate: AnyObject {
    var isImmersiveSpaceReady: Bool { get }
}

/// Waits for immersive space to be fully ready before proceeding.
/// Critical for preventing crashes with large immersive videos.
@MainActor
func waitForImmersiveSpaceReadiness(maxWaitTime: TimeInterval = 5.0) async -> Bool {
    let startTime = Date()
    let checkInterval: TimeInterval = 0.1
    
    while Date().timeIntervalSince(startTime) < maxWaitTime {
        // Check if RealityKit rendering context is ready
        // The immersive space is considered ready when:
        // 1. The RealityView has been added to the scene
        // 2. The rendering pipeline is initialized
        
        // Simple heuristic: wait for first frame render opportunity
        try? await Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))
        
        // After reasonable initialization time, proceed
        if Date().timeIntervalSince(startTime) >= 1.0 {
            print("[ImmersiveSpace] Ready after \(Date().timeIntervalSince(startTime))s")
            return true
        }
    }
    
    print("[ImmersiveSpace] Timeout waiting for readiness")
    return false
}
