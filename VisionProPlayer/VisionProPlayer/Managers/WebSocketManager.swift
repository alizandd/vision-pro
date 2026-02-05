import Foundation
import Combine

/// Manages WebSocket connection to the relay server.
/// Handles connection, reconnection, and message parsing.
@MainActor
class WebSocketManager: ObservableObject {
    /// Connection state
    @Published var isConnected: Bool = false
    @Published var connectionState: ConnectionState = .disconnected
    @Published var lastMessage: String?

    /// Callback for handling commands
    var onCommand: ((ServerCommand) -> Void)?

    /// WebSocket task
    nonisolated(unsafe) private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?

    /// Reconnection settings
    private var reconnectAttempts: Int = 0
    private let maxReconnectAttempts: Int = 10
    private var isManuallyDisconnected: Bool = false
    nonisolated(unsafe) private var reconnectTask: Task<Void, Never>?
    nonisolated(unsafe) private var receiveTask: Task<Void, Never>?
    nonisolated(unsafe) private var heartbeatTask: Task<Void, Never>?

    /// Device info
    private let deviceId: String
    private var deviceName: String { AppConfiguration.deviceName }

    /// Connection states
    enum ConnectionState: String {
        case disconnected
        case connecting
        case connected
        case reconnecting
    }

    init() {
        // Get or create device ID
        if let storedId = UserDefaults.standard.string(forKey: "device_id") {
            self.deviceId = storedId
        } else {
            let newId = UUID().uuidString
            UserDefaults.standard.set(newId, forKey: "device_id")
            self.deviceId = newId
        }

        // Configure URL session
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        self.urlSession = URLSession(configuration: config)
    }

    deinit {
        disconnect()
    }

    // MARK: - Connection Management

    /// Connects to the WebSocket server
    func connect() {
        guard connectionState != .connecting && connectionState != .connected else {
            print("[WebSocket] Already connected or connecting")
            return
        }

        isManuallyDisconnected = false
        connectionState = .connecting

        let serverURL = AppConfiguration.serverURL
        guard let url = URL(string: serverURL) else {
            print("[WebSocket] Invalid server URL: \(serverURL)")
            connectionState = .disconnected
            return
        }

        print("[WebSocket] Connecting to \(serverURL)...")

        webSocketTask = urlSession?.webSocketTask(with: url)
        webSocketTask?.resume()

        // Start receiving messages
        startReceiving()

        // Connection is considered established when we receive the welcome message
        // Timeout after 10 seconds if no welcome message received
        Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            if connectionState == .connecting {
                print("[WebSocket] Connection timeout - no welcome message received")
                connectionState = .disconnected
                isConnected = false
                webSocketTask?.cancel(with: .normalClosure, reason: nil)
                webSocketTask = nil
            }
        }
    }

    /// Disconnects from the WebSocket server
    nonisolated func disconnect() {
        // Cancel tasks and close websocket (can be done from any context)
        // These are marked nonisolated(unsafe) as cancellation is thread-safe
        reconnectTask?.cancel()
        receiveTask?.cancel()
        heartbeatTask?.cancel()
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        
        // Update state on MainActor
        Task { @MainActor in
            isManuallyDisconnected = true
            connectionState = .disconnected
            isConnected = false
            reconnectAttempts = 0
            print("[WebSocket] Disconnected")
        }
    }

    /// Handles successful connection
    private func handleConnected() {
        connectionState = .connected
        isConnected = true
        reconnectAttempts = 0
        print("[WebSocket] Connected")

        // Register with server
        register()
        
        // Start heartbeat to keep connection alive
        startHeartbeat()
    }

    /// Handles connection loss
    private func handleDisconnect() {
        guard !isManuallyDisconnected else { return }

        connectionState = .disconnected
        isConnected = false
        
        // Stop heartbeat
        heartbeatTask?.cancel()

        // Attempt reconnection
        scheduleReconnect()
    }

    /// Schedules a reconnection attempt with exponential backoff
    private func scheduleReconnect() {
        guard !isManuallyDisconnected else { return }
        guard reconnectAttempts < maxReconnectAttempts else {
            print("[WebSocket] Max reconnection attempts reached")
            return
        }

        connectionState = .reconnecting
        reconnectAttempts += 1

        // Exponential backoff: 1s, 2s, 4s, 8s, 16s, etc., max 30s
        let delay = min(pow(2.0, Double(reconnectAttempts - 1)), 30.0)
        print("[WebSocket] Reconnecting in \(delay)s (attempt \(reconnectAttempts)/\(maxReconnectAttempts))...")

        reconnectTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if !Task.isCancelled && !isManuallyDisconnected {
                connect()
            }
        }
    }

    // MARK: - Message Handling

    /// Starts the message receiving loop
    private func startReceiving() {
        receiveTask = Task {
            while !Task.isCancelled {
                do {
                    guard let task = webSocketTask else { break }
                    let message = try await task.receive()

                    switch message {
                    case .string(let text):
                        await handleMessage(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            await handleMessage(text)
                        }
                    @unknown default:
                        break
                    }
                } catch {
                    if !Task.isCancelled {
                        print("[WebSocket] Receive error: \(error)")
                        await handleDisconnect()
                    }
                    break
                }
            }
        }
    }

    /// Handles incoming WebSocket messages
    private func handleMessage(_ text: String) async {
        lastMessage = text
        print("[WebSocket] Received: \(text)")

        guard let data = text.data(using: .utf8) else { return }

        // Try to parse as different message types
        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let messageType = json?["type"] as? String else { return }

            switch messageType {
            case "welcome":
                let welcome = try JSONDecoder().decode(WelcomeMessage.self, from: data)
                print("[WebSocket] Server: \(welcome.message)")
                await handleConnected()

            case "registered":
                let registered = try JSONDecoder().decode(RegisteredMessage.self, from: data)
                print("[WebSocket] Registered: \(registered.message)")

            case "command":
                // Log raw JSON for debugging
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("[WebSocket] Raw command JSON: \(jsonString)")
                }
                let command = try JSONDecoder().decode(ServerCommand.self, from: data)
                print("[WebSocket] Command: \(command.action), Format: \(command.videoFormat?.displayName ?? "nil")")
                onCommand?(command)

            case "error":
                let error = try JSONDecoder().decode(ErrorMessage.self, from: data)
                print("[WebSocket] Server error: \(error.message)")

            case "pong":
                // Heartbeat response
                break

            default:
                print("[WebSocket] Unknown message type: \(messageType)")
            }
        } catch {
            print("[WebSocket] Failed to parse message: \(error)")
        }
    }

    // MARK: - Sending Messages

    /// Sends a message to the server
    func send(_ message: Encodable) {
        guard let webSocketTask = webSocketTask, isConnected else {
            print("[WebSocket] Cannot send - not connected (isConnected: \(isConnected))")
            return
        }

        do {
            let data = try JSONEncoder().encode(message)
            guard let text = String(data: data, encoding: .utf8) else {
                print("[WebSocket] Failed to convert data to string")
                return
            }

            print("[WebSocket] Sending message: \(text)")
            webSocketTask.send(.string(text)) { error in
                if let error = error {
                    print("[WebSocket] Send error: \(error)")
                } else {
                    print("[WebSocket] Message sent successfully")
                }
            }
        } catch {
            print("[WebSocket] Encoding error: \(error)")
        }
    }

    /// Registers this device with the server
    private func register() {
        let registration = RegistrationMessage(
            deviceId: deviceId,
            deviceName: deviceName
        )
        print("[WebSocket] Registering device: \(deviceName) with ID: \(deviceId)")
        send(registration)
        print("[WebSocket] Sent registration message")
    }

    /// Sends a status update to the server
    func sendStatus(state: String, currentVideo: String?, immersiveMode: Bool, currentTime: Double? = nil) {
        let status = StatusMessage(
            deviceId: deviceId,
            deviceName: deviceName,
            state: state,
            currentVideo: currentVideo,
            immersiveMode: immersiveMode,
            currentTime: currentTime
        )
        send(status)
    }
    
    /// Sends the list of local videos to the server
    func sendLocalVideos(_ videos: [LocalVideo]) {
        let message = LocalVideosMessage(
            deviceId: deviceId,
            videos: videos
        )
        print("[WebSocket] Sending \(videos.count) local videos to server")
        send(message)
    }

    /// Starts periodic heartbeat to keep connection alive
    private func startHeartbeat() {
        // Cancel any existing heartbeat
        heartbeatTask?.cancel()
        
        heartbeatTask = Task {
            while !Task.isCancelled {
                // Send ping every 30 seconds
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                
                if !Task.isCancelled && isConnected {
                    await sendPing()
                }
            }
        }
        print("[WebSocket] Heartbeat started")
    }
    
    /// Sends a ping to keep the connection alive
    func sendPing() async {
        guard let webSocketTask = webSocketTask else { return }

        await withCheckedContinuation { continuation in
            webSocketTask.sendPing { error in
                if let error = error {
                    print("[WebSocket] Ping error: \(error)")
                    Task { @MainActor in
                        self.handleDisconnect()
                    }
                } else {
                    print("[WebSocket] Ping sent successfully")
                }
                continuation.resume()
            }
        }
    }

    // MARK: - Configuration

    /// Updates the server URL (requires reconnection)
    func updateServerURL(_ url: String) {
        AppConfiguration.serverURL = url
        if isConnected {
            disconnect()
            connect()
        }
    }
}

// Make StatusMessage and RegistrationMessage encodable wrappers
extension RegistrationMessage {
    enum CodingKeys: String, CodingKey {
        case type, deviceId, deviceName, deviceType
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(deviceId, forKey: .deviceId)
        try container.encode(deviceName, forKey: .deviceName)
        try container.encode(deviceType, forKey: .deviceType)
    }
}

extension StatusMessage {
    enum CodingKeys: String, CodingKey {
        case type, deviceId, deviceName, state, currentVideo, immersiveMode, currentTime
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(deviceId, forKey: .deviceId)
        try container.encode(deviceName, forKey: .deviceName)
        try container.encode(state, forKey: .state)
        try container.encode(currentVideo, forKey: .currentVideo)
        try container.encode(immersiveMode, forKey: .immersiveMode)
        try container.encode(currentTime, forKey: .currentTime)
    }
}

extension LocalVideosMessage {
    enum CodingKeys: String, CodingKey {
        case type, deviceId, videos
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(deviceId, forKey: .deviceId)
        try container.encode(videos, forKey: .videos)
    }
}
