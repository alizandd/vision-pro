# Vision Pro Remote Controller

A complete system for controlling immersive video playback on Apple Vision Pro devices via a web interface.

## Components

### 1. Vision Pro App (`VisionProPlayer/`)
A visionOS app that:
- Connects to a local WebSocket server
- Listens for playback commands
- Plays videos in full immersive mode
- Handles headset removal/reattachment gracefully

### 2. WebSocket Server (`server/`)
A Node.js WebSocket relay server that:
- Runs on your local network
- Relays commands between the web controller and Vision Pro devices
- Tracks connected devices and playback state
- **Serves video files from local storage** (`server/videos/` folder)
- Provides video library API for dynamic media loading

### 3. Web Controller (`web-controller/`)
A web application that:
- Provides a UI to control Vision Pro video playback
- Sends commands: play, pause, resume, change, stop
- Can control multiple Vision Pro devices simultaneously

## Quick Start

### ⚡ Fast Start (Recommended)

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

### 📝 Manual Start

### 1. Add Video Files (Optional)

Place your video files in the `server/videos/` directory:

```bash
cd server/videos
# Copy your video files here
cp ~/Downloads/my-video.mp4 .
```

Supported formats: MP4, MOV, M4V, AVI, MKV, WebM

### 2. Start the WebSocket Server

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

### 3. Open the Web Controller

Open `web-controller/index.html` in a browser, or serve it:

```bash
cd web-controller
npx serve .
```

Enter the server WebSocket URL (e.g., `ws://192.168.1.100:8080`) and click Connect.
The video library will load automatically from the server.

### 4. Deploy the Vision Pro App

1. Open `VisionProPlayer/VisionProPlayer.xcodeproj` in Xcode
2. Configure the WebSocket server URL in Settings
3. Build and deploy to your Vision Pro device

## Network Architecture

The system uses a **hub-and-spoke architecture** where all devices connect to a central server:

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

### Commands (Controller → Vision Pro)

```json
{
  "type": "command",
  "action": "play|pause|resume|change|stop",
  "videoUrl": "https://example.com/video.mp4",  // for play/change
  "targetDevices": ["device-id-1", "all"]       // optional, defaults to all
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

### Device Registration

```json
{
  "type": "register",
  "deviceId": "device-uuid",
  "deviceName": "My Vision Pro",
  "deviceType": "visionpro|controller"
}
```

## Configuration

### Server Configuration

Set environment variables or edit `server/config.js`:

- `PORT` - WebSocket server port (default: 8080)
- `HOST` - Server host (default: 0.0.0.0)

### Vision Pro App Configuration

Configure in the app's Settings:
- WebSocket Server URL (e.g., `ws://192.168.1.100:8080`)

## Development

### Prerequisites

- Node.js 18+ (for server)
- Xcode 15+ with visionOS SDK (for Vision Pro app)
- Modern web browser (for controller)

### Running in Development

```bash
# Terminal 1: Start server
cd server && npm run dev

# Terminal 2: Serve web controller
cd web-controller && npx serve .
```

## Troubleshooting

### Vision Pro won't connect
1. Ensure Vision Pro and server are on the same network
2. Check firewall settings on the server machine
3. Verify the WebSocket URL in the app settings

### Video won't play
1. Ensure the video URL is accessible from the Vision Pro
2. Check that the video format is supported (H.264, HEVC)
3. Verify CORS settings if hosting videos on a web server

### Connection drops
- The app automatically reconnects with exponential backoff
- Check network stability
- Monitor server logs for errors

## License

MIT License
