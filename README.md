# Vision Pro Remote Controller

A complete system for controlling immersive video playback on Apple Vision Pro devices. Supports both **iOS native controller** and **web-based controller** interfaces.

## Components

### 1. Vision Pro App (`VisionProPlayer/`)
A visionOS app that:
- Connects to WebSocket server (iOS Controller or Node.js server)
- Listens for playback commands
- Plays videos in full immersive mode (supports 2D, 3D SBS, 180° VR, 360° VR)
- Receives video files transferred from iOS Controller
- Manages local video library
- Handles headset removal/reattachment gracefully

### 2. iOS Controller App (`iOSController/`) ⭐ NEW
A native iOS/iPadOS app that:
- Acts as both WebSocket server AND HTTP file server
- Controls multiple Vision Pro devices simultaneously
- **Transfers videos from iOS Photos library to Vision Pro**
- Manages videos on each Vision Pro (view, delete)
- Shows real-time device status and connection info
- Works completely offline (no external server needed)

### 3. WebSocket Server (`server/`) - Optional
A Node.js WebSocket relay server that:
- Runs on your local network (laptop/desktop)
- Relays commands between the web controller and Vision Pro devices
- Tracks connected devices and playback state
- **Serves video files from local storage** (`server/videos/` folder)
- Provides video library API for dynamic media loading

### 4. Web Controller (`web-controller/`) - Optional
A web application that:
- Provides a UI to control Vision Pro video playback
- Sends commands: play, pause, resume, change, stop
- Can control multiple Vision Pro devices simultaneously
- Requires Node.js server to be running

## Quick Start

### Option A: iOS Controller (Recommended) ⭐

The easiest way to use the system - no computer/server required!

#### 1. Deploy the iOS Controller App

1. Open `iOSController/iOSController.xcodeproj` in Xcode
2. Build and deploy to your iPhone or iPad
3. Launch the app and tap **Start** to run the server

#### 2. Deploy the Vision Pro App

1. Open `VisionProPlayer/VisionProPlayer.xcodeproj` in Xcode
2. Build and deploy to your Vision Pro device
3. In Vision Pro Settings, enter the WebSocket URL shown on iOS Controller
   - Example: `ws://192.168.1.50:8080`
4. Vision Pro will connect automatically

#### 3. Control & Transfer Videos

- **View connected devices** on the iOS Controller main screen
- **Transfer videos**: Tap the upload icon (↑) to send videos from your Photos library to Vision Pro
- **Play videos**: Select a video from the device's local library and tap Play
- **Delete videos**: Tap the trash icon on any video thumbnail

---

### Option B: Web Controller (Alternative)

Use if you prefer browser-based control or need to run from a computer.

#### ⚡ Fast Start

**Mac/Linux:**
```bash
./start-all.sh
```

**Windows:**
```cmd
start-all.bat
```

This will automatically:
- **Check and install dependencies** (if needed - only first time)
- Start both WebSocket server and Web Controller
- Display all necessary addresses for mobile/tablet and Vision Pro
- Create logs for troubleshooting

See [STARTUP_SCRIPTS.md](STARTUP_SCRIPTS.md) for detailed instructions.

---

#### 📝 Manual Start

##### 1. Add Video Files (Optional)

Place your video files in the `server/videos/` directory:

```bash
cd server/videos
# Copy your video files here
cp ~/Downloads/my-video.mp4 .
```

Supported formats: MP4, MOV, M4V, AVI, MKV, WebM

##### 2. Start the WebSocket Server

```bash
cd server
npm install
./start.sh
```

Or use npm:
```bash
npm start
```

**Note:** The `start.sh` script is recommended as it handles PORT environment variable conflicts.

The server runs on port 8080 by default and will:
- Serve videos from `server/videos/` folder
- Display available videos on startup
- Provide video list API at `http://localhost:8080/api/videos`

##### 3. Open the Web Controller

Open `web-controller/index.html` in a browser, or serve it:

```bash
cd web-controller
npx serve .
```

Enter the server WebSocket URL (e.g., `ws://192.168.1.100:8080`) and click Connect.
The video library will load automatically from the server.

##### 4. Deploy the Vision Pro App

1. Open `VisionProPlayer/VisionProPlayer.xcodeproj` in Xcode
2. Configure the WebSocket server URL in Settings
3. Build and deploy to your Vision Pro device

## Network Architecture

### Architecture A: iOS Controller (Recommended)

The iOS Controller acts as both WebSocket server and HTTP file server:

```
┌─────────────────────────────────────────────────────────────┐
│                    Local Network (WiFi)                      │
│                                                               │
│  ┌──────────────────┐                                        │
│  │  iOS Controller  │        ┌─────────────────┐            │
│  │  (iPhone/iPad)   │◄───────┤  Vision Pro 1   │            │
│  │                  │  WS    │                 │            │
│  │  - WebSocket :8080│       └─────────────────┘            │
│  │  - HTTP     :8081│                                        │
│  │  - Photos Library│        ┌─────────────────┐            │
│  │                  │◄───────┤  Vision Pro 2   │            │
│  │  192.168.1.50    │  WS    │                 │            │
│  └──────────────────┘        └─────────────────┘            │
│                                                               │
│  Video Transfer: iOS Controller ──HTTP:8081──► Vision Pro    │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

**Key Points:**
- **iOS Controller is the server** - runs WebSocket (port 8080) + HTTP file server (port 8081)
- **Vision Pro devices connect to iOS Controller** for commands and file downloads
- **Videos transferred from iOS Photos library** directly to Vision Pro
- **No computer required** - works entirely on mobile devices
- **All devices must be on the same local network**

---

### Architecture B: Web Controller (Alternative)

Uses a Node.js server running on a computer:

```
┌─────────────────────────────────────────────────────────────┐
│                    Local Network (WiFi)                      │
│                                                               │
│  ┌──────────────────┐        ┌─────────────────┐            │
│  │  Server Device   │        │  Web Controller │            │
│  │  (Laptop/PC)     │◄───────┤  (Tablet/Mobile)│            │
│  │                  │  WS    │                 │            │
│  │  - WebSocket     │        └─────────────────┘            │
│  │  - Video Server  │                                        │
│  │  - Video Files   │        ┌─────────────────┐            │
│  │                  │◄───────┤  Vision Pro     │            │
│  │  192.168.1.100   │  WS    │                 │            │
│  │  Port: 8080      │        └─────────────────┘            │
│  └──────────────────┘                                        │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

**Key Points:**
- **Server runs on one device** (laptop/desktop) storing videos and handling WebSocket connections
- **Web controller runs on tablet/mobile** - connects to server via browser
- **Vision Pro devices** connect to same server for commands and video streaming
- **All devices must be on the same local network**

For detailed network setup instructions, see [NETWORK_SETUP.md](NETWORK_SETUP.md).

## Component Architecture

```
┌─────────────────┐         ┌──────────────────┐         ┌─────────────────┐
│  Web Controller │ ──────> │  WebSocket Server │ ──────> │  Vision Pro App │
│   (Browser)     │ <────── │   (Node.js)       │ <────── │   (visionOS)    │
└─────────────────┘         └──────────────────┘         └─────────────────┘
                                    │
                                    │
                            ┌───────┴───────┐
                            │               │
                      ┌─────▼─────┐   ┌─────▼─────┐
                      │ Vision Pro│   │ Vision Pro│
                      │  Device 2 │   │  Device N │
                      └───────────┘   └───────────┘
```

## WebSocket Protocol

### Device Registration

```json
{
  "type": "register",
  "deviceId": "device-uuid",
  "deviceName": "My Vision Pro",
  "deviceType": "visionpro|controller"
}
```

### Playback Commands (Controller → Vision Pro)

```json
{
  "type": "command",
  "action": "play|pause|resume|change|stop",
  "videoUrl": "https://example.com/video.mp4",
  "videoFormat": "mono2d|sbs3d|ou3d|hemisphere180|hemisphere180sbs|sphere360|sphere360ou",
  "targetDevices": ["device-id-1", "all"]
}
```

### Video Transfer Command (iOS Controller → Vision Pro)

```json
{
  "type": "command",
  "action": "download",
  "downloadUrl": "http://192.168.1.50:8081/download/file-id/video.mp4",
  "filename": "video.mp4",
  "fileSize": 104857600
}
```

### Delete Video Command (iOS Controller → Vision Pro)

```json
{
  "type": "command",
  "action": "deleteVideo",
  "videoId": "video-uuid",
  "filename": "video.mp4"
}
```

### Status Updates (Vision Pro → Controller)

```json
{
  "type": "status",
  "deviceId": "device-uuid",
  "deviceName": "My Vision Pro",
  "state": "idle|playing|paused|stopped",
  "currentVideo": "video-url-or-null",
  "immersiveMode": true|false
}
```

### Local Videos List (Vision Pro → Controller)

```json
{
  "type": "localVideos",
  "deviceId": "device-uuid",
  "videos": [
    {
      "id": "video-uuid",
      "name": "BigBuckBunny",
      "filename": "BigBuckBunny.mp4",
      "size": 158008374,
      "url": "file:///path/to/video.mp4"
    }
  ]
}
```

### Transfer Progress (Vision Pro → Controller)

```json
{
  "type": "transferProgress",
  "deviceId": "device-uuid",
  "filename": "video.mp4",
  "status": "started|downloading|completed|failed",
  "progress": 0.75,
  "bytesDownloaded": 78643200,
  "totalBytes": 104857600
}
```

## Configuration

### iOS Controller Configuration

- **WebSocket Server Port**: 8080 (fixed)
- **HTTP File Server Port**: 8081 (fixed)
- **Video Source**: iOS Photos Library

The iOS Controller automatically:
- Detects local IP address
- Starts both servers when you tap "Start"
- Shows connection URL for Vision Pro

### Node.js Server Configuration

Set environment variables or edit `server/config.js`:

- `PORT` - WebSocket server port (default: 8080)
- `HOST` - Server host (default: 0.0.0.0)

### Vision Pro App Configuration

Configure in the app's Settings:
- WebSocket Server URL (e.g., `ws://192.168.1.100:8080`)
- Device Name (customizable)
- Auto-connect on launch

## Video Formats

The Vision Pro app supports multiple video formats for immersive playback:

| Format | Description |
|--------|-------------|
| `mono2d` | Standard 2D flat video |
| `sbs3d` | Stereoscopic Side-by-Side 3D |
| `ou3d` | Stereoscopic Over-Under 3D |
| `hemisphere180` | 180° VR (equirectangular) |
| `hemisphere180sbs` | 180° VR Stereoscopic (recommended for VR content) |
| `sphere360` | 360° VR (full sphere) |
| `sphere360ou` | 360° VR Stereoscopic |

Select the appropriate format in the controller before playback for optimal viewing experience.

## Development

### Prerequisites

- Xcode 15+ with visionOS SDK and iOS SDK
- Node.js 18+ (only for web controller option)
- Modern web browser (only for web controller option)

### Project Structure

```
vision-pro/
├── VisionProPlayer/          # visionOS app
│   └── VisionProPlayer/
│       ├── Managers/         # WebSocket, Video, Download managers
│       ├── Models/           # Data models
│       └── Views/            # SwiftUI views
│
├── iOSController/            # iOS controller app
│   └── iOSController/
│       ├── WebSocketServer.swift
│       ├── FileTransferServer.swift
│       ├── DeviceManager.swift
│       └── Views/
│
├── server/                   # Node.js server (optional)
│   ├── server.js
│   └── videos/               # Video storage
│
└── web-controller/           # Web UI (optional)
    ├── index.html
    ├── controller.js
    └── styles.css
```

### Running in Development

**iOS Controller + Vision Pro:**
1. Run iOS Controller on iPhone/iPad from Xcode
2. Run Vision Pro app on device/simulator from Xcode
3. Enter iOS Controller's WebSocket URL in Vision Pro settings

**Web Controller (alternative):**
```bash
# Terminal 1: Start server
cd server && npm run dev

# Terminal 2: Serve web controller
cd web-controller && npx serve .
```

## Troubleshooting

### Vision Pro won't connect to iOS Controller
1. Ensure Vision Pro and iOS device are on the **same WiFi network**
2. Verify the WebSocket URL matches what's shown on iOS Controller
3. Make sure the server is started (green indicator on iOS Controller)
4. Try restarting the server on iOS Controller

### Video transfer fails
1. Check that both devices are on the same network
2. Verify the iOS Controller shows "Server Running" status
3. Make sure the video file is not corrupted
4. Check Vision Pro console for download errors
5. Large files (>1GB) may take longer - wait for completion

### Videos don't appear after transfer
1. Wait a few seconds for the video list to refresh
2. Pull down to refresh the video list on iOS Controller
3. Check Vision Pro's Documents/Videos folder

### Vision Pro won't connect (Web Controller)
1. Ensure Vision Pro and server are on the same network
2. Check firewall settings on the server machine
3. Verify the WebSocket URL in the app settings

### Video won't play
1. Ensure the video URL is accessible from the Vision Pro
2. Check that the video format is supported (H.264, HEVC)
3. Verify CORS settings if hosting videos on a web server
4. For VR content, ensure correct video format is selected

### Connection drops
- The app automatically reconnects with exponential backoff
- Check network stability
- Monitor server logs for errors

## License

MIT License
