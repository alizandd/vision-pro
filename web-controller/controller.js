/**
 * Vision Pro Web Controller
 *
 * Controls Vision Pro devices via WebSocket connection to the relay server.
 */

class VisionProController {
    constructor() {
        this.ws = null;
        this.connected = false;
        this.devices = new Map();
        this.selectedVideoUrl = '';
        this.controllerId = this.generateId();
        this.reconnectAttempts = 0;
        this.maxReconnectAttempts = 5;
        this.reconnectDelay = 1000;

        // Sample videos for testing
        this.presetVideos = [
            {
                name: 'Big Buck Bunny',
                description: '360p MP4 sample',
                url: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4'
            },
            {
                name: 'Elephant Dream',
                description: 'Blender movie',
                url: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4'
            },
            {
                name: 'Sintel',
                description: 'Blender animated film',
                url: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4'
            },
            {
                name: 'Tears of Steel',
                description: 'Sci-fi short film',
                url: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4'
            }
        ];

        this.init();
    }

    init() {
        this.bindElements();
        this.bindEvents();
        this.renderPresetVideos();
        this.log('Controller initialized', 'info');
    }

    bindElements() {
        // Connection
        this.serverUrlInput = document.getElementById('serverUrl');
        this.connectBtn = document.getElementById('connectBtn');
        this.connectionStatus = document.getElementById('connectionStatus');

        // Devices
        this.devicesList = document.getElementById('devicesList');
        this.targetDevices = document.getElementById('targetDevices');

        // Video
        this.videoUrlInput = document.getElementById('videoUrl');
        this.loadVideoBtn = document.getElementById('loadVideoBtn');
        this.presetList = document.getElementById('presetList');

        // Controls
        this.playBtn = document.getElementById('playBtn');
        this.pauseBtn = document.getElementById('pauseBtn');
        this.resumeBtn = document.getElementById('resumeBtn');
        this.stopBtn = document.getElementById('stopBtn');

        // Log
        this.logContainer = document.getElementById('logContainer');
        this.clearLogBtn = document.getElementById('clearLogBtn');
    }

    bindEvents() {
        this.connectBtn.addEventListener('click', () => this.toggleConnection());
        this.loadVideoBtn.addEventListener('click', () => this.loadVideo());
        this.playBtn.addEventListener('click', () => this.sendCommand('play'));
        this.pauseBtn.addEventListener('click', () => this.sendCommand('pause'));
        this.resumeBtn.addEventListener('click', () => this.sendCommand('resume'));
        this.stopBtn.addEventListener('click', () => this.sendCommand('stop'));
        this.clearLogBtn.addEventListener('click', () => this.clearLog());

        this.videoUrlInput.addEventListener('input', (e) => {
            this.selectedVideoUrl = e.target.value;
            this.updateControlsState();
        });

        this.videoUrlInput.addEventListener('keypress', (e) => {
            if (e.key === 'Enter') {
                this.loadVideo();
            }
        });
    }

    generateId() {
        return 'controller-' + Math.random().toString(36).substring(2, 11);
    }

    // Connection Management

    toggleConnection() {
        if (this.connected) {
            this.disconnect();
        } else {
            this.connect();
        }
    }

    connect() {
        const serverUrl = this.serverUrlInput.value.trim();
        if (!serverUrl) {
            this.log('Please enter a server URL', 'error');
            return;
        }

        this.updateConnectionStatus('connecting');
        this.log(`Connecting to ${serverUrl}...`, 'info');

        try {
            this.ws = new WebSocket(serverUrl);
            this.setupWebSocketHandlers();
        } catch (error) {
            this.log(`Connection error: ${error.message}`, 'error');
            this.updateConnectionStatus('disconnected');
        }
    }

    setupWebSocketHandlers() {
        this.ws.onopen = () => {
            this.connected = true;
            this.reconnectAttempts = 0;
            this.updateConnectionStatus('connected');
            this.log('Connected to server', 'success');

            // Register as controller
            this.ws.send(JSON.stringify({
                type: 'register',
                deviceId: this.controllerId,
                deviceName: 'Web Controller',
                deviceType: 'controller'
            }));
        };

        this.ws.onmessage = (event) => {
            try {
                const message = JSON.parse(event.data);
                this.handleMessage(message);
            } catch (error) {
                this.log(`Error parsing message: ${error.message}`, 'error');
            }
        };

        this.ws.onclose = () => {
            this.connected = false;
            this.updateConnectionStatus('disconnected');
            this.log('Disconnected from server', 'warning');
            this.updateControlsState();

            // Attempt reconnection
            if (this.reconnectAttempts < this.maxReconnectAttempts) {
                const delay = this.reconnectDelay * Math.pow(2, this.reconnectAttempts);
                this.log(`Reconnecting in ${delay / 1000}s...`, 'info');
                setTimeout(() => {
                    this.reconnectAttempts++;
                    this.connect();
                }, delay);
            }
        };

        this.ws.onerror = (error) => {
            this.log('WebSocket error', 'error');
            console.error('WebSocket error:', error);
        };
    }

    disconnect() {
        this.reconnectAttempts = this.maxReconnectAttempts; // Prevent auto-reconnect
        if (this.ws) {
            this.ws.close();
        }
        this.devices.clear();
        this.renderDevicesList();
        this.updateDeviceSelector();
    }

    // Message Handling

    handleMessage(message) {
        switch (message.type) {
            case 'welcome':
                this.log(`Server: ${message.message}`, 'info');
                break;

            case 'registered':
                this.log('Registered with server', 'success');
                if (message.devices) {
                    message.devices.forEach(device => {
                        this.devices.set(device.deviceId, device);
                    });
                    this.renderDevicesList();
                    this.updateDeviceSelector();
                }
                break;

            case 'deviceConnected':
                this.log(`Device connected: ${message.deviceName}`, 'success');
                this.devices.set(message.deviceId, {
                    deviceId: message.deviceId,
                    deviceName: message.deviceName,
                    state: { playbackState: 'idle', immersiveMode: false }
                });
                this.renderDevicesList();
                this.updateDeviceSelector();
                break;

            case 'deviceDisconnected':
                this.log(`Device disconnected: ${message.deviceName}`, 'warning');
                this.devices.delete(message.deviceId);
                this.renderDevicesList();
                this.updateDeviceSelector();
                break;

            case 'deviceStatus':
                this.devices.set(message.deviceId, {
                    deviceId: message.deviceId,
                    deviceName: message.deviceName,
                    state: message.state
                });
                this.renderDevicesList();
                this.log(`${message.deviceName}: ${message.state.playbackState}`, 'info');
                break;

            case 'commandAck':
                this.log(`Command '${message.action}' sent to ${message.targetCount} device(s)`, 'success');
                break;

            case 'error':
                this.log(`Error: ${message.message}`, 'error');
                break;

            case 'pong':
                // Heartbeat response
                break;

            default:
                console.log('Unknown message:', message);
        }

        this.updateControlsState();
    }

    // Commands

    sendCommand(action) {
        if (!this.connected || !this.ws) {
            this.log('Not connected to server', 'error');
            return;
        }

        const targetValue = this.targetDevices.value;
        const targetDevicesArray = targetValue === 'all' ? ['all'] : [targetValue];

        const command = {
            type: 'command',
            action: action,
            targetDevices: targetDevicesArray
        };

        // Include video URL for play and change commands
        if (action === 'play' || action === 'change') {
            if (!this.selectedVideoUrl) {
                this.log('Please select or enter a video URL', 'warning');
                return;
            }
            command.videoUrl = this.selectedVideoUrl;
        }

        this.ws.send(JSON.stringify(command));
        this.log(`Sending '${action}' command...`, 'info');
    }

    loadVideo() {
        const url = this.videoUrlInput.value.trim();
        if (url) {
            this.selectedVideoUrl = url;
            this.log(`Video loaded: ${url}`, 'info');

            // Deselect presets
            document.querySelectorAll('.preset-item').forEach(item => {
                item.classList.remove('selected');
            });

            this.updateControlsState();
        }
    }

    // UI Updates

    updateConnectionStatus(status) {
        const dot = this.connectionStatus.querySelector('.status-dot');
        const text = this.connectionStatus.querySelector('.status-text');

        dot.className = 'status-dot ' + status;

        const statusText = {
            disconnected: 'Disconnected',
            connecting: 'Connecting...',
            connected: 'Connected'
        };
        text.textContent = statusText[status] || status;

        this.connectBtn.textContent = status === 'connected' ? 'Disconnect' : 'Connect';
        this.serverUrlInput.disabled = status === 'connected';
    }

    updateControlsState() {
        const hasDevices = this.devices.size > 0;
        const hasVideo = !!this.selectedVideoUrl;
        const isConnected = this.connected;

        this.playBtn.disabled = !isConnected || !hasDevices || !hasVideo;
        this.pauseBtn.disabled = !isConnected || !hasDevices;
        this.resumeBtn.disabled = !isConnected || !hasDevices;
        this.stopBtn.disabled = !isConnected || !hasDevices;
        this.loadVideoBtn.disabled = !isConnected;
    }

    renderDevicesList() {
        if (this.devices.size === 0) {
            this.devicesList.innerHTML = '<p class="no-devices">No Vision Pro devices connected</p>';
            return;
        }

        this.devicesList.innerHTML = Array.from(this.devices.values()).map(device => {
            const state = device.state || {};
            const playbackState = state.playbackState || 'unknown';
            const immersive = state.immersiveMode ? '<span class="immersive-indicator">Immersive</span>' : '';

            return `
                <div class="device-card">
                    <div class="device-info">
                        <span class="device-name">${this.escapeHtml(device.deviceName)}</span>
                        <span class="device-id">${device.deviceId}</span>
                    </div>
                    <div class="device-state">
                        <span class="state-badge ${playbackState}">${playbackState}</span>
                        ${immersive}
                    </div>
                </div>
            `;
        }).join('');
    }

    updateDeviceSelector() {
        const currentValue = this.targetDevices.value;

        this.targetDevices.innerHTML = '<option value="all">All Devices</option>';

        this.devices.forEach((device, deviceId) => {
            const option = document.createElement('option');
            option.value = deviceId;
            option.textContent = device.deviceName;
            this.targetDevices.appendChild(option);
        });

        // Restore selection if still valid
        if (currentValue !== 'all' && this.devices.has(currentValue)) {
            this.targetDevices.value = currentValue;
        }
    }

    renderPresetVideos() {
        this.presetList.innerHTML = this.presetVideos.map((video, index) => `
            <div class="preset-item" data-index="${index}" data-url="${this.escapeHtml(video.url)}">
                <div class="preset-name">${this.escapeHtml(video.name)}</div>
                <div class="preset-description">${this.escapeHtml(video.description)}</div>
            </div>
        `).join('');

        // Bind click events
        this.presetList.querySelectorAll('.preset-item').forEach(item => {
            item.addEventListener('click', () => {
                // Deselect all
                this.presetList.querySelectorAll('.preset-item').forEach(i => {
                    i.classList.remove('selected');
                });

                // Select this one
                item.classList.add('selected');

                // Update video URL
                this.selectedVideoUrl = item.dataset.url;
                this.videoUrlInput.value = this.selectedVideoUrl;
                this.updateControlsState();

                const video = this.presetVideos[item.dataset.index];
                this.log(`Selected: ${video.name}`, 'info');
            });
        });
    }

    // Logging

    log(message, type = 'info') {
        const time = new Date().toLocaleTimeString();
        const entry = document.createElement('div');
        entry.className = `log-entry ${type}`;
        entry.innerHTML = `
            <span class="log-time">${time}</span>
            <span class="log-message">${this.escapeHtml(message)}</span>
        `;

        this.logContainer.appendChild(entry);
        this.logContainer.scrollTop = this.logContainer.scrollHeight;

        // Keep log size manageable
        while (this.logContainer.children.length > 100) {
            this.logContainer.removeChild(this.logContainer.firstChild);
        }
    }

    clearLog() {
        this.logContainer.innerHTML = '';
        this.log('Log cleared', 'info');
    }

    escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }
}

// Initialize controller when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
    window.controller = new VisionProController();
});
