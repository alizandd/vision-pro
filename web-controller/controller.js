/**
 * Vision Pro Orchestrator Controller
 *
 * Controls Vision Pro devices via WebSocket connection to the relay server.
 * Features: Per-device video preview, individual device controls, media library.
 * Responsive design for tablet and mobile views.
 * Video sync between Vision Pro and web app.
 */

class VisionProController {
    constructor() {
        this.ws = null;
        this.connected = false;
        this.devices = new Map();
        this.selectedVideoUrl = '';
        this.selectedVideoFormat = 'mono2d';
        this.selectedDeviceId = null;
        this.controllerId = this.generateId();
        this.reconnectAttempts = 0;
        this.maxReconnectAttempts = 5;
        this.reconnectDelay = 1000;
        this.logCount = 0;
        this.sidebarOpen = false;
        this.serverBaseUrl = '';

        // Device video players for sync
        this.deviceVideoPreviews = new Map();

        // Video library (loaded from server)
        this.presetVideos = [];

        // Device-specific selected media and format
        this.deviceMediaSelections = new Map();
        this.deviceFormatSelections = new Map();
        
        // Video format options
        this.videoFormats = [
            { value: 'mono2d', label: '2D Flat' },
            { value: 'sbs3d', label: '3D Side-by-Side' },
            { value: 'ou3d', label: '3D Over-Under' },
            { value: 'hemisphere180', label: '180° VR' },
            { value: 'hemisphere180sbs', label: '180° VR 3D' },
            { value: 'sphere360', label: '360° VR' },
            { value: 'sphere360ou', label: '360° VR 3D' }
        ];

        this.init();
    }

    init() {
        this.bindElements();
        this.bindEvents();
        this.setDefaultServerUrl();
        this.log('Orchestrator initialized', 'info');
    }

    /**
     * Set default server URL based on current hostname
     * If accessed via IP (e.g., 192.168.x.x), use that IP for WebSocket
     * If accessed via localhost, use localhost for WebSocket
     */
    setDefaultServerUrl() {
        const currentHost = window.location.hostname;
        const wsPort = 8080; // WebSocket server port
        
        // Construct WebSocket URL based on current host
        const defaultWsUrl = `ws://${currentHost}:${wsPort}`;
        
        // Set the value in the input field
        if (this.serverUrlInput) {
            this.serverUrlInput.value = defaultWsUrl;
            console.log(`[Controller] Default server URL set to: ${defaultWsUrl}`);
        }
    }

    bindElements() {
        // Connection
        this.serverUrlInput = document.getElementById('serverUrl');
        this.connectBtn = document.getElementById('connectBtn');
        this.connectionStatus = document.getElementById('connectionStatus');

        // Mobile Menu
        this.sidebar = document.getElementById('sidebar');
        this.sidebarOverlay = document.getElementById('sidebarOverlay');
        this.mobileMenuBtn = document.getElementById('mobileMenuBtn');

        // Devices
        this.devicesGrid = document.getElementById('devicesGrid');
        this.emptyState = document.getElementById('emptyState');
        this.deviceCount = document.getElementById('deviceCount');


        // Global Controls
        this.playAllBtn = document.getElementById('playAllBtn');
        this.stopAllBtn = document.getElementById('stopAllBtn');
        this.scanDevicesBtn = document.getElementById('scanDevicesBtn');

        // Preview Panel
        this.previewPanel = document.getElementById('previewPanel');
        this.previewDeviceName = document.getElementById('previewDeviceName');
        this.previewStatus = document.getElementById('previewStatus');
        this.previewVideo = document.getElementById('previewVideo');
        this.previewOverlay = document.getElementById('previewOverlay');
        this.previewVideoTitle = document.getElementById('previewVideoTitle');
        this.closePreviewBtn = document.getElementById('closePreviewBtn');
        this.previewPlayBtn = document.getElementById('previewPlayBtn');
        this.previewPauseBtn = document.getElementById('previewPauseBtn');
        this.previewStopBtn = document.getElementById('previewStopBtn');

        // Log
        this.logPanel = document.getElementById('logPanel');
        this.logToggle = document.getElementById('logToggle');
        this.logEntries = document.getElementById('logEntries');
        this.logBadge = document.getElementById('logBadge');
        this.clearLogBtn = document.getElementById('clearLogBtn');
    }

    bindEvents() {
        // Connection
        this.connectBtn.addEventListener('click', () => this.toggleConnection());
        this.serverUrlInput.addEventListener('keypress', (e) => {
            if (e.key === 'Enter') this.toggleConnection();
        });

        // Mobile Menu
        if (this.mobileMenuBtn) {
            this.mobileMenuBtn.addEventListener('click', () => this.toggleSidebar());
        }
        if (this.sidebarOverlay) {
            this.sidebarOverlay.addEventListener('click', () => this.closeSidebar());
        }

        // Global Controls
        this.playAllBtn.addEventListener('click', () => this.sendCommandToAll('play'));
        this.stopAllBtn.addEventListener('click', () => this.sendCommandToAll('stop'));
        this.scanDevicesBtn.addEventListener('click', () => this.log('Scanning for devices...', 'info'));

        // Preview Panel
        this.closePreviewBtn.addEventListener('click', () => this.closePreviewPanel());
        this.previewPlayBtn.addEventListener('click', () => this.sendCommandToSelected('play'));
        this.previewPauseBtn.addEventListener('click', () => this.sendCommandToSelected('pause'));
        this.previewStopBtn.addEventListener('click', () => this.sendCommandToSelected('stop'));

        // Log Panel
        this.logToggle.addEventListener('click', () => this.toggleLogPanel());
        this.clearLogBtn.addEventListener('click', () => this.clearLog());

        // Handle window resize for responsive behavior
        window.addEventListener('resize', () => this.handleResize());
    }

    // =====================================
    // MOBILE SIDEBAR
    // =====================================

    toggleSidebar() {
        this.sidebarOpen = !this.sidebarOpen;
        this.updateSidebarState();
    }

    openSidebar() {
        this.sidebarOpen = true;
        this.updateSidebarState();
    }

    closeSidebar() {
        this.sidebarOpen = false;
        this.updateSidebarState();
    }

    updateSidebarState() {
        if (this.sidebar) {
            this.sidebar.classList.toggle('open', this.sidebarOpen);
        }
        if (this.sidebarOverlay) {
            this.sidebarOverlay.classList.toggle('visible', this.sidebarOpen);
        }
        // Prevent body scroll when sidebar is open on mobile
        document.body.style.overflow = this.sidebarOpen ? 'hidden' : '';
    }

    handleResize() {
        // Close sidebar on larger screens
        if (window.innerWidth > 768 && this.sidebarOpen) {
            this.closeSidebar();
        }
    }

    generateId() {
        return 'controller-' + Math.random().toString(36).substring(2, 11);
    }

    // =====================================
    // CONNECTION MANAGEMENT
    // =====================================

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

        // Extract HTTP base URL from WebSocket URL
        // ws://192.168.1.100:8080 -> http://192.168.1.100:8080
        this.serverBaseUrl = serverUrl.replace('ws://', 'http://').replace('wss://', 'https://');

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
                deviceName: 'Web Orchestrator',
                deviceType: 'controller'
            }));

            // Fetch video library from server
            this.fetchVideosFromServer();
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
            this.updateGlobalControls();

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
        this.reconnectAttempts = this.maxReconnectAttempts;
        if (this.ws) {
            this.ws.close();
        }
        this.devices.clear();
        this.renderDevicesGrid();
    }

    /**
     * Fetch video library from server
     */
    async fetchVideosFromServer() {
        if (!this.serverBaseUrl) {
            this.log('No server URL configured', 'warning');
            return;
        }

        try {
            this.log('Fetching video library from server...', 'info');
            const response = await fetch(`${this.serverBaseUrl}/api/videos`);
            
            if (!response.ok) {
                throw new Error(`HTTP ${response.status}: ${response.statusText}`);
            }

            const data = await response.json();
            
            if (data.videos && Array.isArray(data.videos)) {
                // Convert server video list to preset format
                this.presetVideos = data.videos.map(video => ({
                    name: video.name,
                    description: `${video.extension.toUpperCase()} • ${this.formatFileSize(video.size)}`,
                    url: `${this.serverBaseUrl}${video.url}`,
                    filename: video.filename
                }));

                this.log(`Loaded ${data.count} video(s) from server`, 'success');
                
                // Update media library display
                this.updateMediaLibrary();
                
                // Re-render device cards to show updated video list
                this.renderDevicesGrid();
            } else {
                this.log('No videos found on server', 'warning');
                this.presetVideos = [];
            }
        } catch (error) {
            this.log(`Failed to fetch videos: ${error.message}`, 'error');
            console.error('Error fetching videos:', error);
            this.presetVideos = [];
        }
    }

    /**
     * Update media library display in sidebar
     */
    updateMediaLibrary() {
        const mediaLibrary = document.getElementById('mediaLibrary');
        if (!mediaLibrary) return;

        // Clear existing items
        mediaLibrary.innerHTML = '';

        if (this.presetVideos.length === 0) {
            mediaLibrary.innerHTML = `
                <div class="empty-library">
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                        <rect x="2" y="6" width="20" height="12" rx="2"/>
                        <line x1="2" y1="12" x2="22" y2="12"/>
                    </svg>
                    <p>No videos available</p>
                    <small>Add videos to server/videos/ folder</small>
                </div>
            `;
            return;
        }

        // Create media items
        this.presetVideos.forEach((video, index) => {
            const item = document.createElement('div');
            item.className = 'media-item';
            item.innerHTML = `
                <div class="media-icon">
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                        <polygon points="5,3 19,12 5,21" fill="currentColor"/>
                    </svg>
                </div>
                <div class="media-info">
                    <div class="media-name">${this.escapeHtml(video.name)}</div>
                    <div class="media-desc">${this.escapeHtml(video.description)}</div>
                </div>
            `;
            
            item.addEventListener('click', () => {
                this.selectedVideoUrl = video.url;
                this.log(`Selected: ${video.name}`, 'info');
                
                // Highlight selected item
                document.querySelectorAll('.media-item').forEach(i => i.classList.remove('selected'));
                item.classList.add('selected');
                
                this.updateGlobalControls();
            });
            
            mediaLibrary.appendChild(item);
        });
    }

    /**
     * Format file size to human-readable format
     */
    formatFileSize(bytes) {
        if (bytes === 0) return '0 B';
        const k = 1024;
        const sizes = ['B', 'KB', 'MB', 'GB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return Math.round((bytes / Math.pow(k, i)) * 100) / 100 + ' ' + sizes[i];
    }

    // =====================================
    // MESSAGE HANDLING
    // =====================================

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
                    this.renderDevicesGrid();
                }
                break;

            case 'deviceConnected':
                this.log(`Device connected: ${message.deviceName}`, 'success');
                this.devices.set(message.deviceId, {
                    deviceId: message.deviceId,
                    deviceName: message.deviceName,
                    state: { playbackState: 'idle', immersiveMode: false, currentVideo: null }
                });
                this.renderDevicesGrid();
                break;

            case 'deviceDisconnected':
                this.log(`Device disconnected: ${message.deviceName}`, 'warning');
                this.devices.delete(message.deviceId);
                if (this.selectedDeviceId === message.deviceId) {
                    this.closePreviewPanel();
                }
                this.renderDevicesGrid();
                break;

            case 'deviceStatus':
                const prevDevice = this.devices.get(message.deviceId);
                const prevState = prevDevice?.state?.playbackState;
                const newState = message.state.playbackState;
                
                this.devices.set(message.deviceId, {
                    deviceId: message.deviceId,
                    deviceName: message.deviceName,
                    state: message.state
                });
                
                // First render the grid, then sync video
                // This ensures the video element exists before we try to sync it
                this.renderDevicesGrid();
                this.updatePreviewPanel();
                
                // Sync video preview with device state AFTER render
                this.syncVideoPreview(message.deviceId, message.state, prevState);
                
                this.log(`${message.deviceName}: ${message.state.playbackState}`, 'info');
                break;

            case 'commandAck':
                this.log(`Command '${message.action}' sent to ${message.targetCount} device(s)`, 'success');
                break;

            case 'error':
                this.log(`Error: ${message.message}`, 'error');
                break;

            case 'pong':
                break;

            default:
                console.log('Unknown message:', message);
        }

        this.updateGlobalControls();
    }

    // =====================================
    // COMMANDS
    // =====================================

    sendCommand(action, deviceId, videoUrl = null, videoFormat = null) {
        if (!this.connected || !this.ws) {
            this.log('Not connected to server', 'error');
            return;
        }

        const command = {
            type: 'command',
            action: action,
            targetDevices: [deviceId]
        };

        if ((action === 'play' || action === 'change') && videoUrl) {
            command.videoUrl = videoUrl;
            // Include video format - use device-specific format or default
            command.videoFormat = videoFormat || this.deviceFormatSelections.get(deviceId) || 'mono2d';
        }

        this.ws.send(JSON.stringify(command));
        const formatLabel = this.videoFormats.find(f => f.value === command.videoFormat)?.label || command.videoFormat;
        this.log(`Sending '${action}' to device... (${formatLabel})`, 'info');
    }

    sendCommandToAll(action) {
        if (!this.connected || !this.ws) {
            this.log('Not connected to server', 'error');
            return;
        }

        const command = {
            type: 'command',
            action: action,
            targetDevices: ['all']
        };

        if ((action === 'play' || action === 'change') && this.selectedVideoUrl) {
            command.videoUrl = this.selectedVideoUrl;
            command.videoFormat = this.selectedVideoFormat || 'mono2d';
        }

        this.ws.send(JSON.stringify(command));
        this.log(`Sending '${action}' to all devices...`, 'info');
    }

    sendCommandToSelected(action) {
        if (!this.selectedDeviceId) return;
        const device = this.devices.get(this.selectedDeviceId);
        if (!device) return;

        const videoUrl = this.deviceMediaSelections.get(this.selectedDeviceId) || 
                         device.state?.currentVideo || 
                         this.selectedVideoUrl;

        this.sendCommand(action, this.selectedDeviceId, videoUrl);
    }

    // =====================================
    // UI UPDATES
    // =====================================

    updateConnectionStatus(status) {
        const indicator = this.connectionStatus.querySelector('.status-indicator');
        const label = this.connectionStatus.querySelector('.status-label');

        indicator.className = 'status-indicator ' + status;

        const statusText = {
            disconnected: 'Disconnected',
            connecting: 'Connecting...',
            connected: 'Connected'
        };
        label.textContent = statusText[status] || status;

        this.connectBtn.innerHTML = status === 'connected' 
            ? '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2"><line x1="18" y1="6" x2="6" y2="18"></line><line x1="6" y1="6" x2="18" y2="18"></line></svg>'
            : '<span class="connect-icon"></span>';

        this.serverUrlInput.disabled = status === 'connected';
    }

    updateGlobalControls() {
        const hasDevices = this.devices.size > 0;
        const hasVideo = !!this.selectedVideoUrl;
        const isConnected = this.connected;

        this.playAllBtn.disabled = !isConnected || !hasDevices || !hasVideo;
        this.stopAllBtn.disabled = !isConnected || !hasDevices;
    }

    renderDevicesGrid() {
        // Update device count
        const count = this.devices.size;
        this.deviceCount.textContent = `${count} device${count !== 1 ? 's' : ''}`;

        // Show/hide empty state
        if (count === 0) {
            this.emptyState.classList.remove('hidden');
            // Remove existing device cards
            const existingCards = this.devicesGrid.querySelectorAll('.device-card');
            existingCards.forEach(card => card.remove());
            return;
        }

        this.emptyState.classList.add('hidden');

        // Build device cards
        const fragment = document.createDocumentFragment();
        
        this.devices.forEach((device, deviceId) => {
            const card = this.createDeviceCard(device, deviceId);
            fragment.appendChild(card);
        });

        // Clear existing cards and append new ones
        const existingCards = this.devicesGrid.querySelectorAll('.device-card');
        existingCards.forEach(card => card.remove());
        this.devicesGrid.appendChild(fragment);
    }

    createDeviceCard(device, deviceId) {
        const state = device.state || {};
        const playbackState = state.playbackState || 'idle';
        const currentVideo = state.currentVideo || null;
        const immersive = state.immersiveMode || false;

        const card = document.createElement('div');
        card.className = `device-card${this.selectedDeviceId === deviceId ? ' selected' : ''}`;
        card.dataset.deviceId = deviceId;

        // Get video name from URL
        const videoName = currentVideo ? this.getVideoNameFromUrl(currentVideo) : null;
        const selectedMedia = this.deviceMediaSelections.get(deviceId);

        card.innerHTML = `
            <div class="device-card-header">
                <div class="device-identity">
                    <div class="device-icon">
                        <svg viewBox="0 0 32 32">
                            <rect x="4" y="8" width="24" height="16" rx="8" fill="none" stroke="currentColor" stroke-width="2"/>
                            <circle cx="11" cy="16" r="3" fill="currentColor"/>
                            <circle cx="21" cy="16" r="3" fill="currentColor"/>
                        </svg>
                    </div>
                    <div class="device-meta">
                        <h3>${this.escapeHtml(device.deviceName)}</h3>
                        <span class="device-id-badge">${deviceId.substring(0, 12)}...</span>
                    </div>
                </div>
                <div class="device-status">
                    <span class="status-badge ${playbackState}">
                        <span class="status-dot"></span>
                        ${playbackState}
                    </span>
                    ${immersive ? `
                        <span class="immersive-badge">
                            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                                <circle cx="12" cy="12" r="10"/>
                                <circle cx="12" cy="12" r="4"/>
                            </svg>
                            Immersive
                        </span>
                    ` : ''}
                </div>
            </div>
            <div class="device-card-body">
                <div class="device-media-section">
                    <div class="media-selector-row">
                        <label>Choose media:</label>
                        <select class="media-select" data-device-id="${deviceId}">
                            <option value="">Select video...</option>
                            ${this.presetVideos.map(v => `
                                <option value="${this.escapeHtml(v.url)}" ${selectedMedia === v.url ? 'selected' : ''}>${this.escapeHtml(v.name)}</option>
                            `).join('')}
                        </select>
                    </div>
                    <div class="format-selector-row">
                        <label>Video format:</label>
                        <select class="format-select" data-device-id="${deviceId}">
                            ${this.videoFormats.map(f => `
                                <option value="${f.value}" ${(this.deviceFormatSelections.get(deviceId) || 'hemisphere180sbs') === f.value ? 'selected' : ''}>${f.label}</option>
                            `).join('')}
                        </select>
                    </div>
                    <div class="current-video-display">
                        ${currentVideo ? `
                            <div class="video-icon">
                                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                                    <polygon points="5,3 19,12 5,21" fill="currentColor"/>
                                </svg>
                            </div>
                            <div class="video-info">
                                <div class="video-title">${this.escapeHtml(videoName || 'Playing')}</div>
                                <div class="video-url">${this.escapeHtml(currentVideo)}</div>
                            </div>
                        ` : `
                            <span class="no-video-playing">No video playing</span>
                        `}
                    </div>
                    <div class="device-controls">
                        <button class="btn-device-control btn-device-play" data-action="play" data-device-id="${deviceId}">
                            <svg viewBox="0 0 24 24"><polygon points="5,3 19,12 5,21" fill="currentColor"/></svg>
                            Play
                        </button>
                        <button class="btn-device-control btn-device-pause" data-action="pause" data-device-id="${deviceId}">
                            <svg viewBox="0 0 24 24"><rect x="6" y="4" width="4" height="16" fill="currentColor"/><rect x="14" y="4" width="4" height="16" fill="currentColor"/></svg>
                            Pause
                        </button>
                        <button class="btn-device-control btn-device-resume" data-action="resume" data-device-id="${deviceId}">
                            <svg viewBox="0 0 24 24"><polygon points="5,3 19,12 5,21" fill="currentColor"/></svg>
                            Resume
                        </button>
                        <button class="btn-device-control btn-device-stop" data-action="stop" data-device-id="${deviceId}">
                            <svg viewBox="0 0 24 24"><rect x="4" y="4" width="16" height="16" fill="currentColor"/></svg>
                            Stop
                        </button>
                    </div>
                </div>
                <div class="device-preview-section">
                    <div class="preview-thumbnail">
                        ${currentVideo && (playbackState === 'playing' || playbackState === 'paused') ? `
                            <video src="${this.escapeHtml(currentVideo)}" muted loop></video>
                            ${playbackState === 'playing' ? `
                                <div class="preview-live-badge">
                                    <span class="live-dot"></span>
                                    LIVE
                                </div>
                            ` : `
                                <div class="preview-paused-badge">
                                    <span class="paused-icon">❚❚</span>
                                    PAUSED
                                </div>
                            `}
                        ` : `
                            <div class="no-preview-placeholder">
                                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                                    <rect x="2" y="2" width="20" height="20" rx="2"/>
                                    <circle cx="12" cy="12" r="3"/>
                                </svg>
                                <span>No preview</span>
                            </div>
                        `}
                        <div class="preview-thumbnail-overlay">
                            <button class="btn-expand-preview" data-device-id="${deviceId}">
                                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                                    <polyline points="15,3 21,3 21,9"/>
                                    <polyline points="9,21 3,21 3,15"/>
                                    <line x1="21" y1="3" x2="14" y2="10"/>
                                    <line x1="3" y1="21" x2="10" y2="14"/>
                                </svg>
                            </button>
                        </div>
                    </div>
                </div>
            </div>
        `;

        // Bind events
        this.bindDeviceCardEvents(card, deviceId);

        return card;
    }

    bindDeviceCardEvents(card, deviceId) {
        // Media selector
        const mediaSelect = card.querySelector('.media-select');
        mediaSelect.addEventListener('change', (e) => {
            this.deviceMediaSelections.set(deviceId, e.target.value);
            this.log(`Media selected for device: ${e.target.value.split('/').pop()}`, 'info');
        });
        
        // Format selector
        const formatSelect = card.querySelector('.format-select');
        if (formatSelect) {
            formatSelect.addEventListener('change', (e) => {
                this.deviceFormatSelections.set(deviceId, e.target.value);
                const formatLabel = this.videoFormats.find(f => f.value === e.target.value)?.label || e.target.value;
                this.log(`Format selected: ${formatLabel}`, 'info');
            });
        }

        // Control buttons
        const controlBtns = card.querySelectorAll('.btn-device-control');
        controlBtns.forEach(btn => {
            btn.addEventListener('click', (e) => {
                const action = btn.dataset.action;
                const targetDeviceId = btn.dataset.deviceId;
                const videoUrl = this.deviceMediaSelections.get(targetDeviceId);
                const videoFormat = this.deviceFormatSelections.get(targetDeviceId);
                
                if (action === 'play' && !videoUrl) {
                    this.log('Please select a video first', 'warning');
                    return;
                }
                
                this.sendCommand(action, targetDeviceId, videoUrl, videoFormat);
            });
        });

        // Expand preview button
        const expandBtn = card.querySelector('.btn-expand-preview');
        expandBtn.addEventListener('click', () => {
            this.selectDevice(deviceId);
        });

        // Card click to select
        card.querySelector('.device-card-header').addEventListener('click', () => {
            this.selectDevice(deviceId);
        });
    }

    selectDevice(deviceId) {
        this.selectedDeviceId = deviceId;
        
        // Update card selection state
        document.querySelectorAll('.device-card').forEach(card => {
            card.classList.toggle('selected', card.dataset.deviceId === deviceId);
        });

        this.openPreviewPanel();
    }

    openPreviewPanel() {
        if (!this.selectedDeviceId) return;
        const device = this.devices.get(this.selectedDeviceId);
        if (!device) return;

        this.previewPanel.classList.add('open');
        this.updatePreviewPanel();
    }

    updatePreviewPanel() {
        if (!this.selectedDeviceId || !this.previewPanel.classList.contains('open')) return;
        
        const device = this.devices.get(this.selectedDeviceId);
        if (!device) return;

        const state = device.state || {};
        const currentVideo = state.currentVideo;
        const playbackState = state.playbackState || 'idle';

        this.previewDeviceName.textContent = device.deviceName;
        this.previewStatus.textContent = playbackState.toUpperCase();

        if (currentVideo && (playbackState === 'playing' || playbackState === 'paused')) {
            // Only change src if different to avoid reload (compare without protocol differences)
            const currentSrc = this.previewVideo.src || '';
            const isSameVideo = currentSrc.endsWith(currentVideo.split('/').pop()) || currentSrc === currentVideo;
            
            if (!isSameVideo) {
                this.previewVideo.src = currentVideo;
            }
            this.previewOverlay.classList.add('hidden');
            this.previewVideoTitle.textContent = this.getVideoNameFromUrl(currentVideo) || currentVideo;
            
            // Sync playback state without restarting
            if (playbackState === 'playing') {
                if (this.previewVideo.paused) {
                    this.previewVideo.play().catch(() => {});
                }
            } else {
                if (!this.previewVideo.paused) {
                    this.previewVideo.pause();
                }
            }
        } else {
            if (this.previewVideo.src) {
                this.previewVideo.pause();
                this.previewVideo.src = '';
            }
            this.previewOverlay.classList.remove('hidden');
            this.previewVideoTitle.textContent = '—';
        }
    }

    // =====================================
    // VIDEO SYNC
    // =====================================

    /**
     * Sync video preview with Vision Pro device state
     * When device plays/pauses, the web preview syncs automatically
     * Also syncs the current playback time for accurate preview
     */
    syncVideoPreview(deviceId, state, prevState) {
        const currentVideo = state.currentVideo;
        const playbackState = state.playbackState;
        const deviceTime = state.currentTime || 0;
        
        // Find the video element in the device card
        const card = document.querySelector(`.device-card[data-device-id="${deviceId}"]`);
        if (!card) return;
        
        const videoEl = card.querySelector('.preview-thumbnail video');
        
        // Handle video sync based on state change
        if (playbackState === 'playing' && currentVideo) {
            // Video started playing on Vision Pro - sync to web
            if (videoEl) {
                if (videoEl.src !== currentVideo) {
                    videoEl.src = currentVideo;
                    videoEl.addEventListener('loadedmetadata', () => {
                        this.syncVideoTime(videoEl, deviceTime);
                        videoEl.play().catch(() => {});
                    }, { once: true });
                } else {
                    this.syncVideoTime(videoEl, deviceTime);
                    videoEl.play().catch(() => {});
                }
            }
            
            // If this device is selected, also sync the main preview
            if (this.selectedDeviceId === deviceId && this.previewPanel.classList.contains('open')) {
                if (this.previewVideo.src !== currentVideo) {
                    this.previewVideo.src = currentVideo;
                    this.previewVideo.addEventListener('loadedmetadata', () => {
                        this.syncVideoTime(this.previewVideo, deviceTime);
                        this.previewVideo.play().catch(() => {});
                    }, { once: true });
                } else {
                    this.syncVideoTime(this.previewVideo, deviceTime);
                    this.previewVideo.play().catch(() => {});
                }
            }
            
        } else if (playbackState === 'paused') {
            // Video paused on Vision Pro - pause web preview and sync time
            if (videoEl) {
                videoEl.pause();
                this.syncVideoTime(videoEl, deviceTime);
            }
            
            if (this.selectedDeviceId === deviceId) {
                this.previewVideo.pause();
                this.syncVideoTime(this.previewVideo, deviceTime);
            }
            
        } else if (playbackState === 'stopped' || playbackState === 'idle') {
            // Video stopped on Vision Pro - stop web preview
            if (videoEl) {
                videoEl.pause();
                videoEl.currentTime = 0;
            }
            
            if (this.selectedDeviceId === deviceId) {
                this.previewVideo.pause();
                this.previewVideo.currentTime = 0;
            }
        }
    }

    /**
     * Sync video element time with device time
     * Only seeks if difference is more than 2 seconds to avoid constant seeking
     */
    syncVideoTime(videoEl, deviceTime) {
        if (!videoEl || !deviceTime || isNaN(deviceTime)) return;
        
        const currentTime = videoEl.currentTime || 0;
        const timeDiff = Math.abs(currentTime - deviceTime);
        
        // Only seek if difference is more than 2 seconds
        if (timeDiff > 2) {
            videoEl.currentTime = deviceTime;
        }
    }

    closePreviewPanel() {
        this.previewPanel.classList.remove('open');
        this.previewVideo.pause();
        this.previewVideo.src = '';
        this.selectedDeviceId = null;

        document.querySelectorAll('.device-card').forEach(card => {
            card.classList.remove('selected');
        });
    }

    getVideoNameFromUrl(url) {
        try {
            const pathname = new URL(url).pathname;
            const filename = pathname.split('/').pop();
            return filename.replace(/\.[^/.]+$/, '').replace(/[-_]/g, ' ');
        } catch {
            return null;
        }
    }

    // =====================================
    // LOG PANEL
    // =====================================

    toggleLogPanel() {
        this.logPanel.classList.toggle('collapsed');
    }

    log(message, type = 'info') {
        const time = new Date().toLocaleTimeString();
        const entry = document.createElement('div');
        entry.className = `log-entry ${type}`;
        entry.innerHTML = `
            <span class="log-time">${time}</span>
            <span class="log-message">${this.escapeHtml(message)}</span>
        `;

        this.logEntries.appendChild(entry);
        this.logEntries.scrollTop = this.logEntries.scrollHeight;

        // Update badge
        this.logCount++;
        this.logBadge.textContent = this.logCount > 99 ? '99+' : this.logCount;

        // Keep log size manageable
        while (this.logEntries.children.length > 100) {
            this.logEntries.removeChild(this.logEntries.firstChild);
        }
    }

    clearLog() {
        this.logEntries.innerHTML = '';
        this.logCount = 0;
        this.logBadge.textContent = '0';
        this.log('Log cleared', 'info');
    }

    escapeHtml(text) {
        if (!text) return '';
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }
}

// Initialize controller when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
    window.controller = new VisionProController();
});
