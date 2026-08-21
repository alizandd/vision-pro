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
/// 2. An `AVPlayerItemVideoOutput` taps the decoded frames. The tap only
///    starts being pulled once it reports, via `AVPlayerItemOutputPullDelegate`,
///    that media data is actually available — polling it before the decoder has
///    produced output leaves it permanently dry (see `startDisplayLink`).
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
final class APMPStereoRenderer: NSObject {

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

    /// The item the video output was added to. Held explicitly so `stop()`
    /// detaches the output from the item it was actually attached to, even if
    /// the player has since moved on to a different item.
    private weak var attachedItem: AVPlayerItem?

    /// Queue the pull delegate is called back on.
    private let outputQueue = DispatchQueue(label: "com.visionproplayer.apmp.output")

    /// True while a `requestNotificationOfMediaDataChange` is outstanding, so
    /// we never stack duplicate requests.
    private var isAwaitingMediaData = false

    /// Consecutive display refreshes that produced no new pixel buffer while the
    /// player was playing. Used to re-arm the media-data notification if the
    /// pump ever goes dry mid-playback.
    private var dryTickCount = 0

    /// Host time at which the player was first observed actually playing after
    /// `start()`, sampled by the health monitor. The starvation timeout measures
    /// from here rather than from `start()`, so a prepared-but-not-yet-started
    /// (synchronised) session is never mistaken for a failure.
    private var playbackObservedAt: CFTimeInterval?

    /// Seconds of real playback with zero delivered frames after which the
    /// stereo pipeline is declared dead and `onRenderFailure` fires.
    private let starvationTimeout: CFTimeInterval = 3.0

    /// Called on the main actor when the per-eye pipeline is judged dead — either
    /// no frame ever reached the renderer despite the player genuinely playing,
    /// or the renderer itself failed to decode or present what it was given. Both
    /// look identical to the wearer. The view uses this to abandon the per-eye
    /// path and fall back to the legacy `VideoMaterial` screen, so the picture is
    /// visible instead of a black view.
    var onRenderFailure: ((String) -> Void)?

    /// Set from the decode-failure notification, so the health monitor can act on
    /// a renderer that is being handed frames but cannot decode them.
    private var decodeFailure: String?

    /// Guards against reporting failure more than once.
    private var didReportFailure = false

    /// Token for the block-based decode-failure observer. Block observers are
    /// only removable by their token — `removeObserver(self,…)` does not touch
    /// them — so it has to be kept to deregister cleanly in `stop()`.
    private var decodeFailureObserver: NSObjectProtocol?

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
        // NSObject base is required: AVPlayerItemOutputPullDelegate refines
        // NSObjectProtocol, and CADisplayLink needs an Obj-C selector target.
        super.init()
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
    ///
    /// The display link is deliberately NOT started here. `AVPlayerItemVideoOutput`
    /// only begins vending pixel buffers once the decoder has produced output, and
    /// an output that is polled before that point can stay dry for the whole
    /// session — the player keeps playing audio while the renderer never receives
    /// a single frame, which the wearer sees as sound with a black view. Apple's
    /// contract for a pull-based output is to ask for
    /// `requestNotificationOfMediaDataChange(withAdvanceInterval:)` and start
    /// pulling from `outputMediaDataWillChange(_:)`, which is what we do.
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
        output.setDelegate(self, queue: outputQueue)
        item.add(output)
        self.videoOutput = output
        self.attachedItem = item

        // Present frames as they arrive (each sample is tagged for immediate
        // display, so this clock only has to be running — not aligned).
        synchronizer.setRate(1.0, time: .zero)
        isRunning = true
        didReportFrameError = false
        didReportFirstFrame = false
        didReportFailure = false
        dryTickCount = 0
        playbackObservedAt = nil
        decodeFailure = nil
        print("[APMPStereo] Started — packing=\(packing), projection=\(projection)")
        RemoteLog("APMP", "Renderer started — packing=\(packing), projection=\(projection). Waiting for the video output to report media data.")

        observeRendererFailures()
        requestMediaDataNotification()
        startHealthMonitor()
    }

    /// Watches the renderer's own failure signals. A renderer that receives
    /// frames but cannot decode them leaves the wearer with the same black view
    /// as one that receives nothing, so both have to reach `onRenderFailure`.
    private func observeRendererFailures() {
        guard decodeFailureObserver == nil else { return }
        decodeFailureObserver = NotificationCenter.default.addObserver(
            forName: AVSampleBufferVideoRenderer.didFailToDecodeNotification,
            object: videoRenderer,
            queue: .main
        ) { note in
            let error = note.userInfo?[AVSampleBufferVideoRenderer.didFailToDecodeNotificationErrorKey] as? Error
            let description = error?.localizedDescription ?? "unknown decode error"
            Task { @MainActor [weak self] in
                self?.decodeFailure = description
            }
        }
    }

    /// Asks the output to tell us when frames are available. Until that callback
    /// arrives there is nothing to pull, so the display link stays off.
    private func requestMediaDataNotification() {
        guard let output = videoOutput, isRunning, !isAwaitingMediaData else { return }
        isAwaitingMediaData = true
        output.requestNotificationOfMediaDataChange(withAdvanceInterval: 0.1)
    }

    /// Begins pulling frames each display refresh. Safe to call repeatedly.
    private func startDisplayLink() {
        guard isRunning, displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        print("[APMPStereo] Media data available — frame pump running")
        RemoteLog("APMP", "Video output reported media data — frame pump started.")
    }

    /// Watches the whole per-eye pipeline and reports it dead when the wearer
    /// would otherwise be left looking at a black view. Two distinct modes:
    ///
    /// * **Starvation** — no frame ever reaches the renderer despite the player
    ///   genuinely playing. Timing starts from the first moment playback is
    ///   actually observed, so a prepared-but-not-yet-started (synchronised)
    ///   session never trips it.
    /// * **Renderer failure** — frames are delivered but the renderer cannot
    ///   decode or present them.
    ///
    /// A renderer that merely needs a flush is recovered in place, not abandoned.
    private func startHealthMonitor() {
        Task { @MainActor [weak self] in
            // Give up watching after 60s; by then the session is long decided.
            for _ in 0..<120 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let self, self.isRunning, !self.didReportFailure else { return }

                // Note the first moment the player is genuinely playing. This has
                // to happen HERE and not in tick(): in the starvation case the
                // display link never starts, so tick() never runs and a timer
                // armed there would never arm at all.
                if self.playbackObservedAt == nil, (self.player?.rate ?? 0) > 0 {
                    self.playbackObservedAt = CACurrentMediaTime()
                }

                // Recoverable: the decoder wants a flush before it resumes.
                if self.videoRenderer.requiresFlushToResumeDecoding {
                    print("[APMPStereo] Renderer requires flush to resume decoding — flushing")
                    self.videoRenderer.flush()
                    self.requestMediaDataNotification()
                    continue
                }

                if self.videoRenderer.status == .failed {
                    self.reportFailure("renderer status failed: \(self.videoRenderer.error?.localizedDescription ?? "no error given")")
                    return
                }

                if let decodeFailure = self.decodeFailure {
                    self.reportFailure("decode failed: \(decodeFailure)")
                    return
                }

                guard !self.didReportFirstFrame else { continue }
                guard let observedAt = self.playbackObservedAt else { continue }
                guard CACurrentMediaTime() - observedAt >= self.starvationTimeout else { continue }

                self.reportFailure("no frame after \(self.starvationTimeout)s of real playback (readyForMore=\(self.videoRenderer.isReadyForMoreMediaData) playerRate=\(self.player?.rate ?? -1) awaitingMediaData=\(self.isAwaitingMediaData))")
                return
            }
        }
    }

    /// Reports the pipeline dead, once.
    private func reportFailure(_ reason: String) {
        guard !didReportFailure else { return }
        didReportFailure = true
        print("[APMPStereo] HEALTH: \(reason) — reporting render failure")
        RemoteLog("APMP", "HEALTH: the per-eye pipeline is not producing a picture — \(reason). Falling back to the legacy path so the picture is visible.")
        onRenderFailure?(reason)
    }

    /// Stops pumping and tears down resources.
    func stop() {
        isRunning = false
        onRenderFailure = nil
        if let decodeFailureObserver {
            NotificationCenter.default.removeObserver(decodeFailureObserver)
            self.decodeFailureObserver = nil
        }
        displayLink?.invalidate()
        displayLink = nil
        if let output = videoOutput {
            // Detach from the item the output was actually added to — the player
            // may already have moved on to a different item.
            attachedItem?.remove(output)
            output.setDelegate(nil, queue: nil)
        }
        videoOutput = nil
        attachedItem = nil
        isAwaitingMediaData = false
        playbackObservedAt = nil
        dryTickCount = 0
        decodeFailure = nil
        didReportFailure = false
        synchronizer.setRate(0, time: .zero)
        videoRenderer.flush()
        cachedFormatDescription = nil
        cachedDimensions = nil
        print("[APMPStereo] Stopped")
        RemoteLog("APMP", "Renderer stopped (firstFrameSeen=\(didReportFirstFrame)).")
    }

    // MARK: - Frame pump

    @objc private func tick(_ link: CADisplayLink) {
        guard isRunning, let output = videoOutput else { return }

        guard videoRenderer.isReadyForMoreMediaData else { return }

        let itemTime = output.itemTime(forHostTime: link.targetTimestamp)
        guard output.hasNewPixelBuffer(forItemTime: itemTime) else {
            // The pump can go dry mid-playback (a stall, a seek, a decoder
            // hiccup). Re-arm the notification rather than spinning on an output
            // that has nothing to give.
            if (player?.rate ?? 0) > 0 {
                dryTickCount += 1
                if dryTickCount >= 30 {   // ~0.3s at 90Hz
                    dryTickCount = 0
                    requestMediaDataNotification()
                }
            }
            return
        }
        dryTickCount = 0

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
                print("[APMPStereo] First stereo frame enqueued")
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

        // Pacing is already done by the pull side: the display link asks the
        // output for exactly the frame due at this refresh. Tell the renderer to
        // show whatever it is handed instead of comparing the timestamp against
        // the synchronizer's clock — a sample stamped with "now" is, by the time
        // the renderer dequeues it, marginally in the past and can be discarded
        // as late. That race is what made the picture appear only sometimes.
        markForImmediateDisplay(sampleBuffer)
        return sampleBuffer
    }

    /// Sets `kCMSampleAttachmentKey_DisplayImmediately` on the sample.
    private func markForImmediateDisplay(_ sampleBuffer: CMSampleBuffer) {
        guard let rawAttachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer,
                                                                           createIfNecessary: true),
              CFArrayGetCount(rawAttachments) > 0 else { return }
        let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(rawAttachments, 0),
                                       to: CFMutableDictionary.self)
        CFDictionarySetValue(dictionary,
                             Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                             Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
    }

    enum RendererError: Error {
        case formatDescriptionFailed(OSStatus)
        case sampleBufferFailed(OSStatus)
    }
}

// MARK: - AVPlayerItemOutputPullDelegate

@available(visionOS 26.0, *)
extension APMPStereoRenderer: AVPlayerItemOutputPullDelegate {

    /// The output is about to have frames for us. This is the only safe moment
    /// to begin pulling — starting the display link before this arrives is what
    /// leaves the renderer permanently starved on a cold first play.
    nonisolated func outputMediaDataWillChange(_ sender: AVPlayerItemOutput) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isAwaitingMediaData = false
            self.startDisplayLink()
        }
    }

    nonisolated func outputSequenceWasFlushed(_ output: AVPlayerItemOutput) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.videoRenderer.flush()
            self.dryTickCount = 0
            self.requestMediaDataNotification()
        }
    }
}
