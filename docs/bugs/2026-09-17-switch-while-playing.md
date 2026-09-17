# Switching to another video while one is playing sometimes misbehaves

- **Date**: 2026-09-17
- **Reported by**: field use
- **Severity**: High — intermittent, and Play on All had no protection at all
- **Branch**: `fix/stop-before-switch`
- **Status**: Fixed, verified on simulator

## Symptom

Selecting another video and tapping Play This while one is playing sometimes
goes wrong; stopping first and then playing the next one by hand is always
fine. Play on All while a headset is playing individually had the same
exposure.

## Root cause

- The controller's Play This did stop → sleep 1.2 s → play. The headset
  reports `stopped` *before* it begins closing the immersive view and sends
  nothing once the view is closed, so 1.2 s was a guess; a large file's
  teardown can outlast it and `play` lands mid-teardown.
- Play on All sent `syncPrepare` straight away; a busy headset swapped files
  inside its open immersive view — no stop, no teardown.

## Fix

- Headset: one extra `status` (`stopped`, `immersiveMode: false`) after the
  immersive view has closed — on a Stop command and when a video ends.
- Controller: `DeviceManager.stopAndWait` sends `stop` to busy headsets and
  waits for that status (6 s safety net, disconnect counts as done).
  `playSelected` uses it instead of the sleep; `playOnAll` gets a `stopping`
  phase before clock sync. Rules in `StopGate`, tested by `Tests/run.sh`.

## Verification

iOS 26 iPad + visionOS 26.1 simulators, both consoles captured.

| Case | Result |
| --- | --- |
| Play This while playing, headset without the new status | ⏹ → ⚠️ after 6 s → play; video plays |
| Play This while playing, updated headset | ⏹ → ✅ fully stopped (0.5 s) → play |
| Play on All while a headset plays individually, updated headset | ⏹ → ✅ fully stopped (0.4 s) → clock sync → scheduled start |
| Play on All while playing, headset without the new status | STOPPING phase shown → ⚠️ after 6 s → clock sync → scheduled start |
| Switch right after a video ended by itself | Card shows Stopped without Immersive; plays at once, no ⏹ |

Not verified on hardware; the teardown timing is the thing a device pass
should watch (the ✅ line prints how long it took).

## Spec

`docs/superpowers/specs/2026-09-17-stop-before-switch-design.md`
