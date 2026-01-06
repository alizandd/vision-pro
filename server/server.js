/**
 * Vision Pro WebSocket Relay Server
 *
 * This server relays commands between web controllers and Vision Pro devices.
 * It maintains a registry of connected devices and their states.
 */

const WebSocket = require('ws');
const http = require('http');
const fs = require('fs');
const path = require('path');
const url = require('url');
const config = require('./config');

// Device registry
const devices = new Map();      // deviceId -> { ws, info, state }
const controllers = new Set();  // Set of controller WebSocket connections

// Video storage directory
const VIDEOS_DIR = path.join(__dirname, 'videos');

// Ensure videos directory exists
if (!fs.existsSync(VIDEOS_DIR)) {
    fs.mkdirSync(VIDEOS_DIR, { recursive: true });
    console.log(`[Server] Created videos directory: ${VIDEOS_DIR}`);
}

// Create HTTP server for API, video serving, and health checks
const httpServer = http.createServer((req, res) => {
    const parsedUrl = url.parse(req.url, true);
    const pathname = parsedUrl.pathname;

    // Enable CORS for web controller access
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

    if (req.method === 'OPTIONS') {
        res.writeHead(200);
        res.end();
        return;
    }

    if (pathname === '/health') {
        // Health check endpoint
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({
            status: 'healthy',
            connectedDevices: devices.size,
            connectedControllers: controllers.size,
            uptime: process.uptime()
        }));
    } else if (pathname === '/devices') {
        // Device list endpoint
        res.writeHead(200, { 'Content-Type': 'application/json' });
        const deviceList = Array.from(devices.entries()).map(([id, data]) => ({
            deviceId: id,
            deviceName: data.info.deviceName,
            state: data.state
        }));
        res.end(JSON.stringify(deviceList));
    } else if (pathname === '/api/videos') {
        // List available videos
        handleVideoListRequest(req, res);
    } else if (pathname.startsWith('/videos/')) {
        // Serve video files
        handleVideoFileRequest(req, res, pathname);
    } else {
        res.writeHead(404, { 'Content-Type': 'text/plain' });
        res.end('Not Found');
    }
});

/**
 * Handle video list API request
 * Returns JSON array of available videos with metadata
 */
function handleVideoListRequest(req, res) {
    try {
        const files = fs.readdirSync(VIDEOS_DIR);
        
        // Filter for video files only
        const videoExtensions = ['.mp4', '.mov', '.m4v', '.avi', '.mkv', '.webm'];
        const videoFiles = files.filter(file => {
            const ext = path.extname(file).toLowerCase();
            return videoExtensions.includes(ext);
        });

        // Build video metadata
        const videos = videoFiles.map(filename => {
            const filePath = path.join(VIDEOS_DIR, filename);
            const stats = fs.statSync(filePath);
            const ext = path.extname(filename);
            const name = path.basename(filename, ext);
            
            return {
                filename: filename,
                name: name.replace(/[-_]/g, ' '),
                url: `/videos/${encodeURIComponent(filename)}`,
                size: stats.size,
                modified: stats.mtime,
                extension: ext
            };
        });

        // Sort by name
        videos.sort((a, b) => a.name.localeCompare(b.name));

        console.log(`[Server] Video list requested: ${videos.length} videos found`);

        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({
            count: videos.length,
            videos: videos
        }));
    } catch (error) {
        console.error('[Server] Error listing videos:', error);
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Failed to list videos' }));
    }
}

/**
 * Handle video file serving with range support (for streaming)
 */
function handleVideoFileRequest(req, res, pathname) {
    try {
        // Extract filename from path
        const filename = decodeURIComponent(pathname.replace('/videos/', ''));
        const filePath = path.join(VIDEOS_DIR, filename);

        // Security check: prevent directory traversal
        const normalizedPath = path.normalize(filePath);
        if (!normalizedPath.startsWith(VIDEOS_DIR)) {
            res.writeHead(403, { 'Content-Type': 'text/plain' });
            res.end('Forbidden');
            return;
        }

        // Check if file exists
        if (!fs.existsSync(filePath)) {
            res.writeHead(404, { 'Content-Type': 'text/plain' });
            res.end('Video not found');
            return;
        }

        const stat = fs.statSync(filePath);
        const fileSize = stat.size;
        const range = req.headers.range;

        // Determine MIME type
        const ext = path.extname(filename).toLowerCase();
        const mimeTypes = {
            '.mp4': 'video/mp4',
            '.mov': 'video/quicktime',
            '.m4v': 'video/x-m4v',
            '.avi': 'video/x-msvideo',
            '.mkv': 'video/x-matroska',
            '.webm': 'video/webm'
        };
        const contentType = mimeTypes[ext] || 'application/octet-stream';

        if (range) {
            // Handle range requests for video streaming
            const parts = range.replace(/bytes=/, '').split('-');
            const start = parseInt(parts[0], 10);
            const end = parts[1] ? parseInt(parts[1], 10) : fileSize - 1;
            const chunksize = (end - start) + 1;
            const file = fs.createReadStream(filePath, { start, end });

            res.writeHead(206, {
                'Content-Range': `bytes ${start}-${end}/${fileSize}`,
                'Accept-Ranges': 'bytes',
                'Content-Length': chunksize,
                'Content-Type': contentType,
            });

            file.pipe(res);
            console.log(`[Server] Streaming video: ${filename} (${start}-${end}/${fileSize})`);
        } else {
            // Serve entire file
            res.writeHead(200, {
                'Content-Length': fileSize,
                'Content-Type': contentType,
                'Accept-Ranges': 'bytes'
            });

            fs.createReadStream(filePath).pipe(res);
            console.log(`[Server] Serving video: ${filename} (${fileSize} bytes)`);
        }
    } catch (error) {
        console.error('[Server] Error serving video:', error);
        res.writeHead(500, { 'Content-Type': 'text/plain' });
        res.end('Internal Server Error');
    }
}

// Create WebSocket server
const wss = new WebSocket.Server({ server: httpServer });

console.log(`[Server] Vision Pro WebSocket Server starting...`);

wss.on('connection', (ws, req) => {
    const clientIp = req.socket.remoteAddress;
    console.log(`[Server] New connection from ${clientIp}`);

    // Initialize heartbeat tracking
    ws.isAlive = true;
    ws.on('pong', () => {
        ws.isAlive = true;
    });

    let clientInfo = null;

    ws.on('message', (data) => {
        try {
            const message = JSON.parse(data.toString());
            handleMessage(ws, message, clientInfo, (info) => {
                clientInfo = info;
            });
        } catch (error) {
            console.error('[Server] Error parsing message:', error);
            sendError(ws, 'Invalid JSON message');
        }
    });

    ws.on('close', () => {
        console.log(`[Server] Connection closed from ${clientIp}`);
        handleDisconnect(ws, clientInfo);
    });

    ws.on('error', (error) => {
        console.error(`[Server] WebSocket error from ${clientIp}:`, error);
    });

    // Send welcome message
    ws.send(JSON.stringify({
        type: 'welcome',
        message: 'Connected to Vision Pro WebSocket Server',
        serverVersion: '1.0.0'
    }));
});

/**
 * Handle incoming WebSocket messages
 */
function handleMessage(ws, message, clientInfo, setClientInfo) {
    console.log(`[Server] Received message:`, JSON.stringify(message));

    switch (message.type) {
        case 'register':
            handleRegistration(ws, message, setClientInfo);
            break;

        case 'command':
            handleCommand(ws, message, clientInfo);
            break;

        case 'status':
            handleStatusUpdate(ws, message, clientInfo);
            break;

        case 'ping':
            ws.send(JSON.stringify({ type: 'pong', timestamp: Date.now() }));
            break;

        default:
            console.log(`[Server] Unknown message type: ${message.type}`);
    }
}

/**
 * Handle device/controller registration
 */
function handleRegistration(ws, message, setClientInfo) {
    const { deviceId, deviceName, deviceType } = message;

    if (!deviceId || !deviceType) {
        sendError(ws, 'Missing required registration fields');
        return;
    }

    const clientInfo = {
        deviceId,
        deviceName: deviceName || 'Unknown Device',
        deviceType
    };

    setClientInfo(clientInfo);

    if (deviceType === 'visionpro') {
        // Register Vision Pro device
        devices.set(deviceId, {
            ws,
            info: clientInfo,
            state: {
                playbackState: 'idle',
                currentVideo: null,
                immersiveMode: false,
                lastUpdate: Date.now()
            }
        });

        console.log(`[Server] ✅ Vision Pro registered: ${deviceName} (${deviceId})`);
        console.log(`[Server] Total Vision Pro devices: ${devices.size}`);

        // Notify controllers about new device
        const notification = {
            type: 'deviceConnected',
            deviceId,
            deviceName
        };
        console.log(`[Server] Broadcasting to ${controllers.size} controllers:`, JSON.stringify(notification));
        broadcastToControllers(notification);

        // Send current device list to the new device
        ws.send(JSON.stringify({
            type: 'registered',
            deviceId,
            message: 'Successfully registered as Vision Pro device'
        }));

    } else if (deviceType === 'controller') {
        // Register controller
        controllers.add(ws);
        ws.deviceInfo = clientInfo;

        console.log(`[Server] Controller registered: ${deviceName}`);

        // Send current device list to controller
        const deviceList = Array.from(devices.entries()).map(([id, data]) => ({
            deviceId: id,
            deviceName: data.info.deviceName,
            state: data.state
        }));

        ws.send(JSON.stringify({
            type: 'registered',
            deviceId,
            devices: deviceList,
            message: 'Successfully registered as controller'
        }));
    }
}

/**
 * Handle commands from controllers
 */
function handleCommand(ws, message, clientInfo) {
    const { action, videoUrl, targetDevices } = message;

    if (!action) {
        sendError(ws, 'Missing action in command');
        return;
    }

    const validActions = ['play', 'pause', 'resume', 'change', 'stop'];
    if (!validActions.includes(action)) {
        sendError(ws, `Invalid action: ${action}`);
        return;
    }

    // Determine target devices
    let targets = [];
    if (!targetDevices || targetDevices.includes('all')) {
        targets = Array.from(devices.keys());
    } else {
        targets = targetDevices.filter(id => devices.has(id));
    }

    if (targets.length === 0) {
        sendError(ws, 'No target devices available');
        return;
    }

    // Prepare command for devices
    const deviceCommand = {
        type: 'command',
        action,
        videoUrl: videoUrl || null,
        timestamp: Date.now()
    };

    // Send command to target devices
    let sentCount = 0;
    targets.forEach(deviceId => {
        const device = devices.get(deviceId);
        if (device && device.ws.readyState === WebSocket.OPEN) {
            device.ws.send(JSON.stringify(deviceCommand));
            sentCount++;
            console.log(`[Server] Sent ${action} command to ${device.info.deviceName}`);
        }
    });

    // Acknowledge command
    ws.send(JSON.stringify({
        type: 'commandAck',
        action,
        targetCount: sentCount,
        timestamp: Date.now()
    }));
}

/**
 * Handle status updates from Vision Pro devices
 */
function handleStatusUpdate(ws, message, clientInfo) {
    if (!clientInfo || clientInfo.deviceType !== 'visionpro') {
        return;
    }

    const device = devices.get(clientInfo.deviceId);
    if (device) {
        device.state = {
            playbackState: message.state || 'unknown',
            currentVideo: message.currentVideo || null,
            immersiveMode: message.immersiveMode || false,
            currentTime: message.currentTime || 0,
            lastUpdate: Date.now()
        };

        console.log(`[Server] Status update from ${clientInfo.deviceName}: ${message.state} (time: ${message.currentTime})`);

        // Broadcast status to all controllers
        broadcastToControllers({
            type: 'deviceStatus',
            deviceId: clientInfo.deviceId,
            deviceName: clientInfo.deviceName,
            state: device.state
        });
    }
}

/**
 * Handle client disconnection
 */
function handleDisconnect(ws, clientInfo) {
    if (!clientInfo) return;

    if (clientInfo.deviceType === 'visionpro') {
        devices.delete(clientInfo.deviceId);
        console.log(`[Server] Vision Pro disconnected: ${clientInfo.deviceName}`);

        // Notify controllers
        broadcastToControllers({
            type: 'deviceDisconnected',
            deviceId: clientInfo.deviceId,
            deviceName: clientInfo.deviceName
        });

    } else if (clientInfo.deviceType === 'controller') {
        controllers.delete(ws);
        console.log(`[Server] Controller disconnected: ${clientInfo.deviceName}`);
    }
}

/**
 * Broadcast message to all connected controllers
 */
function broadcastToControllers(message) {
    const messageStr = JSON.stringify(message);
    controllers.forEach(controller => {
        if (controller.readyState === WebSocket.OPEN) {
            controller.send(messageStr);
        }
    });
}

/**
 * Send error message to client
 */
function sendError(ws, errorMessage) {
    ws.send(JSON.stringify({
        type: 'error',
        message: errorMessage,
        timestamp: Date.now()
    }));
}

// Heartbeat to detect stale connections
const heartbeatInterval = setInterval(() => {
    wss.clients.forEach(ws => {
        if (ws.isAlive === false) {
            console.log('[Server] Terminating stale connection');
            return ws.terminate();
        }
        ws.isAlive = false;
        ws.ping();
    });
}, 30000);

wss.on('close', () => {
    clearInterval(heartbeatInterval);
});

// Start server
httpServer.listen(config.port, config.host, () => {
    console.log(`[Server] ========================================`);
    console.log(`[Server] Vision Pro Server Started`);
    console.log(`[Server] ========================================`);
    console.log(`[Server] WebSocket: ws://${config.host}:${config.port}`);
    console.log(`[Server] Video API: http://${config.host}:${config.port}/api/videos`);
    console.log(`[Server] Videos Folder: ${VIDEOS_DIR}`);
    console.log(`[Server] Health Check: http://${config.host}:${config.port}/health`);
    console.log(`[Server] Device List: http://${config.host}:${config.port}/devices`);
    console.log(`[Server] ========================================`);
    
    // List available videos on startup
    try {
        const files = fs.readdirSync(VIDEOS_DIR);
        const videoExtensions = ['.mp4', '.mov', '.m4v', '.avi', '.mkv', '.webm'];
        const videoFiles = files.filter(file => {
            const ext = path.extname(file).toLowerCase();
            return videoExtensions.includes(ext);
        });
        console.log(`[Server] Available videos: ${videoFiles.length}`);
        videoFiles.forEach((file, index) => {
            console.log(`[Server]   ${index + 1}. ${file}`);
        });
    } catch (error) {
        console.log(`[Server] No videos folder found or error reading it`);
    }
    console.log(`[Server] ========================================`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
    console.log('[Server] Received SIGTERM, shutting down...');
    wss.close(() => {
        httpServer.close(() => {
            console.log('[Server] Server closed');
            process.exit(0);
        });
    });
});

process.on('SIGINT', () => {
    console.log('[Server] Received SIGINT, shutting down...');
    wss.close(() => {
        httpServer.close(() => {
            console.log('[Server] Server closed');
            process.exit(0);
        });
    });
});
