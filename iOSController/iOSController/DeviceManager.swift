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
    private let bonjourService = BonjourService()
    let fileTransferServer = FileTransferServer()
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupBindings()
        setupCallbacks()
    }
    
    // MARK: - Server Control
    
    /// Start the server and Bonjour advertising
    func startServer() {
        log("Starting server...", type: .info)
        webSocketServer.start()
        fileTransferServer.start()
        
        // Start Bonjour advertising after a small delay to ensure server is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            self.bonjourService.startAdvertising(port: self.serverPort)
        }
    }
    
    /// Stop the server
    func stopServer() {
        log("Stopping server...", type: .info)
        bonjourService.stopAdvertising()
        webSocketServer.stop()
        fileTransferServer.stop()
        devices.removeAll()
    }
    
    // MARK: - Commands
    
    /// Send play command to device
    func play(deviceId: String, videoUrl: String, format: VideoFormat) {
        let command = CommandMessage(action: .play, videoUrl: videoUrl, videoFormat: format)
        webSocketServer.sendCommand(to: deviceId, command: command)
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
        
        // Handle disconnection
        webSocketServer.onDeviceDisconnected = { [weak self] deviceId in
            Task { @MainActor in
                guard let self = self else { return }
                
                if let index = self.devices.firstIndex(where: { $0.deviceId == deviceId }) {
                    let deviceName = self.devices[index].deviceName
                    self.devices.remove(at: index)
                    self.log("Device disconnected: \(deviceName)", type: .warning)
                }
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
