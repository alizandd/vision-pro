# ADR: Controller-side live preview of what the headset user is watching

**Date**: 2026-08-12
**Status**: Accepted
**Branch**: `feature/controller-live-preview`

## Context

An operator holding the iPhone/iPad controller — in a hotel suite or a sales
centre — cannot see what the person wearing the Vision Pro is currently
experiencing. They need two things at a glance:

1. **Where in the video** the viewer is (elapsed time, progress, state).
2. **What the viewer is actually seeing** right now.

The content is immersive and, in most formats the player supports
(`sbs3d`, `ou3d`, `hemisphere180sbs`, `sphere360sbs`, `sphere360ou`),
**stereoscopic** — two eye images packed into one frame. Anything that naively
shows a raw frame to the operator displays a doubled, distorted image.

This system is **already running in production**. Any change must be additive:
with no preview configured, behaviour must be byte-for-byte what it is today.

## Options considered

1. **Play the same immersive file on the tablet.** Rejected. The library holds
   files of 1.5 GB and 4.6 GB; copying them to a phone is impractical, and the
   tablet would additionally need equirectangular + per-eye unwarping to render
   them correctly. Two hard problems for a small preview.

2. **Stream frames from the headset.** The headset grabs frames from its own
   player, crops to the viewer's field of view and to one eye, downscales, and
   pushes JPEGs over the WebSocket. Highest truthfulness, but costs headset
   CPU/GPU during playback of very large media, consumes bandwidth on the same
   link that carries control messages, and at a tolerable frame rate looks like
   a slideshow. Kept as a possible future addition, not v1.

3. **Full ReplayKit mirror.** visionOS does support ReplayKit broadcast, but it
   requires a broadcast upload extension **and** the wearer pressing the system
   Start Broadcast button on the headset every session — it cannot be initiated
   from the controller. It also captures passthrough (the real room), which is
   unacceptable in a customer-facing venue.

4. **Paired companion video (chosen).** For each immersive video, a small,
   flat, mono, already-edited MP4 of identical duration is imported onto the
   controller and paired to it. When the headset plays, the controller plays the
   companion in lockstep and overlays the viewer's head direction.

## Decision

Adopt option 4, with a head-direction indicator layered on top.

**Why it wins.** The companion is authored flat and mono, so the stereo problem
never arises — no cropping, no projection maths, no shaders on the tablet. The
file is small enough to transfer and store comfortably. An edited flat cut is
also more legible on a 10-inch screen than a raw equirectangular frame would be.

**Why the indicator is required.** A companion video shows what the *content*
contains, not where the viewer is *looking*. In 360° material the viewer may be
facing away from whatever the editor framed. Head yaw is already available —
`ARKitSession` + `WorldTrackingProvider.queryDeviceAnchor` already run in
`NativeImmersiveView` for recentering — so publishing it costs a few hundred
bytes per second, no new framework and no new permission. Gaze/eye tracking is
deliberately **not** used: visionOS does not expose it to apps.

### Constraints this decision imposes

- **Durations must match.** A companion trimmed or recut relative to the
  immersive original silently shows the operator the wrong moment. Pairing
  verifies duration and refuses a mismatch beyond a small tolerance.
- **Pairing is explicit, not magical.** Base filename is used to *suggest* a
  pairing; the operator confirms it, and can override. A missing companion is a
  clearly-labelled state, never a wrong picture.
- **Sync is continuous, not per-status-message.** The companion plays on its own
  clock and is corrected against the headset's reported media time, reusing the
  clock-offset already measured by `SyncSessionManager`. Seeking on every status
  update would stutter.

### Non-negotiable compatibility rule

With **no companion paired**, the controller behaves exactly as it does today:
same device card, same controls, same messages on the wire. The preview is
strictly additive. The Vision Pro app publishes head pose only while an
immersive space is open and only when a preview is subscribed.

## Consequences

- Someone must author a flat companion cut per immersive video. Acceptable for a
  curated library; it does not scale to arbitrary user media, which is why the
  no-companion fallback is a first-class state rather than an error.
- The controller gains a media import surface (Photos **and** Files, so material
  can come from any drive or cloud provider) and a small companion library.
- Preview accuracy is bounded by the editor's discipline, not by the software.
- If the direction indicator proves to be noise in real use, it can be removed
  without touching the companion-playback path.
