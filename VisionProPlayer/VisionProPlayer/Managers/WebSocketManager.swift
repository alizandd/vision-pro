import Foundation
import Combine
import Network

/// Manages WebSocket connection to the relay server.
/// Handles connection, reconnection, and message parsing.
@MainActor
class WebSocketManager: ObservableObject {
    /// True once a controller has asked for viewer-state updates. Until then
    /// nothing is published, so headsets nobody is watching stay silent.
    @Published var isPreviewSubscribed: Bool = false

    /// Connection state
    @Published var isConnected: Bool = false
    @Published var connectionState: ConnectionState = .disconnected
    @Published var lastMessage: String?

    /// Callback for handling commands
    var onCommand: ((ServerCommand) -> Void)?
    
    /// Callback for handling download commands
    var onDownloadCommand: ((DownloadCommand) -> Void)?
    
    /// Callback for handling delete video commands
    var onDeleteVideoCommand: ((DeleteVideoCommand) -> Void)?

    /// Callbacks for synchronized playback commands
    var onSyncPrepareCommand: ((SyncPrepareCommand) -> Void)?
    var onSyncStartCommand: ((SyncStartCommand) -> Void)?
    var onSyncResumeCommand: ((SyncResumeCommand) -> Void)?
    var onSeekCommand: ((SeekCommand) -> Void)?

    /// WebSocket task
    nonisolated(unsafe) private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?

    /// Asks the app to re-run Bonjour discovery because the stored address looks
    /// stale. Set by the app; the manager itself knows nothing about Bonjour.
    var onRediscoveryNeeded: (() -> Void)?

    /// Reconnection settings
    private var reconnectAttempts: Int = 0
    /// After this many consecutive failures the address is treated as suspect
    /// and discovery is asked for a fresh one. There is deliberately no attempt
    /// ceiling: giving up permanently is what left headsets dead until relaunch.
    private let attemptsBeforeRediscovery: Int = 3
    private var isManuallyDisconnected: Bool = false

    /// Watches for the headset rejoining WiFi so a reconnect can be immediate
    /// rather than waiting out the backoff.
    private let pathMonitor = NWPathMonitor()
    private var isNetworkAvailable: Bool = true
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
        // Stable per-install id, shared with AppConfiguration so the two can't
        // drift apart (the default device name is derived from it).
        self.deviceId = AppConfiguration.deviceIdentifier

        // Configure URL session
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        self.urlSession = URLSession(configuration: config)

        startPathMonitoring()
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
        guard !serverURL.isEmpty else {
            // Nothing to connect to yet — Bonjour discovery will supply the
            // controller and drive the connection.
            print("[WebSocket] No controller known yet — waiting for Bonjour discovery")
            connectionState = .disconnected
            return
        }
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

    /// Schedules a reconnection attempt with exponential backoff.
    ///
    /// Retrying forever against a cached address is what broke reconnection when
    /// the controller came back on a different DHCP lease, so once a few
    /// attempts have failed this asks discovery for a fresh address instead of
    /// continuing to dial a dead one — and it never stops trying while the
    /// network is up.
    private func scheduleReconnect() {
        guard !isManuallyDisconnected else { return }
        guard isNetworkAvailable else {
            print("[WebSocket] Network unavailable — waiting for it to come back")
            connectionState = .disconnected
            return
        }

        connectionState = .reconnecting
        reconnectAttempts += 1

        if reconnectAttempts >= attemptsBeforeRediscovery {
            print("[WebSocket] \(reconnectAttempts) failed attempts — asking Bonjour for a fresh address")
            onRediscoveryNeeded?()
        }

        // Exponential backoff: 1s, 2s, 4s, 8s, 16s, capped at 30s.
        let delay = min(pow(2.0, Double(reconnectAttempts - 1)), 30.0)
        print("[WebSocket] Reconnecting in \(delay)s (attempt \(reconnectAttempts))...")

        reconnectTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if !Task.isCancelled && !isManuallyDisconnected {
                connect()
            }
        }
    }

    /// Points the connection at a freshly discovered address and connects,
    /// cancelling any pending backoff. Called when Bonjour resolves the
    /// controller — including when it has moved to a new address.
    func retarget(to url: String) {
        let addressChanged = url != AppConfiguration.serverURL
        AppConfiguration.serverURL = url

        guard addressChanged || !isConnected else { return }

        print("[WebSocket] Retargeting to \(url)")

        // Tear the old socket down without going through disconnect(), whose
        // manual-disconnect flag would suppress the reconnect we want here.
        reconnectTask?.cancel()
        receiveTask?.cancel()
        heartbeatTask?.cancel()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil

        isConnected = false
        connectionState = .disconnected
        isManuallyDisconnected = false
        reconnectAttempts = 0

        connect()
    }

    /// Starts watching network availability so a WiFi rejoin reconnects at once.
    private func startPathMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self = self else { return }
                let available = path.status == .satisfied
                let regained = available && !self.isNetworkAvailable
                self.isNetworkAvailable = available

                guard regained else { return }
                print("[WebSocket] 🌐 Network available again — re-discovering and reconnecting")
                self.reconnectAttempts = 0
                self.onRediscoveryNeeded?()
                if !self.isConnected && !self.isManuallyDisconnected {
                    self.reconnectTask?.cancel()
                    self.connect()
                }
            }
        }
        pathMonitor.start(queue: .main)
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
                
                // Check if it's a download command
                if let actionStr = json?["action"] as? String, actionStr == "download" {
                    let downloadCommand = try JSONDecoder().decode(DownloadCommand.self, from: data)
                    print("[WebSocket] Download command: \(downloadCommand.filename)")
                    onDownloadCommand?(downloadCommand)
                } else if let actionStr = json?["action"] as? String, actionStr == "deleteVideo" {
                    let deleteCommand = try JSONDecoder().decode(DeleteVideoCommand.self, from: data)
                    print("[WebSocket] Delete command: \(deleteCommand.filename)")
                    onDeleteVideoCommand?(deleteCommand)
                } else if let actionStr = json?["action"] as? String, actionStr == "syncPrepare" {
                    let prepareCommand = try JSONDecoder().decode(SyncPrepareCommand.self, from: data)
                    print("[WebSocket] Sync prepare: \(prepareCommand.filename)")
                    onSyncPrepareCommand?(prepareCommand)
                } else if let actionStr = json?["action"] as? String, actionStr == "syncStart" {
                    let startCommand = try JSONDecoder().decode(SyncStartCommand.self, from: data)
                    print("[WebSocket] Sync start at: \(startCommand.startAt)")
                    onSyncStartCommand?(startCommand)
                } else if let actionStr = json?["action"] as? String, actionStr == "previewSubscribe" {
                    let subscribe = try JSONDecoder().decode(PreviewSubscribeCommand.self, from: data)
                    isPreviewSubscribed = subscribe.enabled
                    print("[WebSocket] Preview subscription: \(subscribe.enabled ? "on" : "off")")
                } else if let actionStr = json?["action"] as? String, actionStr == "syncResume" {
                    let resumeCommand = try JSONDecoder().decode(SyncResumeCommand.self, from: data)
                    print("[WebSocket] Sync resume at media time: \(resumeCommand.mediaTime)")
                    onSyncResumeCommand?(resumeCommand)
                } else if let actionStr = json?["action"] as? String, actionStr == "seek" {
                    let seekCommand = try JSONDecoder().decode(SeekCommand.self, from: data)
                    print("[WebSocket] Seek to media time: \(seekCommand.mediaTime)")
                    onSeekCommand?(seekCommand)
                } else {
                    let command = try JSONDecoder().decode(ServerCommand.self, from: data)
                    print("[WebSocket] Command: \(command.action), Format: \(command.videoFormat?.displayName ?? "nil")")
                    onCommand?(command)
                }

            case "error":
                let error = try JSONDecoder().decode(ErrorMessage.self, from: data)
                print("[WebSocket] Server error: \(error.message)")

            case "clockSync":
                // Reply immediately — this is latency-sensitive, so it is
                // handled here rather than routed through a callback.
                let request = try JSONDecoder().decode(ClockSyncMessage.self, from: data)
                let response = ClockSyncResponse(
                    deviceId: deviceId,
                    t0: request.t0,
                    t1: Int64(Date().timeIntervalSince1970 * 1000)
                )
                send(response)

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
    /// - Parameter logging: set false for high-rate telemetry so the log stays
    ///   readable — viewer state alone would otherwise emit 10 lines a second.
    func send(_ message: Encodable, logging: Bool = true) {
        guard let webSocketTask = webSocketTask, isConnected else {
            if logging {
                print("[WebSocket] Cannot send - not connected (isConnected: \(isConnected))")
            }
            return
        }

        do {
            let data = try JSONEncoder().encode(message)
            guard let text = String(data: data, encoding: .utf8) else {
                print("[WebSocket] Failed to convert data to string")
                return
            }

            if logging { print("[WebSocket] Sending message: \(text)") }
            webSocketTask.send(.string(text)) { error in
                if let error = error {
                    print("[WebSocket] Send error: \(error)")
                } else if logging {
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

    /// Re-announces this device's name to the controller.
    ///
    /// Called after a rename so the operator's device list updates at once
    /// instead of waiting for the next reconnect. Re-registering on the live
    /// connection is safe: the controller only replaces *other* connections
    /// holding the same device id, never the one the message arrived on.
    func announceIdentity() {
        guard isConnected else { return }
        print("[WebSocket] Re-announcing identity as '\(deviceName)'")
        register()
    }

    /// Sends a status update to the server
    func sendStatus(state: String, currentVideo: String?, immersiveMode: Bool, currentTime: Double? = nil, duration: Double? = nil) {
        let status = StatusMessage(
            deviceId: deviceId,
            deviceName: deviceName,
            state: state,
            currentVideo: currentVideo,
            immersiveMode: immersiveMode,
            currentTime: currentTime,
            duration: duration
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
    
    /// Sends transfer progress to the server
    func sendTransferProgress(filename: String, progress: Double, bytesDownloaded: Int64, totalBytes: Int64, status: String) {
        let message = TransferProgressMessage(
            deviceId: deviceId,
            filename: filename,
            progress: progress,
            bytesDownloaded: bytesDownloaded,
            totalBytes: totalBytes,
            status: status
        )
        send(message)
    }
    
    /// Publishes where the wearer is looking and where playback is.
    ///
    /// Silently does nothing unless a controller subscribed, so this can be
    /// called from the render loop without gating at every call site.
    func sendViewerState(yaw: Double, pitch: Double, mediaTime: Double) {
        guard isPreviewSubscribed, isConnected else { return }
        let message = ViewerStateMessage(
            deviceId: deviceId,
            yaw: yaw,
            pitch: pitch,
            mediaTime: mediaTime,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000)
        )
        send(message, logging: false)
    }

    /// Sends sync readiness report to the controller
    func sendSyncReady(filename: String, success: Bool, message: String? = nil) {
        let ready = SyncReadyMessage(
            deviceId: deviceId,
            filename: filename,
            success: success,
            message: message
        )
        send(ready)
    }

    /// Sends delete video response to the server
    func sendDeleteVideoResponse(filename: String, success: Bool, message: String?) {
        let response = DeleteVideoResponse(
            deviceId: deviceId,
            filename: filename,
            success: success,
            message: message
        )
        send(response)
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
        case type, deviceId, deviceName, state, currentVideo, immersiveMode, currentTime, duration
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
        try container.encode(duration, forKey: .duration)
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
