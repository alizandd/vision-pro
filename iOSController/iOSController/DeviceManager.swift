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
        devices.removeAll()
    }
    
    // MARK: - Commands
    
    /// Send play command to device
    func play(deviceId: String, videoUrl: String, format: VideoFormat) {
        let command = CommandMessage(action: .play, videoUrl: videoUrl, videoFormat: format)
        webSocketServer.sendCommand(to: deviceId, command: command)
        log("Play command sent to \(deviceName(for: deviceId))", type: .success)
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
