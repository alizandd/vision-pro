# ADR: Group seek reuses the scheduled resume rather than a scheduled seek

- **Date**: 2026-09-17
- **Status**: Accepted
- **Spec**: `docs/superpowers/specs/2026-09-17-playback-scrubber-design.md`

## Context

The controller gains a seek bar, for one headset and for a whole Play on All
session. A group seek must leave every headset at the same frame at the same
moment. The headset already supports `syncResume { mediaTime, startAt }`
(seek, preroll, start at a scheduled wall-clock tick) from the 2026-07-22
synchronised playback work.

## Options

1. **Scheduled `seek { mediaTime, startAt }`** — a new headset path that seeks
   and restarts on a tick. Clean on the wire; duplicates `scheduledResume` on
   the headset, the side that only gets verified on real devices.
2. **`syncPause` + `syncResume`** — the controller pauses the group and resumes
   it at the operator's time. No new headset code for the group case; the one
   new command (`seek`) is a plain single-headset jump.
3. **Seek only the preview** — does not control the headset. Rejected.

## Decision

Option 2. The headset gets exactly one new, unscheduled command. The group
path is a resume with a different number, already exercised by Resume All.

## Consequences

- A group seek while playing costs the same 1 s lead as a Resume All, during
  which the group bar is disabled.
- A group seek while paused is N individual `seek` commands; the controller
  updates its stored per-device position so the next Resume All uses the
  target.
- The headset's `seek` handler must not change playback state, so a paused
  headset stays paused on the new frame.

## Implementation note

The bar itself is not a SwiftUI `Slider`. On iPadOS 26 the slider's
`onEditingChanged(false)` did not reliably fire at the end of a drag, which
left the thumb stuck and no seek sent; and inside the page's ScrollView the
wide group bar lost horizontal drags to the scroll view. The track is drawn
by hand and driven by a high-priority `DragGesture`, whose `onEnded` is
dependable, and which lets the operator grab anywhere on the track.
