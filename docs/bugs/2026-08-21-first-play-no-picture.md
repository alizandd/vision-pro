# First playback shows no picture (audio only) until the user stops and replays

- **Date**: 2026-08-21
- **Reported by**: client / field testing
- **Severity**: Critical — the headset wearer sees nothing on the first play
- **Task**: TeamFlow #2445
- **Branch**: `feature/first-play-no-picture`
- **Status**: Fixed

## Symptom

On roughly 70–80% of first plays after the app is launched, sound plays correctly
from the start but the image never appears. Pressing Stop and playing the same
video a second time reliably fixes it for the rest of the session.

## Root cause

The default render path on a real Vision Pro is the per-eye APMP path
(`StereoDebugSettings.trueStereoEnabled` defaults to `true`), implemented in
`VisionProPlayer/Managers/StereoVideoRenderer.swift`. It taps decoded frames with
an `AVPlayerItemVideoOutput` and pumps them into an `AVSampleBufferVideoRenderer`
that a RealityKit `VideoPlayerComponent` displays. Audio stays on the untouched
`AVPlayer`, which is why sound was never affected.

Three defects, in order of importance:

1. **The frame tap was attached too early and never told to wait for media.**
   `NativeVideoPlayerManager.waitForPlayerReadiness()` resolves the moment
   `AVPlayerItem.status == .readyToPlay`, which only means playback *can* begin —
   no video frame has been decoded yet. `APMPStereoRenderer.start()` added the
   `AVPlayerItemVideoOutput` at exactly that moment and immediately started a
   `CADisplayLink` polling `hasNewPixelBuffer(forItemTime:)`. Apple's contract for
   a pull-based output is `requestNotificationOfMediaDataChange(withAdvanceInterval:)`
   plus the `AVPlayerItemOutputPullDelegate` callback before pulling; without it an
   output added before the decoder has produced output can stay permanently dry.
   A cold first play (large file, nothing cached) hits that window; the warm second
   play does not — which is exactly the 70–80% / stop-and-replay-fixes-it signature.

2. **Nothing recovered.** The 3-second watchdog only wrote a log line. Once
   `makeStereoScreenIfEnabled()` installed the renderer it set `activeStereoKey`,
   and `updateVideoScreen()` returned early on every subsequent call forever. A dry
   pump stayed dry for the whole session; the only escape was Stop + Play, which
   tore the pipeline down and rebuilt it.

3. **Frames were timestamped at or behind the presentation clock.** `start()` ran
   `synchronizer.setRate(1.0, time: .zero)` before `player.play()`, and every sample
   was enqueued with `presentationTimeStamp = synchronizer.currentTime()` — already
   due on arrival, so early frames could be discarded as late.

## Fix

- Pull frames the documented way: `AVPlayerItemOutputPullDelegate` +
  `requestNotificationOfMediaDataChange`, with the display link started only from
  `outputMediaDataWillChange`. The request is re-armed if the pump goes dry
  mid-playback (~0.3 s of empty refreshes) and on `outputSequenceWasFlushed`.
- Tag every sample `kCMSampleAttachmentKey_DisplayImmediately`. Pacing is already
  done by the pull side, which asks for exactly the frame due at this refresh, so
  the renderer no longer races its own timestamp against the synchronizer clock.
- Replace the log-only watchdog with a health monitor that calls `onRenderFailure`,
  and have `NativeImmersiveView` fall back to the legacy `VideoMaterial` screen. The
  monitor covers **two** modes: starvation (no frame delivered) and renderer failure
  (`status == .failed`, or the decode-failure notification). `requiresFlushToResumeDecoding`
  is recovered in place rather than treated as fatal. The starvation timer is armed
  from the monitor, **not** from `tick()` — in the starvation case the display link
  never starts, so a timer armed there would never arm at all.
- The starvation timer only starts once the player is genuinely playing, so a
  prepared-but-not-yet-started synchronised session never trips it.
- Fix the stale-output detach in `stop()` (the output was removed from
  `player.currentItem`, which may no longer be the item it was added to), and
  deregister the block-based notification observer by its token.

## Verification

Run on the visionOS 26.1 simulator against the real iOS Controller (Bonjour
discovery, WebSocket, 360° VR 3D (SBS) format):

| Check | Result |
| --- | --- |
| Legacy path still renders on cold first play | Pass — picture visible |
| Pull-delegate handshake (APMP forced on in simulator) | Pass — `Media data available → frame pump running → First stereo frame enqueued` |
| Health monitor does not false-positive while frames flow | Pass — no failure reported over 10 s of playback |
| Starvation → automatic fallback (frame tap deliberately not attached) | Pass — failure reported at 3.0 s, legacy screen rebuilt, **picture appeared**, audio uninterrupted |
| Synchronised playback (`Play on All`) | Pass — `syncPrepare → syncReady → syncStart in 0.993s` |
| Both build slices (simulator Debug, device Release) | Pass |

Two build-time hooks were used for the starvation test (`APMP_TEST_ON_SIM` to run
the APMP path in the simulator, `APMP_FORCE_STARVE` to skip attaching the output).
Both were reverted; no test flags remain in the source.

**Not verified here**: the 70–80% cold-start reproduction on real Vision Pro
hardware, and per-eye stereo depth — the simulator renders a single eye and
cannot run the APMP display path at all. Both need a device pass.

## Depth / per-eye rendering: confirmed unchanged

Checked explicitly, because the fallback is the one thing that could silently cost
stereo depth:

- **The eye-split mechanism is byte-for-byte unchanged.** `configuration(for:)`, the
  `ViewPackingKind` / `ProjectionKind` / `HorizontalFieldOfView` extensions,
  `CMVideoFormatDescriptionCreate`, `VideoPlayerComponent(videoRenderer:)` and the
  output's pixel-buffer attributes are all untouched — the only line that differs in
  that area is a log string.
- **No geometry, UV, mesh, scale or radius line changed** in `NativeImmersiveView`,
  so the legacy path's mapping is identical too.
- **`DisplayImmediately` does not affect depth.** It changes *when* a sample is
  presented, not how it is split. Each sample carries one frame-packed image (both
  eyes in a single buffer), so there is no left/right ordering to disturb, and the
  attachment does not alter the format description the renderer reads to split eyes.
- **The fallback cannot downgrade a working pipeline.** Starvation is guarded by
  `didReportFirstFrame`, so it can only fire before a single frame has ever been
  enqueued. `status == .failed` is terminal per Apple's contract. A decode-failure
  notification only escalates once frames have actually stopped arriving — while
  they are still flowing it is logged and cleared and the per-eye path keeps running
  (tightened after review; treating any decode error as fatal would have cost depth
  for a whole video over one bad frame).
- **A fallback is not sticky across sessions.** `apmpDisabledForKey` is cleared in
  `onDisappear`, so the next immersive session attempts per-eye stereo again.

Net effect: when the per-eye path works it behaves exactly as before. The only
behavioural change is that a pipeline which would previously have shown a black
view now shows the picture in mono instead.

## Related

The same run surfaced a separate, pre-existing defect: `updateVideoScreen()` calls
`videoManager.startPlayback()` whenever it builds a screen, without checking
`autoPlayOnReady`, so each headset plays for ~1 s before the scheduled `syncStart`
during "Play on All". Tracked separately; not fixed here.
