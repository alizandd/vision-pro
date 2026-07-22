# ADR: Synchronized multi-device playback (Play on All)

**Date**: 2026-07-22
**Status**: Accepted
**Branch**: `claude/sync-playback`

## Context

Multiple Vision Pro headsets connect to one iOS Controller. Today each headset is
controlled individually from its own device card, so starting the same video on
N headsets is manual and unsynchronized. We need group playback: play, pause,
resume, and stop applied to all connected devices at the same moment.

The serverless architecture applies: iOS Controller is the hub (WebSocket 8080 +
HTTP 8081); there is no relay server.

## Options considered

1. **Naive broadcast** — send `play` to every device in a loop. Rejected: each
   Vision Pro takes ~1.5 s to open its immersive space plus a variable video
   load time, so starts diverge by seconds.
2. **Two-phase prepare/commit + scheduled start (chosen)** — see below.
3. **Continuous drift-corrected sync** (periodic rate adjustment against a
   master clock). Rejected for v1: playback of identical local files started
   simultaneously drifts only a few ms/min; complexity not justified. Possible
   future enhancement.

## Decision

Two-phase orchestration with clock-offset scheduling:

1. **Clock sync** — the controller measures each device's clock offset with a
   `clockSync` request/response (NTP-style: offset ≈ t1 − (t0 + t2)/2 using
   epoch-ms timestamps). Offsets are stored per device and refreshed before
   each sync session. Expected accuracy on LAN: ±10 ms.
2. **Prepare** — controller sends `syncPrepare` (filename, format) to all
   target devices. Each Vision Pro opens its immersive space, preloads the
   local video, prerolls the AVPlayer, and replies `syncReady`. The controller
   waits at a readiness barrier (15 s timeout; devices that miss it are
   reported and excluded).
3. **Start** — controller picks `startAt = now + 1 s` (controller clock) and
   broadcasts `syncStart(startAt)`. Each device converts `startAt` to its own
   clock using the measured offset and schedules playback with
   `AVPlayer.setRate(_:time:atHostTime:)`.
4. **Group controls** — `syncPause` broadcasts immediately; `syncResume`
   re-uses the scheduled-start mechanism (resume at media time M at wall time
   T) so devices stay aligned; `syncStop` is a plain broadcast.

Preconditions: the video must already exist locally on every target device
(transferred beforehand). The sync UI offers only videos present on **all**
connected devices (intersection by filename).

## Protocol additions

| Message | Direction | Fields |
|---|---|---|
| `clockSync` | controller → device | `t0` (epoch ms) |
| `clockSyncResponse` | device → controller | `t0`, `t1` (device epoch ms) |
| `command/syncPrepare` | controller → device | `filename`, `videoFormat` |
| `syncReady` | device → controller | `deviceId`, `filename`, `success`, `message?` |
| `command/syncStart` | controller → device | `startAt` (epoch ms, controller clock) |
| `command/syncPause` | controller → device | — |
| `command/syncResume` | controller → device | `mediaTime` (s), `startAt` (epoch ms) |
| `command/syncStop` | controller → device | — |

Backwards compatible: existing per-device commands are untouched.

## Components

- **iOS Controller — `SyncSessionManager`**: session state machine
  (idle → syncing clocks → preparing → ready → playing → paused), offset
  measurement, readiness barrier, group command fan-out.
- **iOS Controller — Sync UI**: "Play on All" panel above the device list:
  common-video picker, format picker, play/pause/resume/stop-all buttons,
  per-device readiness/status chips.
- **Vision Pro — sync command handling**: `syncPrepare` path (open immersive
  space → prepare player → preroll → report ready, without auto-play),
  scheduled start via host-time conversion, scheduled resume, group
  pause/stop.

## Consequences

- New messages must be added to both apps' `Models.swift` and both WebSocket
  layers; the protocol table in CLAUDE.md gains the sync section.
- The Vision Pro play pipeline gains a "prepare without autoplay" mode —
  today `onPlayerReady` starts playback immediately; sync sessions must
  suppress that and wait for `syncStart`.
- Drift correction is explicitly out of scope for v1.
