# Network Architecture & Setup Guide

## Overview

This document explains how to set up the Vision Pro system across multiple devices on the same network.

## Network Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Local Network (WiFi)                      │
│                                                               │
│  ┌──────────────────┐        ┌─────────────────┐            │
│  │  Server Device   │        │  Web Controller │            │
│  │  (Laptop/PC)     │◄───────┤  (Tablet/Mobile)│            │
│  │                  │  WS    │                 │            │
│  │  - WebSocket     │        └─────────────────┘            │
│  │  - HTTP Server   │                                        │
│  │  - Video Files   │        ┌─────────────────┐            │
│  │                  │◄───────┤  Vision Pro     │            │
│  │  192.168.1.100   │  WS    │                 │            │
│  │  Port: 8080      │        └─────────────────┘            │
│  └──────────────────┘                                        │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

## Device Roles

### 1. Server Device (Laptop/Computer)
- **Runs:** WebSocket relay server + HTTP file server
- **Stores:** Video files in `server/videos/` folder
- **IP Example:** 192.168.1.100
- **Port:** 8080 (default)
- **Functions:**
  - Relays commands between controllers and Vision Pro devices
  - Serves video files via HTTP
  - Provides video list API

### 2. Web Controller (Tablet/Mobile/Computer)
- **Runs:** Web browser with controller interface
- **Connects to:** Server WebSocket at `ws://SERVER_IP:8080`
- **Functions:**
  - Send playback commands
  - View device status
  - Select videos from server library

### 3. Vision Pro Device
- **Runs:** visionOS app
- **Connects to:** Server WebSocket at `ws://SERVER_IP:8080`
- **Functions:**
  - Receives playback commands
  - Plays videos in immersive mode
  - Sends status updates

## Setup Instructions

### Step 1: Prepare Server Device

1. **Find Server IP Address:**
   ```bash
   # On macOS/Linux:
   ifconfig | grep "inet "
   
   # On Windows:
   ipconfig
   ```
   
   Look for your local network IP (usually starts with 192.168.x.x or 10.x.x.x)
   Example: `192.168.1.100`

2. **Create Videos Folder:**
   ```bash
   cd server
   mkdir -p videos
   ```

3. **Add Video Files:**
   Place your video files (MP4, MOV) in `server/videos/` folder:
   ```
   server/videos/
   ├── sample1.mp4
   ├── sample2.mp4
   └── demo-video.mov
   ```

4. **Start Server:**
   ```bash
   cd server
   npm install
   npm start
   ```
   
   You should see:
   ```
   [Server] WebSocket server running on ws://0.0.0.0:8080
   [Server] Video server running on http://0.0.0.0:8080
   ```

### Step 2: Connect Web Controller

1. **Open Web Controller:**
   - On tablet/mobile: Open `web-controller/index.html` in browser
   - Or serve it: `cd web-controller && npx serve .`

2. **Enter Server URL:**
   ```
   ws://192.168.1.100:8080
   ```
   Replace `192.168.1.100` with your server's IP address

3. **Click Connect**

4. **Verify Connection:**
   - Status should show "Connected"
   - Video library should load automatically from server

### Step 3: Connect Vision Pro

1. **Open Settings in Vision Pro App**

2. **Enter WebSocket Server URL:**
   ```
   ws://192.168.1.100:8080
   ```
   Replace with your server's IP address

3. **Save and Connect**

4. **Verify:**
   - Web controller should show Vision Pro device in devices list

## Video Management

### Supported Formats
- MP4 (H.264, HEVC)
- MOV
- M4V

### Adding Videos
1. Copy video files to `server/videos/` folder
2. Restart server (or wait for auto-refresh if implemented)
3. Videos will appear in web controller library

### Video URLs
Videos are served at: `http://SERVER_IP:8080/videos/FILENAME`

Example: `http://192.168.1.100:8080/videos/sample1.mp4`

## Troubleshooting

### Web Controller Won't Connect
- ✓ Verify server is running
- ✓ Check IP address is correct
- ✓ Use `ws://` not `wss://` for local network
- ✓ Ensure all devices on same WiFi network
- ✓ Check firewall allows port 8080

### Vision Pro Won't Connect
- ✓ Check WebSocket URL in app settings
- ✓ Verify Vision Pro and server on same network
- ✓ Check server logs for connection attempts
- ✓ Try restarting the app

### Videos Won't Load
- ✓ Verify video files are in `server/videos/` folder
- ✓ Check video format is supported
- ✓ Test video URL directly: `http://SERVER_IP:8080/videos/video.mp4`
- ✓ Check file permissions

### Firewall Issues
If devices can't connect:

**macOS:**
```bash
# Allow port 8080
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add node
```

**Windows:**
- Windows Defender Firewall → Allow an app → Allow port 8080

**Linux:**
```bash
sudo ufw allow 8080
```

## Network Requirements

- **All devices must be on the same local network**
- **Port 8080 must be accessible** (configurable in `server/config.js`)
- **WiFi recommended** for stable connection
- **Low latency network** for smooth playback

## Advanced Configuration

### Change Server Port

Edit `server/config.js`:
```javascript
module.exports = {
    port: 9000,  // Change to desired port
    host: '0.0.0.0'
};
```

### Multiple Networks

If server has multiple network interfaces, bind to specific IP:
```javascript
module.exports = {
    host: '192.168.1.100'  // Specific interface
};
```

## Security Notes

- This setup is for **local network use only**
- No authentication is implemented
- Do not expose to public internet without proper security
- For production use, add HTTPS/WSS and authentication

---

**Need Help?**
Check server logs for detailed connection information and errors.

