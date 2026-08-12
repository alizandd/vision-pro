import Foundation
import Combine

/// Manages connected Vision Pro devices and communication
@MainActor
class DeviceManager: ObservableObject {
    @Published var devices: [ConnectedDevice] = []
    @Published var isServerRunning: Bool = false
    @Published var serverPort: UInt16 = 8080
    @Published var connectionCount: Int = 0
    @Published var logs: [LogEntry] = []
    
    private let webSocketServer = WebSocketServer()
    let fileTransferServer = FileTransferServer()
    /// Flat companion videos used to preview what a headset viewer is watching.
    let companionLibrary = CompanionLibrary()
    /// Which companion represents which headset video.
    let pairingStore = CompanionPairingStore()
    let syncManager = SyncSessionManager()
    private var cancellables = Set<AnyCancellable>()
    /// Devices currently asked to report viewer state.
    private var previewSubscriptions: Set<String> = []

    init() {
        setupBindings()
        setupCallbacks()
        setupSyncManager()
        setupPreviewRepublishing()
    }

    /// The companion library and pairing store are separate observable objects,
    /// so views watching only the device manager would not redraw when a pairing
    /// changes — the paired badge simply never appeared. Republish their changes
    /// here rather than threading both objects through every view.
    private func setupPreviewRepublishing() {
        pairingStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        companionLibrary.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    /// Wires the sync session manager to the WebSocket server and device state
    private func setupSyncManager() {
        syncManager.sendToDevice = { [weak self] deviceId, message in
            self?.webSocketServer.send(to: deviceId, message: message)
        }
        syncManager.deviceCurrentTime = { [weak self] deviceId in
            self?.devices.first(where: { $0.deviceId == deviceId })?.state.currentTime
        }
        syncManager.setDeviceFormat = { [weak self] deviceId, format in
            self?.devices.first(where: { $0.deviceId == deviceId })?.state.currentFormat = format
        }
        syncManager.log = { [weak self] message, type in
            self?.log(message, type: type)
        }

        webSocketServer.onClockSyncResponse = { [weak self] deviceId, response in
            Task { @MainActor in
                self?.syncManager.handleClockSyncResponse(deviceId: deviceId, response: response)
            }
        }

        webSocketServer.onSyncReady = { [weak self] deviceId, message in
            Task { @MainActor in
                self?.syncManager.handleSyncReady(deviceId: deviceId, message: message)
            }
        }
    }
    
    // MARK: - Server Control
    
    /// Start the server.
    ///
    /// Bonjour advertising is owned by `WebSocketServer` and published on the
    /// same listener that actually accepts the WebSocket connections — there is
    /// deliberately no second advertiser here. A separate listener bound to the
    /// same port would both publish a duplicate `_visionproctl._tcp` record and
    /// steal (then drop) incoming connections.
    func startServer() {
        log("Starting server...", type: .info)
        webSocketServer.start()
        fileTransferServer.start()
    }

    /// Stop the server
    func stopServer() {
        log("Stopping server...", type: .info)
        webSocketServer.stop()
        fileTransferServer.stop()
        devices.removeAll()
    }
    
    // MARK: - Commands
    
    /// Send play command to device
    func play(deviceId: String, videoUrl: String, format: VideoFormat) {
        let command = CommandMessage(action: .play, videoUrl: videoUrl, videoFormat: format)
        webSocketServer.sendCommand(to: deviceId, command: command)
        // Remember the projection we asked for — the preview needs it to know
        // whether a look direction is meaningful for this content.
        devices.first(where: { $0.deviceId == deviceId })?.state.currentFormat = format
        log("Play command sent to \(deviceName(for: deviceId))", type: .success)
    }
    
    /// Smart play that guarantees a clean start.
    ///
    /// The Vision Pro cannot reliably switch directly from one playing video to
    /// another — it must be fully stopped first (which also tears down and
    /// reopens the immersive space). This helper automates the "stop, then play"
    /// sequence the user previously had to do by hand:
    /// - If the device is currently busy (playing/paused/loading), it sends a
    ///   `stop`, waits briefly for the immersive space to close, then sends `play`.
    /// - Otherwise it plays immediately.
    func playSelected(deviceId: String, videoUrl: String, format: VideoFormat) {
        guard !videoUrl.isEmpty else { return }
        guard let device = devices.first(where: { $0.deviceId == deviceId }) else { return }
        
        let currentState = device.state.playbackState
        let isBusy = currentState == .playing || currentState == .paused || currentState == .loading
        
        guard isBusy else {
            // Nothing playing — start right away.
            play(deviceId: deviceId, videoUrl: videoUrl, format: format)
            return
        }
        
        // Stop the current video for a clean switch.
        log("Switching video — stopping current playback first", type: .info)
        stop(deviceId: deviceId)
        
        // Optimistically reflect the stopped state so the UI updates immediately
        // instead of waiting for the device's status broadcast.
        device.state.playbackState = .stopped
        objectWillChange.send()
        
        // Give the Vision Pro time to dismiss the immersive space before the new
        // play command arrives, so it opens a fresh space for the next video.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000) // 1.2s
            self?.play(deviceId: deviceId, videoUrl: videoUrl, format: format)
        }
    }
    
    /// Send pause command to device
    func pause(deviceId: String) {
        let command = CommandMessage(action: .pause)
        webSocketServer.sendCommand(to: deviceId, command: command)
        log("Pause command sent to \(deviceName(for: deviceId))", type: .info)
    }
    
    /// Send resume command to device
    func resume(deviceId: String) {
        let command = CommandMessage(action: .resume)
        webSocketServer.sendCommand(to: deviceId, command: command)
        log("Resume command sent to \(deviceName(for: deviceId))", type: .info)
    }
    
    /// Send stop command to device
    func stop(deviceId: String) {
        let command = CommandMessage(action: .stop)
        webSocketServer.sendCommand(to: deviceId, command: command)
        log("Stop command sent to \(deviceName(for: deviceId))", type: .info)
    }
    
    /// Send stop command to all devices
    func stopAll() {
        let command = CommandMessage(action: .stop)
        webSocketServer.sendCommandToAll(command: command)
        log("Stop command sent to all devices", type: .info)
    }
    
    /// Send transfer command to device (for video download)
    func sendTransferCommand(to deviceId: String, command: TransferCommand) {
        webSocketServer.sendTransferCommand(to: deviceId, command: command)
        log("📤 Transfer command sent: \(command.filename)", type: .info)
    }
    
    /// Asks a headset to start or stop reporting where its wearer is looking.
    ///
    /// Off by default: a headset nobody is previewing sends nothing, so the
    /// control channel carries exactly the traffic it always did.
    func setPreviewSubscription(deviceId: String, enabled: Bool) {
        guard previewSubscriptions.contains(deviceId) != enabled else { return }

        if enabled {
            previewSubscriptions.insert(deviceId)
        } else {
            previewSubscriptions.remove(deviceId)
            devices.first(where: { $0.deviceId == deviceId })?.state.viewer = nil
        }

        webSocketServer.send(to: deviceId, message: PreviewSubscribeCommand(enabled: enabled))
        log("Preview \(enabled ? "started" : "stopped") for \(deviceName(for: deviceId))", type: .info)
    }

    /// Send delete video command to device
    func deleteVideo(deviceId: String, filename: String) {
        let command = DeleteVideoCommand(filename: filename)
        webSocketServer.sendDeleteVideoCommand(to: deviceId, command: command)
        log("🗑️ Delete command sent: \(filename)", type: .info)
    }
    
    // MARK: - Helpers
    
    private func deviceName(for deviceId: String) -> String {
        devices.first(where: { $0.deviceId == deviceId })?.deviceName ?? "Unknown"
    }
    
    private func setupBindings() {
        // Bind server state
        webSocketServer.$isRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] running in
                self?.isServerRunning = running
                if running {
                    self?.log("✅ Server started on port \(String(format: "%d", self?.serverPort ?? 8080))", type: .success)
                }
            }
            .store(in: &cancellables)
        
        webSocketServer.$port
            .receive(on: DispatchQueue.main)
            .assign(to: &$serverPort)
        
        webSocketServer.$connectionCount
            .receive(on: DispatchQueue.main)
            .assign(to: &$connectionCount)

        // Keep the advertised TXT record honest about the file-transfer port:
        // the HTTP listener may land on a different port than the 8081 default.
        fileTransferServer.$port
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] httpPort in
                guard let self = self else { return }
                self.webSocketServer.fileTransferPort = httpPort
                self.webSocketServer.refreshAdvertisement()
            }
            .store(in: &cancellables)
    }
    
    private func setupCallbacks() {
        // Handle new device registration
        webSocketServer.onDeviceRegistered = { [weak self] connection, message in
            Task { @MainActor in
                guard let self = self else { return }
                
                // Check if device already exists
                if let existing = self.devices.first(where: { $0.deviceId == message.deviceId }) {
                    existing.deviceName = message.deviceName
                    self.log("Device reconnected: \(message.deviceName)", type: .info)
                } else {
                    let device = ConnectedDevice(
                        deviceId: message.deviceId,
                        deviceName: message.deviceName,
                        connection: connection
                    )
                    self.devices.append(device)
                    self.log("✅ New device connected: \(message.deviceName)", type: .success)
                }
            }
        }
        
        // Handle status updates
        webSocketServer.onStatusUpdate = { [weak self] deviceId, message in
            Task { @MainActor in
                guard let self = self,
                      let device = self.devices.first(where: { $0.deviceId == deviceId }) else { return }
                
                device.state.playbackState = PlaybackState(rawValue: message.state) ?? .unknown
                device.state.currentVideo = message.currentVideo
                device.state.immersiveMode = message.immersiveMode
                device.state.currentTime = message.currentTime ?? 0
                // Keep the last reported duration when a message omits it, so a
                // headset on an older build simply leaves it nil rather than
                // clearing a value we already learned.
                if let reported = message.duration, reported.isFinite, reported > 0 {
                    device.state.duration = reported
                }

                // Let an active sync session react (e.g. end when all devices finish)
                self.syncManager.handleDeviceStatus(deviceId: deviceId, state: device.state.playbackState)

                // Trigger UI update
                self.objectWillChange.send()
            }
        }
        
        // Handle local videos
        webSocketServer.onLocalVideos = { [weak self] deviceId, videos in
            Task { @MainActor in
                guard let self = self,
                      let device = self.devices.first(where: { $0.deviceId == deviceId }) else { return }
                
                device.localVideos = videos
                self.log("\(device.deviceName): \(videos.count) local video(s) found", type: .info)
                
                // Trigger UI update
                self.objectWillChange.send()
            }
        }
        
        // Handle viewer look direction (only arrives while a preview is open)
        webSocketServer.onViewerState = { [weak self] deviceId, message in
            Task { @MainActor in
                guard let self = self,
                      let device = self.devices.first(where: { $0.deviceId == deviceId }) else { return }

                // Smooth the pose: raw head tracking jitters a degree or two at
                // rest, which reads as a twitching indicator.
                let alpha = 0.35
                let previous = device.state.viewer
                let smoothedYaw = previous.map { $0.yaw + alpha * shortestAngleDelta(from: $0.yaw, to: message.yaw) } ?? message.yaw
                let smoothedPitch = previous.map { $0.pitch + alpha * (message.pitch - $0.pitch) } ?? message.pitch

                device.state.viewer = ViewerLook(
                    yaw: smoothedYaw,
                    pitch: smoothedPitch,
                    mediaTime: message.mediaTime,
                    receivedAt: Date()
                )
                device.objectWillChange.send()
            }
        }

        // Handle disconnection
        webSocketServer.onDeviceDisconnected = { [weak self] deviceId in
            Task { @MainActor in
                guard let self = self else { return }
                
                if let index = self.devices.firstIndex(where: { $0.deviceId == deviceId }) {
                    let deviceName = self.devices[index].deviceName
                    self.devices.remove(at: index)
                    self.log("Device disconnected: \(deviceName)", type: .warning)
                }

                // Keep any active sync session consistent
                self.syncManager.handleDeviceDisconnected(deviceId: deviceId)
            }
        }
        
        // Handle transfer progress
        webSocketServer.onTransferProgress = { [weak self] deviceId, message in
            Task { @MainActor in
                guard let self = self else { return }
                
                let statusEmoji: String
                switch message.status {
                case .started:
                    statusEmoji = "📥"
                case .downloading:
                    statusEmoji = "⏳"
                case .completed:
                    statusEmoji = "✅"
                case .failed:
                    statusEmoji = "❌"
                }
                
                let progress = Int(message.progress * 100)
                
                if message.status == .completed {
                    self.log("\(statusEmoji) Transfer complete: \(message.filename)", type: .success)
                } else if message.status == .failed {
                    self.log("\(statusEmoji) Transfer failed: \(message.filename)", type: .error)
                } else if progress % 25 == 0 && progress > 0 {
                    // Only log at 25%, 50%, 75%
                    self.log("\(statusEmoji) Downloading \(message.filename): \(progress)%", type: .info)
                }
            }
        }
        
        // Handle delete video response
        webSocketServer.onDeleteVideoResponse = { [weak self] deviceId, response in
            Task { @MainActor in
                guard let self = self else { return }
                
                if response.success {
                    self.log("✅ Deleted: \(response.filename)", type: .success)
                } else {
                    self.log("❌ Delete failed: \(response.filename) - \(response.message ?? "Unknown error")", type: .error)
                }
            }
        }
    }
    
    // MARK: - Logging
    
    func log(_ message: String, type: LogType) {
        let entry = LogEntry(message: message, type: type)
        logs.append(entry)
        
        // Keep only last 100 logs
        if logs.count > 100 {
            logs.removeFirst()
        }
        
        print("[DeviceManager] \(message)")
    }
    
    func clearLogs() {
        logs.removeAll()
    }
}

/// Shortest signed rotation between two angles, so smoothing across the ±π
/// wrap-around does not spin the indicator the long way round.
func shortestAngleDelta(from: Double, to: Double) -> Double {
    var delta = to - from
    while delta > .pi { delta -= 2 * .pi }
    while delta < -.pi { delta += 2 * .pi }
    return delta
}

// MARK: - Log Entry

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let message: String
    let type: LogType
    
    var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: timestamp)
    }
}

enum LogType {
    case info
    case success
    case warning
    case error
}
