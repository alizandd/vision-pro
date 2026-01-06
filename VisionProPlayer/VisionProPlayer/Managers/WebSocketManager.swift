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
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?

    /// Reconnection settings
    private var reconnectAttempts: Int = 0
    private let maxReconnectAttempts: Int = 10
    private var isManuallyDisconnected: Bool = false
    private var reconnectTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?

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

        // The connection is considered established when we receive the welcome message
        // For now, mark as connected after a brief delay
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if connectionState == .connecting {
                await handleConnected()
            }
        }
    }

    /// Disconnects from the WebSocket server
    func disconnect() {
        isManuallyDisconnected = true
        reconnectTask?.cancel()
        receiveTask?.cancel()
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        connectionState = .disconnected
        isConnected = false
        reconnectAttempts = 0
        print("[WebSocket] Disconnected")
    }

    /// Handles successful connection
    private func handleConnected() {
        connectionState = .connected
        isConnected = true
        reconnectAttempts = 0
        print("[WebSocket] Connected")

        // Register with server
        register()
    }

    /// Handles connection loss
    private func handleDisconnect() {
        guard !isManuallyDisconnected else { return }

        connectionState = .disconnected
        isConnected = false

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
                let command = try JSONDecoder().decode(ServerCommand.self, from: data)
                print("[WebSocket] Command: \(command.action)")
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
            print("[WebSocket] Cannot send - not connected")
            return
        }

        do {
            let data = try JSONEncoder().encode(message)
            guard let text = String(data: data, encoding: .utf8) else { return }

            webSocketTask.send(.string(text)) { error in
                if let error = error {
                    print("[WebSocket] Send error: \(error)")
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
        send(registration)
        print("[WebSocket] Sent registration")
    }

    /// Sends a status update to the server
    func sendStatus(state: String, currentVideo: String?, immersiveMode: Bool) {
        let status = StatusMessage(
            deviceId: deviceId,
            deviceName: deviceName,
            state: state,
            currentVideo: currentVideo,
            immersiveMode: immersiveMode
        )
        send(status)
    }

    /// Sends a ping to keep the connection alive
    func sendPing() {
        guard let webSocketTask = webSocketTask else { return }

        webSocketTask.sendPing { error in
            if let error = error {
                print("[WebSocket] Ping error: \(error)")
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
        case type, deviceId, deviceName, state, currentVideo, immersiveMode
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(deviceId, forKey: .deviceId)
        try container.encode(deviceName, forKey: .deviceName)
        try container.encode(state, forKey: .state)
        try container.encode(currentVideo, forKey: .currentVideo)
        try container.encode(immersiveMode, forKey: .immersiveMode)
    }
}
