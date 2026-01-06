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

### 3. Web Controller (`web-controller/`)
A web application that:
- Provides a UI to control Vision Pro video playback
- Sends commands: play, pause, resume, change, stop
- Can control multiple Vision Pro devices simultaneously

## Quick Start

### 1. Start the WebSocket Server

```bash
cd server
npm install
npm start
```

The server runs on port 8080 by default.

### 2. Open the Web Controller

Open `web-controller/index.html` in a browser, or serve it:

```bash
cd web-controller
npx serve .
```

### 3. Deploy the Vision Pro App

1. Open `VisionProPlayer/VisionProPlayer.xcodeproj` in Xcode
2. Configure the WebSocket server URL in Settings
3. Build and deploy to your Vision Pro device

## Architecture

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
