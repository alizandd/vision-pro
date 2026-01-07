# CLAUDE.md - AI Assistant Guide for vision-pro

**Last Updated**: 2026-01-06
**Repository**: vision-pro
**Status**: Active Development

---

## Overview

Vision Pro Remote Controller - A complete system for controlling immersive video playback on Apple Vision Pro devices via a web interface. The system consists of three components that communicate over WebSocket.

### Repository Information
- **Repository Name**: vision-pro
- **Remote URL**: http://local_proxy@127.0.0.1:30432/git/alizandd/vision-pro
- **Current Branch**: claude/vision-pro-web-controller-scFsv

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
│       │   └── VideoPlayerManager.swift # Video playback control
│       ├── Models/
│       │   └── Models.swift            # Data models and protocols
│       └── Assets.xcassets/            # App assets
│
├── server/                             # WebSocket relay server (Node.js)
│   ├── server.js                       # Main server implementation
│   ├── config.js                       # Server configuration
│   └── package.json                    # Node.js dependencies
│
├── web-controller/                     # Web-based controller UI
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

### WebSocket Server
- **Runtime**: Node.js 18+
- **Dependencies**: ws (WebSocket library)
- **Port**: 8080 (configurable)

### Web Controller (Orchestrator UI)
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
