# CLAUDE.md - AI Assistant Guide for vision-pro

**Last Updated**: 2026-02-05
**Repository**: vision-pro
**Status**: Active Development

---

## Overview

Vision Pro Remote Controller - A complete system for controlling immersive video playback on Apple Vision Pro devices. Supports both **iOS native controller** and **web-based controller** interfaces. The system communicates over WebSocket with HTTP file transfer support.

### Repository Information
- **Repository Name**: vision-pro
- **Remote URL**: http://local_proxy@127.0.0.1:30432/git/alizandd/vision-pro
- **Current Branch**: feature/ios-controller-app

---

## Project Structure

```
vision-pro/
├── VisionProPlayer/                    # visionOS app (Swift/SwiftUI/RealityKit)
│   └── VisionProPlayer/
│       ├── VisionProPlayerApp.swift    # App entry point
│       ├── ContentView.swift           # Main UI view
│       ├── ImmersiveView.swift         # Full immersive video playback
│       ├── SettingsView.swift          # Configuration UI
│       ├── Managers/
│       │   ├── AppState.swift          # Central state management
│       │   ├── WebSocketManager.swift  # WebSocket connection handling
│       │   ├── VideoPlayerManager.swift # Video playback control
│       │   ├── LocalVideoManager.swift  # Local video file management
│       │   └── DownloadManager.swift    # Video download from iOS Controller
│       ├── Models/
│       │   └── Models.swift            # Data models and protocols
│       └── Assets.xcassets/            # App assets
│
├── iOSController/                      # iOS Controller app (Swift/SwiftUI) ⭐ NEW
│   └── iOSController/
│       ├── iOSControllerApp.swift      # App entry point
│       ├── ContentView.swift           # Main UI view
│       ├── DeviceCardView.swift        # Device display card
│       ├── VideoTransferView.swift     # Video transfer UI
│       ├── WebSocketServer.swift       # WebSocket server implementation
│       ├── FileTransferServer.swift    # HTTP file server for transfers
│       ├── DeviceManager.swift         # Device & connection management
│       └── Models.swift                # Data models
│
├── server/                             # WebSocket relay server (Node.js) - Optional
│   ├── server.js                       # Main server implementation
│   ├── config.js                       # Server configuration
│   └── package.json                    # Node.js dependencies
│
├── web-controller/                     # Web-based controller UI - Optional
│   ├── index.html                      # Main HTML page
│   ├── styles.css                      # Styling
│   └── controller.js                   # Controller logic
│
├── README.md                           # Project documentation
└── CLAUDE.md                           # This file
```

---

## Technology Stack

### Vision Pro App
- **Language**: Swift 5
- **Frameworks**: SwiftUI, RealityKit, AVFoundation
- **Platform**: visionOS 1.0+
- **IDE**: Xcode 15+
- **Features**:
  - WebSocket client for receiving commands
  - Video download manager for file transfers
  - Local video library management
  - Multiple video format support (2D, 3D, VR)

### iOS Controller App ⭐ NEW
- **Language**: Swift 5
- **Frameworks**: SwiftUI, Network (NWListener), PhotosUI
- **Platform**: iOS 17.0+ / iPadOS 17.0+
- **IDE**: Xcode 15+
- **Ports**: WebSocket 8080, HTTP 8081
- **Features**:
  - WebSocket server (NWListener-based)
  - HTTP file server for video transfers
  - Photos library integration (PhotosPicker)
  - Multi-device management
  - Real-time status monitoring
  - Video transfer with progress tracking
  - Remote video deletion

### WebSocket Server (Optional)
- **Runtime**: Node.js 18+
- **Dependencies**: ws (WebSocket library)
- **Port**: 8080 (configurable)

### Web Controller (Optional)
- **Technologies**: HTML5, CSS3, JavaScript (ES6+)
- **Fonts**: Outfit (UI), JetBrains Mono (code)
- **No build step required** - runs directly in browser
- **Responsive**: Fully supports desktop, tablet, and mobile views
- **Features**:
  - Per-device video preview with LIVE badge
  - **Video sync**: When Vision Pro plays/pauses, web preview syncs automatically
  - Media library sidebar with preset videos
  - Individual device controls
  - Expandable full-size preview panel
  - Mobile: Hamburger menu with slide-out sidebar
  - Tablet: Optimized layout with larger video preview

---

## Development Workflow

### Running the System

1. **Start the WebSocket Server**:
```bash
cd server
npm install
npm start
```

2. **Open the Web Controller**:
```bash
# Option 1: Open directly
open web-controller/index.html

# Option 2: Serve with a local server
cd web-controller && npx serve .
```

3. **Deploy the Vision Pro App**:
- Open `VisionProPlayer/VisionProPlayer.xcodeproj` in Xcode
- Configure signing & capabilities
- Build and deploy to Vision Pro device

### Branch Strategy
- Feature branches must start with `claude/`
- Current working branch: `claude/vision-pro-web-controller-scFsv`
- Push to remote using: `git push -u origin <branch-name>`

### Commit Message Convention
- Use imperative mood ("Add feature" not "Added feature")
- First line: brief summary (50 chars or less)
- Reference specific components: `[server]`, `[app]`, `[web]`

---

## WebSocket Protocol

### Message Types

**Registration (Device → Server)**:
```json
{
  "type": "register",
  "deviceId": "uuid",
  "deviceName": "My Vision Pro",
  "deviceType": "visionpro|controller"
}
```

**Commands (Controller → Device)**:
```json
{
  "type": "command",
  "action": "play|pause|resume|change|stop",
  "videoUrl": "https://example.com/video.mp4",
  "targetDevices": ["device-id", "all"]
}
```

**Status Updates (Device → Controller)**:
```json
{
  "type": "status",
  "deviceId": "uuid",
  "deviceName": "My Vision Pro",
  "state": "idle|playing|paused|stopped",
  "currentVideo": "url",
  "immersiveMode": true
}
```

---

## Code Conventions

### Swift (Vision Pro App)
- Use `@MainActor` for UI-related classes
- Use `@Published` for observable state
- Follow Apple's Swift API Design Guidelines
- Use `async/await` for asynchronous operations

### JavaScript (Web Controller)
- ES6+ class-based structure
- Camel case for variables and functions
- Escape all user input before DOM insertion
- Use WebSocket with automatic reconnection

### Node.js (Server)
- CommonJS modules (`require`)
- Error handling with try/catch
- Graceful shutdown handling

---

## Key Components

### VisionProPlayerApp.swift
- Main app entry point
- Manages scene lifecycle
- Handles immersive space opening/closing
- Routes commands from WebSocket to video player

### WebSocketManager.swift
- Handles WebSocket connection with exponential backoff reconnection
- Parses incoming JSON commands
- Sends status updates to server
- Supports configurable server URL

### VideoPlayerManager.swift
- AVPlayer-based video playback
- Creates VideoMaterial for RealityKit
- Manages playback state (play, pause, resume, stop)
- Reports state changes via callback

### ImmersiveView.swift
- RealityKit-based immersive experience
- Renders video on a plane in 3D space
- Positioned 3 meters in front of user

### LocalVideoManager.swift
- Scans Documents/Videos folder for local videos
- Provides video metadata (name, size, modified date)
- Supports video deletion

### DownloadManager.swift
- URLSession-based download manager
- Progress tracking with delegate callbacks
- Handles large file downloads with temp file management
- Moves completed downloads to Videos folder

---

## iOS Controller Key Components

### WebSocketServer.swift
- NWListener-based WebSocket server
- Handles client connections and message routing
- Device registration and status management
- Heartbeat mechanism for connection health

### FileTransferServer.swift
- NWListener-based HTTP server on port 8081
- Serves video files for transfer
- Range request support for resumable downloads
- Chunked streaming for efficient memory usage

### DeviceManager.swift
- Central coordinator for iOS Controller
- Manages WebSocket and HTTP servers
- Tracks connected Vision Pro devices
- Handles video transfer commands
- Activity logging

### DeviceCardView.swift
- SwiftUI view for device display
- Video thumbnail grid
- Playback controls
- Video format selector
- Delete confirmation dialog

---

## Configuration

### Server Configuration (server/config.js)
- `PORT`: WebSocket server port (default: 8080)
- `HOST`: Server host (default: 0.0.0.0)

### Vision Pro App Settings
- WebSocket Server URL (stored in UserDefaults)
- Device Name (customizable)
- Auto-connect on launch

---

## Troubleshooting

### Vision Pro won't connect
1. Verify Vision Pro and server are on same network
2. Check server URL in app settings (e.g., `ws://192.168.1.100:8080`)
3. Check firewall allows port 8080

### Video won't play
1. Verify video URL is accessible
2. Check video format (H.264, HEVC supported)
3. CORS must allow access from Vision Pro

### WebSocket disconnects
- App implements automatic reconnection with exponential backoff
- Server implements heartbeat ping/pong
- Check network stability

---

## AI Assistant Guidelines

### Important Files to Know
- `VisionProPlayer/VisionProPlayer/Managers/` - Core logic
- `VisionProPlayer/VisionProPlayer/Managers/DownloadManager.swift` - Video download from iOS Controller
- `iOSController/iOSController/FileTransferServer.swift` - HTTP server for video files
- `iOSController/iOSController/VideoTransferView.swift` - Video transfer UI
- `server/server.js` - WebSocket relay implementation
- `web-controller/controller.js` - Controller logic

### When Making Changes
1. Read existing implementation first
2. Follow established patterns
3. Test WebSocket communication end-to-end
4. Verify immersive space behavior

### Common Tasks
- **Add new command**: Update Models.swift, WebSocketManager, VideoPlayerManager, and server.js
- **Change Vision Pro UI**: Modify ContentView.swift or SettingsView.swift
- **Modify video playback**: Update VideoPlayerManager.swift and ImmersiveView.swift
- **Update Web Controller UI**: Modify web-controller/styles.css and controller.js

### Web Controller UI Structure
The web controller uses a modern dark theme with:
- **Sidebar**: Server connection, media library, quick actions
- **Main Content**: Device grid with cards showing status and preview
- **Device Card**: Name, status badges (PLAYING/PAUSED/IMMERSIVE), media selector, controls, video thumbnail
- **Preview Panel**: Full-size video preview when device is selected
- **Activity Log**: Collapsible log panel at the bottom

---

## Quick Reference

### Essential Commands
```bash
# Start server (recommended - handles PORT conflicts)
cd server && ./start.sh

# Or use npm
cd server && npm start

# Add videos to server
cp ~/Downloads/my-video.mp4 server/videos/

# Test video API
curl http://localhost:8080/api/videos

# Serve web controller
cd web-controller && npx serve .

# Git operations
git status
git add .
git commit -m "Message"
git push -u origin claude/vision-pro-web-controller-scFsv
```

### Server Health Check
```bash
curl http://localhost:8080/health
curl http://localhost:8080/devices
curl http://localhost:8080/api/videos
```

---

## Changelog

### 2026-02-05
- **[iOS Controller App]** Complete native iOS/iPadOS app for Vision Pro control
  - **New Project**: `iOSController/` - Full SwiftUI app
  - **WebSocket Server** (`WebSocketServer.swift`):
    - NWListener-based WebSocket server on port 8080
    - Device registration and status tracking
    - Command routing to Vision Pro devices
    - Heartbeat/ping-pong for connection health
  - **HTTP File Server** (`FileTransferServer.swift`):
    - NWListener-based HTTP server on port 8081
    - Serves videos for transfer with range request support
    - Chunked streaming for large files
    - MIME type detection
  - **Device Management** (`DeviceManager.swift`):
    - Central manager for all connected devices
    - Real-time status updates
    - Video transfer coordination
    - Activity logging
  - **UI Components**:
    - `ContentView.swift` - Main view with server status and device list
    - `DeviceCardView.swift` - Per-device card with video library and controls
    - `VideoTransferView.swift` - PhotosPicker UI for video selection
    - Connection URL display with copy button
  - **Features**:
    - Start/stop server with one tap
    - View all connected Vision Pro devices
    - See local videos on each device
    - Play/pause/stop controls per device
    - Video format selection (2D, 3D, VR)
- **[Video Transfer from iOS to Vision Pro]** Wireless video transfer
  - Select videos from iOS Photos library (PhotosPicker)
  - Choose target Vision Pro device
  - HTTP streaming transfer over WiFi
  - Progress tracking with real-time updates
  - Videos save to Vision Pro's Documents/Videos folder
  - Automatic video list refresh after download
  - `DownloadManager.swift` on Vision Pro handles downloads
- **[Delete Videos Remotely]** Remove videos from Vision Pro via iOS Controller
  - Trash icon on each video thumbnail
  - Confirmation dialog before deletion
  - `deleteVideo` command sent to Vision Pro
  - Automatic video list refresh after deletion
- **[UI Improvements]**
  - Video thumbnail grid with aligned layout
  - Fixed-height video info for consistent alignment
  - Truncated filenames with middle ellipsis
  - Selection border properly visible (padding fix)
  - Removed sample videos feature (no longer needed)
- **[Protocol Update]** New WebSocket message types
  - `download` - Transfer video from controller to Vision Pro
  - `deleteVideo` - Remove video from Vision Pro
  - `localVideos` - Vision Pro sends its video library to controller
  - `transferProgress` - Real-time transfer progress updates
  - `deleteVideoResponse` - Confirmation of video deletion

### 2026-01-31
- **[Critical Stereo 180° SBS Fixes]** Major rewrite to fix stereoscopic video playback
  - **Playback Lifecycle Overhaul** - Fixed crashes on large (~20GB) videos:
    1. Open immersive space FIRST
    2. Wait for immersive space to be fully ready (1.5+ seconds)
    3. THEN initialize video player (prevents memory pressure)
    4. Start playback only when both are ready
  - **Memory-Safe Video Loading** - Optimized for large immersive files:
    - `AVURLAsset` with streaming options (no full file load)
    - 30-second forward buffer (configurable)
    - Deferred video initialization
    - Proper cleanup of all observers
  - **Improved Hemisphere Geometry** - Correct 180° FOV rendering:
    - Front-facing hemisphere only (no content behind viewer)
    - Proper equirectangular UV mapping
    - 128 segments for smooth curvature
    - 10m radius for immersive scale
  - **New Views/ImmersiveVideoPlayer.swift** - AVPlayerViewController wrapper
    - For future use with system player integration
    - Includes stereo metadata detection
  - **New STEREO_VIDEO_GUIDE.md** - Comprehensive documentation:
    - Explains why native player works but custom app doesn't
    - Instructions for adding spatial metadata to videos
    - MV-HEVC conversion guidance
    - Troubleshooting steps
  - **Important Limitation**: RealityKit's `VideoMaterial` doesn't support per-eye
    stereoscopic rendering. Videos MUST have spatial metadata for stereo to work.
    See STEREO_VIDEO_GUIDE.md for solutions.

### 2026-01-08
- **[Stereoscopic & Immersive Video Support]** Full support for VR and 3D video formats
  - New `VideoFormat` enum with 7 format types:
    - `mono2d` - Standard 2D flat video
    - `sbs3d` - Stereoscopic Side-by-Side 3D
    - `ou3d` - Stereoscopic Over-Under 3D
    - `hemisphere180` - 180° VR (equirectangular)
    - `hemisphere180sbs` - 180° VR Stereoscopic
    - `sphere360` - 360° VR (full sphere)
    - `sphere360ou` - 360° VR Stereoscopic
  - Hemisphere mesh generation for 180° content
  - Format-aware entity creation in `VideoPlayerManager`
  - Dynamic screen positioning (flat screen vs immersive dome)
- **[Web Controller Format Selector]** Per-device video format selection
  - Dropdown to select video format before playback
  - Default format set to `hemisphere180sbs` for VR content
  - Format sent with play/change commands
- **[Protocol Update]** WebSocket command now includes `videoFormat` field
  - Backwards compatible - defaults to `mono2d` if not specified

### 2026-01-07
- **[Local Video Storage]** Server now serves videos from local folder
  - Videos stored in `server/videos/` directory
  - Server scans folder and serves video list via `/api/videos`
  - HTTP video streaming with range request support
  - Supports MP4, MOV, M4V, AVI, MKV, WebM formats
- **[Dynamic Media Library]** Web controller fetches videos from server
  - Automatic video library loading on connection
  - Shows video name, format, and file size
  - Click to select videos for playback
  - No more hardcoded video URLs
- **[Network Architecture]** Clear hub-and-spoke setup
  - Server device stores videos and handles WebSocket/HTTP
  - Web controller connects from tablet/mobile browser
  - Vision Pro devices connect to same server
  - Comprehensive network setup guide in NETWORK_SETUP.md
- **[Server Startup Scripts]** Added startup scripts for easy launch
  - `start-all.sh` / `start-all.bat` - Start all servers (Mac/Windows)
  - `stop-all.sh` / `stop-all.bat` - Stop all servers (Mac/Windows)
  - Automatic IP detection and display
  - Auto-install dependencies if needed
  - Handles PORT environment variable conflicts
  - Shows all necessary URLs for mobile and Vision Pro

### 2026-01-06
- Initial project implementation
- Created Vision Pro app with WebSocket client
- Created Node.js WebSocket relay server
- Created web-based controller UI
- Implemented full immersive video playback
- Added reconnection logic with exponential backoff
- **[UI Redesign]** Modern Orchestrator-style web interface
  - Per-device video preview with LIVE indicator
  - Expandable full-size preview panel
  - Media library sidebar with preset videos
  - Individual device playback controls
  - Status badges (Playing, Paused, Immersive)
  - Custom video URL support
  - Activity log panel
- **[Responsive]** Tablet and mobile support
  - Hamburger menu with slide-out sidebar on mobile
  - Adaptive layouts for all screen sizes
  - Touch-friendly controls
- **[Video Sync]** Web preview syncs with Vision Pro
  - Automatic play/pause/stop synchronization
  - LIVE badge shows when video is actively playing

---

**Remember**: This is a living document. Update it as the project evolves.
