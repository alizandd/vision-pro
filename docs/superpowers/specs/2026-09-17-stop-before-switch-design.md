# Stop before switch — fully stop the previous video before starting the next

- **Date**: 2026-09-17
- **Status**: Approved design, not yet implemented
- **Applies to**: VPC Remote (controller) and VPC Player (headset), after the
  playback-scrubber work (merged to `main` 2026-09-17)

## Problem

Switching from a playing video to another one sometimes misbehaves; stopping
first and then playing the next one by hand is always fine. The code already
half-does this for a single headset, but not reliably, and not at all for a
group:

- **Single headset ("Play This")** — `DeviceManager.playSelected` sends `stop`,
  sleeps a fixed **1.2 s**, then sends `play`. The headset reports `stopped`
  *before* it begins closing the immersive view, and sends nothing once the
  view is closed. So the controller has no signal for "fully stopped"; on a
  large file the teardown can outlast the 1.2 s and `play` lands mid-teardown.
- **Play on All** — `syncPrepare` is sent straight away. A headset that is
  playing something swaps the file inside the open immersive view; no stop, no
  teardown.

## Decision

Full teardown on every switch — the immersive view closes, the wearer briefly
sees the app window, and the next video opens a fresh view. This is exactly
the manual "Stop, then Play" sequence known to be reliable, and the memory
note in `handlePlayCommand` (open the space before loading a large asset)
applies to the fresh space.

Approach A of the three considered: the controller orchestrates
stop → wait → play, and the headset gains one status so the wait has
something real to wait for. Rejected: headset-enforced teardown inside
`play`/`syncPrepare` (only verifiable on a device, invisible to the operator)
and a longer fixed delay (still a guess).

## Part 1 — Headset: the "fully stopped" status

After the immersive space has been dismissed and the main window reopened,
the headset sends one `status` with `state: "stopped"` and
`immersiveMode: false`. Two places dismiss the space and both send it:

- the `.stop` / `.syncStop` command handler in `VisionProPlayerApp`, after
  `openWindow(id: "main")`;
- the playback-ended path (`onPlaybackEnded`), after its dismissal.

Nothing else changes on the headset. A controller that does not care sees one
extra status line. Older headset builds never send it; the controller's
timeout (Part 2) covers them.

## Part 2 — Controller: `stopAndWait`, then play

New helper on `DeviceManager`:

```swift
/// Sends `stop` to every busy headset in `deviceIds` and waits until each has
/// reported stopped with the immersive view closed, or `timeout` has passed.
func stopAndWait(deviceIds: [String], timeout: TimeInterval = 6) async
```

Behaviour:

1. **Busy** means `playbackState` is `playing`, `paused` or `loading`, **or**
   `immersiveMode` is still `true`. Busy headsets get `stop`; idle ones are
   skipped, so a cold start adds no delay.
2. **Done** for a headset means `playbackState` is `stopped` or `idle` **and**
   `immersiveMode == false` — or the headset has disconnected. The wait is
   event-driven: `onStatusUpdate` resolves it as soon as a qualifying status
   arrives. A headset that already satisfies the condition resolves at once.
3. **Timeout**: 6 s per headset, all waited in parallel. On timeout, log a
   warning and continue — the operator is never stranded.

Implementation: a `[String: CheckedContinuation<Void, Never>]` of pending
waits keyed by device id, resolved from `onStatusUpdate` and from the
disconnect handler; the timeout races via `Task.sleep`. Each continuation is
resumed exactly once.

Activity Log lines:

- `⏹ Stopping <device> before the next video`
- `✅ <device> fully stopped (1.8 s)`
- `⚠️ <device> did not confirm the stop within 6 s — continuing`

Call sites:

- **`playSelected`** — replaces the 1.2 s sleep: `await stopAndWait([id])`,
  then `play`. The optimistic "stopped" UI update stays.
- **`SyncSessionManager.playOnAll`** — a new first phase. `SessionState`
  gains `.stopping`; the manager calls a new hook
  `stopBusyDevices: (([String]) async -> Void)?` (wired by `DeviceManager` to
  `stopAndWait`) before clock sync. `SyncControlPanel` shows
  "Stopping current videos…" for `.stopping`, alongside the existing
  "Syncing clocks…" / "Preparing devices…". `isSessionActive` treats
  `.stopping` as active so the Play on All button cannot be tapped twice.

## Edge cases

| Case | Behaviour |
| --- | --- |
| Headset already idle | No `stop` sent, no wait. |
| Headset disconnects during the wait | Counts as done; the play/prepare that follows fails for it as it does today. |
| Older headset build (no post-close status) | Waits the full 6 s, then continues. Slower than today's 1.2 s, but no longer racing. |
| Operator taps Play This twice quickly | The second `playSelected` runs the same stop-and-wait; the headset ends up on the last requested video. No special handling. |
| Play on All while a group session is already running | Unchanged: the button is not shown; Stop All first. |

## Testing

Simulators (iOS 26 iPad + visionOS 26.1), headset console captured.

| Case | Expect |
| --- | --- |
| Single: switch while playing | Headset log `Stopping` → status `stopped, immersiveMode:false` → `PLAY COMMAND`; controller log `⏹ … → ✅ … fully stopped (x s)`; new video plays |
| Play on All while a headset is playing individually | Same stop/confirm sequence, then `Measuring clock offsets…` and the normal sync start |
| Play on All from idle | No `⏹` line, session starts immediately |
| Timeout path: new controller against the previous headset build | `⚠️ … did not confirm the stop within 6 s — continuing`, then the video still plays |
| Regression: play / pause / resume / stop, scrubber, preview first-play | Unchanged |

## Files

- Headset: `VisionProPlayer/VisionProPlayer/VisionProPlayerApp.swift`
- Controller: `iOSController/iOSController/DeviceManager.swift`,
  `SyncSessionManager.swift`, `SyncControlPanel.swift`
- Docs: `CLAUDE.md` changelog; operator guide section 10 note ("Play This
  stops the current video first — the wearer sees the window for a moment").
