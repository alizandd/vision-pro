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

### Web Controller
- **Technologies**: HTML5, CSS3, JavaScript (ES6+)
- **No build step required** - runs directly in browser

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
- **Change UI**: Modify ContentView.swift or SettingsView.swift
- **Modify video playback**: Update VideoPlayerManager.swift and ImmersiveView.swift

---

## Quick Reference

### Essential Commands
```bash
# Start server
cd server && npm start

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
```

---

## Changelog

### 2026-01-06
- Initial project implementation
- Created Vision Pro app with WebSocket client
- Created Node.js WebSocket relay server
- Created web-based controller UI
- Implemented full immersive video playback
- Added reconnection logic with exponential backoff

---

**Remember**: This is a living document. Update it as the project evolves.
