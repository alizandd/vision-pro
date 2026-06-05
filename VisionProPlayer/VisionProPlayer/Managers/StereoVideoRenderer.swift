import Foundation
import AVFoundation
import CoreMedia
import CoreVideo
import QuartzCore

/// Renders true per-eye stereoscopic video from a *frame-packed* source
/// (side-by-side / over-under) WITHOUT touching the pixels, by injecting
/// Apple Projected Media Profile (APMP) metadata into each frame.
///
/// How it works (visionOS 26+):
/// 1. The existing `AVPlayer` keeps decoding the video and playing the audio.
/// 2. An `AVPlayerItemVideoOutput` taps the decoded frames.
/// 3. A `CADisplayLink` pulls the latest frame each display refresh.
/// 4. For each frame we build a `CMSampleBuffer` whose format description
///    carries APMP extensions describing the frame packing (SBS/OU) and the
///    projection (rectilinear / half-equirect 180° / equirect 360°).
/// 5. The buffer is enqueued into an `AVSampleBufferVideoRenderer`, which a
///    RealityKit `VideoPlayerComponent` uses to render proper stereo per eye.
///
/// This is dramatically cheaper than splitting pixel buffers, because the
/// system reads the tags and routes each half of the frame to the correct eye.
///
/// NOTE: Depth can only be verified on a real Vision Pro — the simulator
/// renders a single eye.
@available(visionOS 26.0, *)
@MainActor
final class APMPStereoRenderer {

    /// Frame packing of the source video.
    enum Packing {
        case sideBySide
        case overUnder
    }

    /// Projection of the source video.
    enum Projection {
        case rectilinear            // Flat 3D
        case halfEquirectangular    // 180° VR
        case equirectangular        // 360° VR
    }

    /// The renderer that a RealityKit `VideoPlayerComponent` consumes.
    let videoRenderer = AVSampleBufferVideoRenderer()

    /// Drives presentation timing for the video renderer.
    private let synchronizer = AVSampleBufferRenderSynchronizer()

    private weak var player: AVPlayer?
    private let packing: Packing
    private let projection: Projection
    private let horizontalFieldOfView: Int32  // thousandths of a degree

    private var videoOutput: AVPlayerItemVideoOutput?
    private var displayLink: CADisplayLink?

    /// Cached, dimension-keyed APMP format description (creating one per frame
    /// would be wasteful — dimensions rarely change mid-stream).
    private var cachedFormatDescription: CMFormatDescription?
    private var cachedDimensions: CMVideoDimensions?

    private var isRunning = false

    /// Whether we've already reported a frame-processing error (avoids spamming
    /// the remote log once per display refresh).
    private var didReportFrameError = false

    /// Whether we've confirmed the first frame was enqueued to the renderer.
    private var didReportFirstFrame = false

    init(packing: Packing, projection: Projection) {
        self.packing = packing
        self.projection = projection
        switch projection {
        case .rectilinear:        self.horizontalFieldOfView = 65_000
        case .halfEquirectangular: self.horizontalFieldOfView = 180_000
        case .equirectangular:    self.horizontalFieldOfView = 360_000
        }
        synchronizer.addRenderer(videoRenderer)
    }

    deinit {
        // displayLink invalidation must happen on main; best-effort here.
        displayLink?.invalidate()
    }

    /// Maps an app `VideoFormat` to an APMP renderer configuration.
    /// Returns nil for formats that aren't frame-packed stereo (no injection needed).
    static func configuration(for format: VideoFormat) -> (packing: Packing, projection: Projection)? {
        switch format {
        case .sideBySide3D:      return (.sideBySide, .rectilinear)
        case .overUnder3D:       return (.overUnder, .rectilinear)
        case .hemisphere180SBS:  return (.sideBySide, .halfEquirectangular)
        case .sphere360SBS:      return (.sideBySide, .equirectangular)
        case .sphere360OU:       return (.overUnder, .equirectangular)
        case .mono2D, .hemisphere180, .sphere360:
            return nil
        }
    }

    /// Attaches to a player and begins pumping frames into the video renderer.
    func start(player: AVPlayer) {
        guard let item = player.currentItem else {
            print("[APMPStereo] No current item to attach to")
            RemoteLog("APMP", "start() failed: player has no current item")
            return
        }
        self.player = player

        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ])
        item.add(output)
        self.videoOutput = output

        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.displayLink = link

        // Present frames as they arrive (we tag each with the synchronizer's clock).
        synchronizer.setRate(1.0, time: .zero)
        isRunning = true
        didReportFrameError = false
        didReportFirstFrame = false
        print("[APMPStereo] Started — packing=\(packing), projection=\(projection)")
        RemoteLog("APMP", "Renderer started — packing=\(packing), projection=\(projection). Pumping frames into VideoPlayerComponent.")

        // Watchdog: if no frame is enqueued shortly after start, the per-eye split
        // isn't happening and the user will still see a single eye / no depth.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3s
            guard let self, self.isRunning, !self.didReportFirstFrame else { return }
            RemoteLog("APMP", "WATCHDOG: no stereo frame after 3s. isRunning=\(self.isRunning) readyForMore=\(self.videoRenderer.isReadyForMoreMediaData) playerRate=\(self.player?.rate ?? -1) hasOutput=\(self.videoOutput != nil). Frames NOT flowing → still single-eye.")
        }
    }

    /// Stops pumping and tears down resources.
    func stop() {
        isRunning = false
        displayLink?.invalidate()
        displayLink = nil
        if let output = videoOutput {
            player?.currentItem?.remove(output)
        }
        videoOutput = nil
        synchronizer.setRate(0, time: .zero)
        videoRenderer.flush()
        cachedFormatDescription = nil
        cachedDimensions = nil
        print("[APMPStereo] Stopped")
        RemoteLog("APMP", "Renderer stopped (firstFrameSeen=\(didReportFirstFrame)).")
    }

    // MARK: - Frame pump

    @objc private func tick(_ link: CADisplayLink) {
        guard isRunning,
              let output = videoOutput,
              videoRenderer.isReadyForMoreMediaData else {
            return
        }

        let itemTime = output.itemTime(forHostTime: link.targetTimestamp)
        guard output.hasNewPixelBuffer(forItemTime: itemTime) else { return }

        var displayTime = CMTime.zero
        guard let pixelBuffer = output.copyPixelBuffer(forItemTime: itemTime,
                                                       itemTimeForDisplay: &displayTime) else {
            return
        }

        do {
            let formatDescription = try apmpFormatDescription(for: pixelBuffer)
            // Present at the synchronizer's current time so the frame shows now,
            // while the AVPlayer continues to drive audio + transport.
            let presentationTime = synchronizer.currentTime()
            let sampleBuffer = try makeSampleBuffer(pixelBuffer: pixelBuffer,
                                                    formatDescription: formatDescription,
                                                    time: presentationTime)
            videoRenderer.enqueue(sampleBuffer)
            if !didReportFirstFrame {
                didReportFirstFrame = true
                let dims = cachedDimensions
                RemoteLog("APMP", "First stereo frame enqueued OK (\(dims?.width ?? 0)x\(dims?.height ?? 0)) — per-eye split is live.")
            }
        } catch {
            print("[APMPStereo] Frame processing failed: \(error)")
            if !didReportFrameError {
                didReportFrameError = true
                RemoteLog("APMP", "Frame processing FAILED: \(error). Stereo will not render.")
            }
        }
    }

    // MARK: - APMP format description

    private func apmpFormatDescription(for pixelBuffer: CVPixelBuffer) throws -> CMFormatDescription {
        let width = Int32(CVPixelBufferGetWidth(pixelBuffer))
        let height = Int32(CVPixelBufferGetHeight(pixelBuffer))

        if let cached = cachedFormatDescription,
           let dims = cachedDimensions,
           dims.width == width, dims.height == height {
            return cached
        }

        // Start from the buffer's own (base) format description so codec/colorimetry match.
        var baseDescription: CMFormatDescription?
        var status = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &baseDescription
        )
        guard status == noErr, let baseDescription else {
            throw RendererError.formatDescriptionFailed(status)
        }

        var extensions: [String: Any] =
            (CMFormatDescriptionGetExtensions(baseDescription) as? [String: Any]) ?? [:]

        // Frame packing (which half is which eye).
        let packingValue: CFString = (packing == .sideBySide)
            ? kCMFormatDescriptionViewPackingKind_SideBySide
            : kCMFormatDescriptionViewPackingKind_OverUnder
        extensions[kCMFormatDescriptionExtension_ViewPackingKind as String] = packingValue

        // Projection (flat / 180 / 360).
        let projectionValue: CFString
        switch projection {
        case .rectilinear:         projectionValue = kCMFormatDescriptionProjectionKind_Rectilinear
        case .halfEquirectangular: projectionValue = kCMFormatDescriptionProjectionKind_HalfEquirectangular
        case .equirectangular:     projectionValue = kCMFormatDescriptionProjectionKind_Equirectangular
        }
        extensions[kCMFormatDescriptionExtension_ProjectionKind as String] = projectionValue
        extensions[kCMFormatDescriptionExtension_HorizontalFieldOfView as String] = horizontalFieldOfView

        let codecType = CMFormatDescriptionGetMediaSubType(baseDescription)
        var apmpDescription: CMFormatDescription?
        status = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: codecType,
            width: width,
            height: height,
            extensions: extensions as CFDictionary,
            formatDescriptionOut: &apmpDescription
        )
        guard status == noErr, let apmpDescription else {
            throw RendererError.formatDescriptionFailed(status)
        }

        cachedFormatDescription = apmpDescription
        cachedDimensions = CMVideoDimensions(width: width, height: height)
        return apmpDescription
    }

    private func makeSampleBuffer(pixelBuffer: CVPixelBuffer,
                                  formatDescription: CMFormatDescription,
                                  time: CMTime) throws -> CMSampleBuffer {
        var timing = CMSampleTimingInfo(duration: .invalid,
                                        presentationTimeStamp: time,
                                        decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        guard status == noErr, let sampleBuffer else {
            throw RendererError.sampleBufferFailed(status)
        }
        return sampleBuffer
    }

    enum RendererError: Error {
        case formatDescriptionFailed(OSStatus)
        case sampleBufferFailed(OSStatus)
    }
}
