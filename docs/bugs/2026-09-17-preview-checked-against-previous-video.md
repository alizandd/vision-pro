# Preview withheld on the first play of every video; Stop + Play again fixes it

- **Date**: 2026-09-17
- **Reported by**: client, on two headsets
- **Severity**: High — every watch-along preview fails the first time, and the
  message blames the operator's file
- **Branch**: `fix/preview-stale-duration`
- **Status**: Fixed, verified on simulator

## Symptom

With a correctly paired preview video (same running time as the headset file),
the first play of each video shows **Preview not shown — `<preview>` runs 2:14 but
the headset video runs 2:17**. Stopping and playing the same video again makes
the preview work. Playing a different video brings the message back.

The "headset" running time in the message is not the running time of the video
that is playing. It is the running time of the video played **before** it.

## Root cause

Two things in the controller (VPC Remote) combined. The headset is not involved.

1. **The controller carried a running time over from one video to the next.**
   `DeviceManager.onStatusUpdate` stored `message.duration` only when it was
   `> 0`. The headset reports `0` for the whole of loading (`stop()` resets
   `duration` before `prepareVideo` runs, and `.loading` / `.stopped` statuses go
   out with that 0), so the controller kept whatever it had learned last — the
   previous video's length — and attached it to the new video.

2. **The preview checked the length exactly once.** `CompanionPreviewView`
   ran `CompanionPairingStore.verify` from `.task(id: companion.id)`, i.e. when
   the preview panel appeared. That is while the status is still `.loading`, so
   the check ran against the stale value and withheld the preview. When the real
   running time arrived a moment later (in the `.playing` status), nothing
   re-ran the check.

Why Stop + Play again works: during the first play the controller did receive
the right running time. Stop sends 0, which was ignored, so the right value
survived, and the second play's one-shot check passed. Why the *next* video
fails again: it inherits this video's running time.

## Fix

Controller only (`iOSController/iOSController/`):

- `DeviceManager.swift` — a status message whose `currentVideo` differs from the
  stored one clears `duration` first. A reported `0` is now stored as `nil`
  ("not known yet"), not ignored. Only a message that **omits** the field (a
  headset on an older build) leaves the stored value alone, which keeps the
  original backwards-compatibility intent.
- `CompanionPreviewView.swift` — the verify-and-load step is factored into
  `verifyAndLoad(_:)` and also runs from `.onChange(of: device.state.duration)`,
  so the check repeats when the real running time lands. Calling it repeatedly is
  safe: `CompanionPreviewPlayer.load` is a no-op for an already-loaded companion,
  and `withhold` is a no-op for an unchanged reason.

## Verification

iOS 26 iPad simulator (VPC Remote) against the visionOS 26.1 simulator
(VPC Player), Bonjour + WebSocket, 360° VR 3D (SBS). `Lobby_Tour.mp4` (4:12) is
paired with `Lobby_Tour.mov` (4:12); for the mismatch case `SyncTest.mp4` (5:00)
was temporarily paired with the same 4:12 companion.

| Check | Before | After |
| --- | --- | --- |
| Play a 0:10 video, then Lobby Tour (paired, matching length) | Withheld: "runs 4:12 but the headset video runs **0:10**" | Preview shown on first play |
| Play SyncTest (5:00) with the 4:12 companion — a real mismatch | Withheld, but quoting the *previous* video's length | Withheld, quoting **5:00** — the correct length |
| Switch straight from that mismatch to Lobby Tour | Withheld until Stop + Play again | Preview shown on first play |

Not verified on hardware; the logic is entirely in the controller's handling of
status messages, which the simulator exercises identically.

## Related

Section 14 of the operator guide (`docs/guide`, on `fix/sync-gate-and-local-buffer`)
tells operators to pair while the film is loaded on the headset. That advice
stands; it is about the pairing sheet's own check, which reads the stored
running time and was affected by the same stale value in the window between two
videos.
