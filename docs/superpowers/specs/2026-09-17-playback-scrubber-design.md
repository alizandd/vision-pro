# Playback scrubber — seek from the controller, single headset and group

- **Date**: 2026-09-17
- **Status**: Approved design, not yet implemented
- **Applies to**: VPC Remote (controller) and VPC Player (headset), after 1.8 (1) / 3.7 (1)

## Goal

The operator can jump to any point in the video from the controller: on one
headset from its card, and on every headset in a Play on All session from the
Synchronized Playback panel, with the group staying in sync. The watch-along
preview follows the headset as it does today.

## Decisions taken

| Question | Decision |
| --- | --- |
| Single headset, group, or both | Both. Group seek stays synchronised. |
| Drag behaviour | Seek on release only. No live scrubbing. |
| When the bar is shown | Whenever the headset has a video loaded (playing, paused, loading) — with or without a paired preview. |
| Group mechanism | Reuse `syncPause` + `syncResume { mediaTime, startAt }`. No new scheduled path on the headset. |

Rejected: a scheduled `seek { startAt }` command (duplicates `syncResume` on the
headset, the side that only gets verified on real devices); seeking only the
preview (does not control the headset).

## Part 1 — Protocol and headset

One new command, single headset only:

```json
{ "type": "command", "action": "seek", "mediaTime": 42.5 }
```

Headset (`Models.swift` `CommandAction.seek`, `WebSocketManager` parsing,
`VisionProPlayerApp` routing, `NativeVideoPlayerManager.seek(toMediaTime:)`):

- `mediaTime` is clamped to `0…duration`, then the player seeks with zero
  tolerance — the same call `scheduledResume` uses.
- Playback state is unchanged: playing stays playing, paused stays paused on
  the new frame.
- When the seek completes, the headset sends one `status` with the new
  `currentTime` and the unchanged state, so the controller updates even though
  no state changed. The 10 Hz `viewerState` feed (when subscribed) continues
  from the new position.
- Ignored when no player is loaded.

No headset change for the group path. A group seek arrives as `syncPause`
followed by `syncResume { mediaTime, startAt }`, both already handled: seek to
`mediaTime`, preroll, start at the scheduled tick.

## Part 2 — Controller: scrubber on a headset card

New view `PlaybackScrubber` (`iOSController/PlaybackScrubber.swift`), reused by
the card and by the sync panel. Inputs: position, duration, `isEnabled`, an
optional hint string, and an `onSeek(Double)` callback. It owns only the
drag/hold state described below.

**Placement in the card** (`CompanionPreviewView`, which already decides what
to show for a loaded video):

- Preview paired: picture → scrubber → direction indicator → preview file
  name. The position badge currently drawn in the picture's corner is removed;
  the times live on the bar.
- No preview paired: the "No preview video for this one" notice becomes a
  single line, with the scrubber under it.

**Display.** A `Slider` over `0…duration`, position on the left (`0:53`),
running time on the right (`4:12`). While playing the thumb follows the live
position. If `duration` is nil (still loading, or an older headset build), the
bar is disabled and shows `--:--`.

**Live position feed.** The `previewSubscribe` subscription is currently
enabled only while a paired preview picture is on screen. It becomes: enabled
while a scrubber is visible — card expanded and video loaded — regardless of
pairing. Cost is unchanged per open card; collapsed cards subscribe to nothing.
Side effect: the position for unpaired headsets is now live rather than frozen
between state changes.

**Dragging.** On touch-down the thumb stops following the feed and the left
time shows the target. On release:

1. Send `seek { mediaTime: target }` to the headset.
2. Log `⏩ Seek <device> → m:ss` in the Activity Log.
3. Hold the thumb at the target until a live position arrives within 1 s of
   it, or 2 s elapse — whichever first — then resume following the feed. This
   prevents the thumb snapping back to the stale position while the headset
   catches up.

**During a group session.** If the headset is an active device of a
`SyncSessionManager` session in state `playing` or `paused`, the card's
scrubber shows position but is disabled with the hint "Use the Synchronized
Playback bar". Out of scope, noted: the card's Play/Pause/Stop are not gated
during a session today either.

## Part 3 — Controller: group seek

The same `PlaybackScrubber`, placed in `SyncControlPanel` between the device
chips and the Pause All / Stop All row, visible only while the session is
`playing` or `paused`.

- **Position**: the furthest-ahead active device's live position — the rule
  `resumeAll` already uses.
- **Duration**: from the active devices' reported duration (same file on all).

**On release → `SyncSessionManager.seekAll(to mediaTime: Double)`:**

1. Session `playing`: send `syncPause` to every active device, then
   `scheduleStart(mediaTime:)` — `resumeAll` with the operator's time instead
   of the measured one. All headsets seek, preroll and restart on the same
   clock tick with the usual lead time. Session state stays `playing`.
2. Session `paused`: send `seek { mediaTime }` to each active device. Nothing
   restarts. Set each active device's stored `currentTime` to the target so the
   next `resumeAll` starts from there. Session state stays `paused`.
3. Devices not active in the session are untouched, as with every group
   command.

While a case-1 restart is pending (the lead time), the panel's scrubber is
disabled so a second drag cannot overlap. The thumb holds at the target under
the same rule as the card.

**Logging**: `⏩ Group seek → m:ss (N devices)`, followed by the existing
`Sync resume scheduled (+1000ms)` line.

Per-card scrubbers of the session's devices are disabled meanwhile (Part 2).

## Part 4 — Edge cases

| Case | Behaviour |
| --- | --- |
| Target outside `0…duration` | Clamped by the slider and again by the headset. |
| Headset disconnects mid-drag | Command has no recipient; the card is removed anyway. No handling. |
| Headset still loading | Bar disabled until `duration` is reported (nil during loading since the 2026-09-17 fix). |
| Preview after a seek | No change: the companion player's existing drift logic seeks when the headset jumps > 1 s. |
| Group paused → seek → Resume All | Resumes from the seek target (Part 3, case 2). Named test. |
| Older headset without `seek` | Unknown actions are ignored by the headset parser; the bar stays disabled anyway because older builds do not report `duration`. |

**Out of scope**: ±10 s skip buttons, hardware/keyboard shortcuts, seeking
while the immersive space is closed, live scrubbing.

## Testing

Simulators (iOS 26 iPad + visionOS 26.1) with the headset console captured,
then a device pass.

| Case | Expect |
| --- | --- |
| Single card, playing, drag to 2:00 | Headset log `Seek to 120.0s`; status arrives; thumb holds then follows; preview jumps with it |
| Single card, paused, drag | New frame, still Paused; Resume continues from there |
| Card without preview | Scrubber visible and working, position ticking |
| Card during a group session | Scrubber disabled with hint |
| Group playing, drag to 1:30 | Log `Group seek → 1:30`; headset `Sync pause` → `Sync resume at 90.0s`; session stays PLAYING |
| Group paused, drag, then Resume All | Headset resumes at the seek target, not the old pause time |
| Drag to end of file | Clamps; video ends normally |
| Regression: Play, Pause/Resume/Stop, Play on All, Pause All/Resume All/Stop All, preview first-play | Unchanged |

## Files

- Headset: `Models.swift`, `WebSocketManager.swift`, `VisionProPlayerApp.swift`,
  `Managers/NativeVideoPlayerManager.swift`
- Controller: `Models.swift`, `DeviceManager.swift`, `SyncSessionManager.swift`,
  `CompanionPreviewView.swift`, `SyncControlPanel.swift`, new `PlaybackScrubber.swift`
- Docs: `CLAUDE.md` protocol section and changelog; operator guide section 10
  and 11 gain a short "jumping to a point in the video" note; ADR
  `docs/adr/2026-09-17-playback-scrubber.md` recording the group-seek decision.
