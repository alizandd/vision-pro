# Synchronised sessions start early, and local files hold a 30 s forward buffer

- **Date**: 2026-09-02
- **Reported by**: code review during the audio-only investigation
  (see `2026-09-02-audio-only-422-master.md`)
- **Severity**: High — "Play All" is not actually synchronised, and the
  per-eye path is more likely to be abandoned on group starts
- **Task**: —
- **Branch**: `fix/sync-gate-and-local-buffer`
- **Status**: Fixed in code; needs a device pass

## Symptom

Under "Play All" every headset began playing on its own a second or two
after its player became ready, before the controller's `syncStart` arrived.
The scheduled start then landed on a player that was already running, so
the group was never frame-aligned. On a cold start the per-eye renderer's
3 s starvation window also opened early, so headsets in a group were more
likely than a single-play headset to drop to the flat legacy screen.

The client's field report was that "Play All" misbehaved more often than a
single play.

## Root cause

Two defects, one of them the cause and one a contributor to the memory
pressure seen in the same sessions.

1. **The sync gate only covered one of the two start paths.**
   `handleSyncPrepare` prepared with `autoPlay: false`, and the app's
   `onPlayerReady` handler honoured `autoPlayOnReady`. But
   `NativeImmersiveView.updateVideoScreen()` also calls
   `videoManager.startPlayback()` whenever it (re)builds the screen — which it
   does the moment `isPlayerReady` flips — and `startPlayback()` itself had no
   gate. The view's call reached `player.play()` roughly 50 ms–2 s after
   ready (the ARKit recentre wait), racing `prerollForSync()` and pre-empting
   the scheduled `setRate(_:time:atHostTime:)`.

2. **`preferredForwardBufferDuration = 30` for local files.** The buffer is
   measured in seconds, so its memory cost is bitrate × duration: 30 s of a
   160 Mbps master is ~600 MB of compressed data held on top of the decoder's
   frame pool. A local file reads from flash far faster than any playback
   bitrate, so the buffer bought nothing and only pushed the app towards a
   memory kill. The controller log from the field showed the headset
   re-registering 47 s into playback with no clean disconnect first, which is
   the signature of the process dying.

## Fix

- `NativeVideoPlayerManager.startPlayback()` now returns early while
  `autoPlayOnReady == false`. The scheduled path,
  `startPlayback(atDeviceEpochMs:)`, is unaffected; `resume()` and the
  scheduled resume do not go through the gated method. Normal single-device
  play prepares with `autoPlay: true` and is unchanged.
- `createOptimizedPlayerItem` keeps the 30 s buffer for network URLs and uses
  3 s for `file://` assets.

The view's three `startPlayback()` calls were left in place; with the gate
in the manager they are harmless, and removing them was not verifiable
without a device.

## Verification

- Debug build for the visionOS 26.1 simulator compiles.
- Code trace: sync prepare → `isPlayerReady` → view rebuild → `startPlayback()`
  now returns at the new guard; `syncStart` → `startPlayback(atDeviceEpochMs:)`
  → `setRate` is the first call that moves the player.
- **Still needs a device pass**: confirm a group of headsets stays on the
  per-eye path and starts together, and that memory stays flat during a
  full-length immersive file.
