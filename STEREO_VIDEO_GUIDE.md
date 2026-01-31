# Stereo 180° Video Playback Guide for Vision Pro

## Understanding the Challenge

When playing Stereo 180° Side-by-Side (SBS) videos in a custom visionOS app, there are specific requirements that differ from playing the same video in the native Vision Pro player.

### Why the Native Player Works

The native Vision Pro video player:
1. Reads spatial/stereo metadata from the video file
2. Automatically detects SBS/OU layout from metadata
3. Uses Apple's internal rendering pipeline for per-eye stereo separation
4. Has access to APIs not available to third-party apps

### The Challenge with Custom Apps

RealityKit's `VideoMaterial`:
- Renders the video as a single texture
- Applies the **same** frame to **both** eyes
- Does NOT support per-eye UV offset or stereo separation
- This means both eyes see the same image, breaking 3D depth

## Solutions

### Solution 1: Add Spatial Metadata to Your Video (Recommended)

The most reliable solution is to add proper spatial metadata tags to your video file. This tells visionOS exactly how to interpret and render the stereo content.

#### Using Spatial Media Metadata Injector (Free Tool)

1. Download [Spatial Media Metadata Injector](https://github.com/google/spatial-media/releases) by Google
2. Run the tool:
   ```bash
   python spatialmedia -i --stereo=left-right input.mp4 output.mp4
   ```
3. For 180° SBS content, use these settings:
   - Stereo mode: `left-right` (side-by-side)
   - This embeds the metadata needed for proper stereo rendering

#### Using FFmpeg with Metadata

```bash
ffmpeg -i input.mp4 -c copy \
  -metadata:s:v:0 stereo_mode=1 \
  -metadata:s:v:0 spherical=equirectangular \
  -metadata:s:v:0 spherical_bounds="0/90/90/90" \
  output.mp4
```

#### Using MP4Box

```bash
mp4box -add input.mp4#video:name=left:stereo_layer_id=0 \
       -add input.mp4#video:name=right:stereo_layer_id=1 \
       -stereo sbs \
       output.mp4
```

### Solution 2: Convert to MV-HEVC (Best Quality)

Apple's Multi-View HEVC (MV-HEVC) codec is the ideal format for stereoscopic video on Vision Pro:

1. **Pros**: Native support, optimal quality, proper stereo rendering
2. **Cons**: Requires video re-encoding, increases file size

#### Using Apple Compressor
1. Import your video into Compressor
2. Select "Spatial Video" preset
3. Configure source as "Side-by-Side Stereo"
4. Export as MV-HEVC

#### Using HandBrake (with proper settings)
1. Source: Your SBS video
2. Video Codec: HEVC
3. Add spatial metadata after encoding

### Solution 3: Use Deep Link to Native Player

If metadata tagging doesn't work, you can open the video in the native player:

```swift
// Open video in native Vision Pro player
if let url = URL(string: "visionos-video://path/to/video.mp4") {
    await UIApplication.shared.open(url)
}
```

Note: This exits your app and opens the system player.

## Video File Requirements

For optimal playback in the custom app, your video should have:

### Required Metadata Tags
- `stereo3d`: Indicates stereoscopic content
- `stereo_mode`: `side_by_side_left_first` or `1`
- `projection`: `equirectangular`
- `spherical_bounds`: For 180° content

### Recommended Video Specs
| Property | Value |
|----------|-------|
| Resolution | 5760x2880 or higher (per-eye: 2880x2880) |
| Codec | H.265/HEVC or MV-HEVC |
| Frame Rate | 30fps or 60fps |
| Bit Rate | 50-100 Mbps for high quality |
| Container | MP4 or MOV |

## Verifying Video Metadata

Check if your video has spatial metadata:

```bash
# Using FFprobe
ffprobe -v quiet -print_format json -show_streams video.mp4 | grep -E "stereo|spherical"

# Using MediaInfo
mediainfo --Full video.mp4 | grep -E "Stereo|Spherical|3D"
```

## Troubleshooting

### Video Plays But No 3D Effect
- **Cause**: Missing stereo metadata
- **Fix**: Add metadata using tools above

### One Eye Sees Wrong Image
- **Cause**: Incorrect stereo mode (left-right vs right-left)
- **Fix**: Check video source layout and adjust metadata

### Content Appears Behind Viewer
- **Cause**: Incorrect projection type or bounds
- **Fix**: Ensure `spherical_bounds` is set for 180° content

### App Crashes on Large Files
- **Cause**: Memory pressure from video initialization
- **Fix**: The updated app code now:
  1. Opens immersive space first
  2. Waits for space to be ready (1.5+ seconds)
  3. Then initializes video with optimized buffering

## Technical Details

### How Stereo 180° SBS Works

```
┌─────────────────────────────────────────┐
│         Video Frame Layout              │
├───────────────────┬─────────────────────┤
│                   │                     │
│    LEFT EYE       │     RIGHT EYE       │
│    (0.0-0.5)      │     (0.5-1.0)       │
│                   │                     │
└───────────────────┴─────────────────────┘
       ↓                    ↓
   Left Display        Right Display
```

### Hemisphere Projection

For 180° equirectangular content:
- Horizontal FOV: 180° (−90° to +90°)
- Vertical FOV: 180° (−90° to +90°)
- The viewer is positioned at the center of a hemisphere
- Only content in front of the viewer is visible

### Memory Considerations for 20GB Files

The app now uses:
- Streaming from disk (no full file load)
- 30-second forward buffer (configurable)
- Deferred video initialization
- Proper lifecycle to prevent memory pressure

## App Code Changes Summary

The updated app includes:

1. **Proper Playback Lifecycle**
   - Open immersive space FIRST
   - Wait 1.5+ seconds for rendering context
   - THEN initialize video player
   - Start playback when both are ready

2. **Optimized Asset Loading**
   - `AVURLAsset` with streaming options
   - Smaller buffer sizes to reduce memory
   - No precise duration requirement (faster load)

3. **Correct Hemisphere Geometry**
   - Front-facing hemisphere (180° FOV)
   - Proper UV mapping for equirectangular projection
   - Correct normals for inside-out rendering

4. **Stereo UV Mapping (Left Eye)**
   - For SBS content, UV is mapped to left half (0.0-0.5)
   - System handles stereo separation IF video has metadata

## Next Steps

1. **First**: Add spatial metadata to your video file using the tools above
2. **Test**: Try the video in the native Vision Pro player to confirm metadata
3. **Deploy**: Install the updated app and test playback
4. **Verify**: Both eyes should now see correct stereo separation

If issues persist after adding metadata, consider converting to MV-HEVC format for the most reliable stereo playback on Vision Pro.
