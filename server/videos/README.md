# Videos Directory

This directory stores video files that will be served to Vision Pro devices and displayed in the web controller.

## Adding Videos

1. **Copy video files to this directory:**
   ```bash
   cp /path/to/your/video.mp4 server/videos/
   ```

2. **Supported formats:**
   - MP4 (H.264, HEVC)
   - MOV
   - M4V
   - AVI
   - MKV
   - WebM

3. **After adding videos:**
   - Restart the server or refresh the web controller
   - Videos will appear automatically in the web controller's media library

## Best Practices

- Use descriptive file names (e.g., `nature-documentary.mp4`)
- Avoid special characters in filenames
- Keep file sizes reasonable for network streaming
- Test videos play correctly before adding to library

## Example

```bash
server/videos/
├── demo-video.mp4
├── product-showcase.mov
└── training-material.mp4
```

Each video will appear in the web controller with its filename (without extension) as the display name.




