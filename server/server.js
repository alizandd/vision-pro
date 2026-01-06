/**
 * Vision Pro WebSocket Relay Server
 *
 * This server relays commands between web controllers and Vision Pro devices.
 * It maintains a registry of connected devices and their states.
 */

const WebSocket = require('ws');
const http = require('http');
const config = require('./config');

// Device registry
const devices = new Map();      // deviceId -> { ws, info, state }
const controllers = new Set();  // Set of controller WebSocket connections

// Create HTTP server for health checks
const httpServer = http.createServer((req, res) => {
    if (req.url === '/health') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({
            status: 'healthy',
            connectedDevices: devices.size,
            connectedControllers: controllers.size,
            uptime: process.uptime()
        }));
    } else if (req.url === '/devices') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        const deviceList = Array.from(devices.entries()).map(([id, data]) => ({
            deviceId: id,
            deviceName: data.info.deviceName,
            state: data.state
        }));
        res.end(JSON.stringify(deviceList));
    } else {
        res.writeHead(404);
        res.end('Not Found');
    }
});

// Create WebSocket server
const wss = new WebSocket.Server({ server: httpServer });

console.log(`[Server] Vision Pro WebSocket Server starting...`);

wss.on('connection', (ws, req) => {
    const clientIp = req.socket.remoteAddress;
    console.log(`[Server] New connection from ${clientIp}`);

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

        console.log(`[Server] Vision Pro registered: ${deviceName} (${deviceId})`);

        // Notify controllers about new device
        broadcastToControllers({
            type: 'deviceConnected',
            deviceId,
            deviceName
        });

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
            lastUpdate: Date.now()
        };

        console.log(`[Server] Status update from ${clientInfo.deviceName}: ${message.state}`);

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

// Handle client pong responses
wss.on('connection', (ws) => {
    ws.isAlive = true;
    ws.on('pong', () => {
        ws.isAlive = true;
    });
});

// Start server
httpServer.listen(config.port, config.host, () => {
    console.log(`[Server] WebSocket server running on ws://${config.host}:${config.port}`);
    console.log(`[Server] Health check: http://${config.host}:${config.port}/health`);
    console.log(`[Server] Device list: http://${config.host}:${config.port}/devices`);
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
