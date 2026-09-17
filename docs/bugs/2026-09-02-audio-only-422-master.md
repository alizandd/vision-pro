# Some headsets play audio only — the delivered file was a 4:2:2 mastering encode

- **Date**: 2026-09-02
- **Reported by**: client, field use
- **Severity**: Critical — the wearer hears the soundtrack over a black view
- **Task**: —
- **Branch**: — (no code change; content problem)
- **Status**: Root cause identified; converted file sent to the client for
  verification on the headsets

## Symptom

On some headsets, on some plays — reported as worse under "Play All" — the
video plays with sound but the picture never appears. Single plays on the
same headsets sometimes work.

## Root cause

The file in use was the vendor's mastering export, not a delivery encode:

```
16384 x 4096 @ 59.94 fps · HEVC profile "Rext" · yuv422p10le (4:2:2 10-bit)
161 Mbps average · HEVC level field = 255 (not a defined level)
```

The HEVC Range Extensions 4:2:2 profile is not supported by the M2 hardware
video decoder, so VideoToolbox falls back to software decoding. Measured on
an M2 Pro (same media-engine generation as the headset):

| encode | pixels/frame | VideoToolbox decode | vs 59.94 fps needed |
|---|---|---|---|
| vendor master, Rext 4:2:2 | 67 MP | 12 fps | 0.20x |
| same content, same size, Main 10 4:2:0 | 67 MP | 67 fps | 1.11x |
| 12288 x 3072, Main 10 4:2:0 | 38 MP | 111–114 fps | 1.85–1.91x |
| 8192 x 2048, Main 10 4:2:0 | 17 MP | 205 fps | 3.43x |

The pixel format, not the resolution, is the blocker: changing only the
chroma subsampling gave a 5.6x speed-up at the same size. AAC audio is
trivial to decode and keeps playing while the video decoder falls hopelessly
behind — hence sound without picture. It is intermittent because the device
sits at the edge of what it can manage, so the outcome depends on thermal
state and what ran before. The app's health-monitor fallback cannot help:
the legacy `VideoMaterial` path uses the same decoder.

The per-eye canvas is a full 360° equirect in which the imagery spans ~209°
(content occupies 24.4 %–82.6 % of each eye's width; the rest is black by
design). That matches the file's spherical metadata, so `sphere360sbs` is
the correct controller format for it.

## Resolution

- A delivery encode was produced with `hevc_videotoolbox`:
  12288 x 3072, Main 10, 4:2:0, `hvc1`, level 189, ~106 Mbps, audio copied
  as AAC. Framing verified identical to the master (same 24.4 %–82.6 %
  content span), so the operator's format selection does not change.
- The ffmpeg re-encode drops the `st3d`/`sv3d` side data. That is harmless
  here: `checkStereoMetadata` only looks for MV-HEVC extensions
  (`StereoInfo`, `MVHEVCConfiguration`, `CMStereoVideoMode`), the file never
  had them, and the flag only gates a log warning — the render path is
  chosen from the operator-selected format.
- A delivery spec was sent to the render vendor: full 360° equirect
  unchanged, 12288 x 3072 SBS, HEVC Main 10 4:2:0, valid level / High tier,
  59.94p, 100–150 Mbps, Rec.709 SDR, `hvc1`, AAC-LC stereo; 30-second test
  clip before the full render.

## Follow-ups

- The player logs the codec on load but not the profile or pixel format;
  a 4:2:2 / invalid-level file would have been flagged on day one if it did.
- Nothing tells the controller when frames stop arriving — it receives
  `playing` before a single frame is presented, and the legacy path has no
  picture-health detection at all. See the code-review notes in the
  changelog entry for 2026-09-02.
