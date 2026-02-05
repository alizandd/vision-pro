import Foundation
import Network

/// Represents a client connection
class ClientConnection: Identifiable {
    let id: String
    let connection: NWConnection
    var deviceId: String?
    var deviceName: String?
    var deviceType: String?
    
    init(connection: NWConnection) {
        self.id = UUID().uuidString
        self.connection = connection
    }
}

/// WebSocket Server using Network framework
@MainActor
class WebSocketServer: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var port: UInt16 = 8080
    @Published var connectionCount: Int = 0
    
    private var listener: NWListener?
    private var connections: [String: ClientConnection] = [:]
    
    /// Callback when a new device registers
    var onDeviceRegistered: ((ClientConnection, RegistrationMessage) -> Void)?
    
    /// Callback when a device sends status update
    var onStatusUpdate: ((String, StatusMessage) -> Void)?
    
    /// Callback when a device sends local videos
    var onLocalVideos: ((String, [LocalVideo]) -> Void)?
    
    /// Callback when a device disconnects
    var onDeviceDisconnected: ((String) -> Void)?
    
    init() {}
    
    /// Start the WebSocket server
    func start() {
        guard !isRunning else { return }
        
        do {
            // Create WebSocket parameters
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            
            // Add WebSocket protocol
            let wsOptions = NWProtocolWebSocket.Options()
            wsOptions.autoReplyPing = true
            parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)
            
            // Create listener
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
            
            listener?.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    self?.handleListenerState(state)
                }
            }
            
            listener?.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handleNewConnection(connection)
                }
            }
            
            listener?.start(queue: .main)
            print("[WebSocketServer] Starting on port \(port)...")
            
        } catch {
            print("[WebSocketServer] Failed to start: \(error)")
        }
    }
    
    /// Stop the server
    func stop() {
        print("[WebSocketServer] Stopping server...")
        
        // Send close frame to all connections before cancelling
        for (_, client) in connections {
            // Send WebSocket close frame
            let metadata = NWProtocolWebSocket.Metadata(opcode: .close)
            metadata.closeCode = .protocolCode(.normalClosure)
            let context = NWConnection.ContentContext(identifier: "closeFrame", metadata: [metadata])
            
            client.connection.send(content: nil, contentContext: context, isComplete: true, completion: .contentProcessed { _ in
                // Cancel after sending close frame
                client.connection.cancel()
            })
        }
        
        // Small delay to allow close frames to be sent
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.listener?.cancel()
            self?.listener = nil
            self?.connections.removeAll()
            self?.isRunning = false
            self?.connectionCount = 0
            print("[WebSocketServer] Stopped")
        }
    }
    
    /// Send command to a specific device
    func sendCommand(to deviceId: String, command: CommandMessage) {
        guard let client = connections.values.first(where: { $0.deviceId == deviceId }) else {
            print("[WebSocketServer] Device not found: \(deviceId)")
            return
        }
        
        sendMessage(command, to: client)
    }
    
    /// Send command to all devices
    func sendCommandToAll(command: CommandMessage) {
        for client in connections.values where client.deviceType == "visionpro" {
            sendMessage(command, to: client)
        }
    }
    
    // MARK: - Private Methods
    
    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            isRunning = true
            if let port = listener?.port {
                self.port = port.rawValue
            }
            print("[WebSocketServer] ✅ Server ready on port \(self.port)")
        case .failed(let error):
            isRunning = false
            print("[WebSocketServer] ❌ Server failed: \(error)")
        case .cancelled:
            isRunning = false
            print("[WebSocketServer] Server cancelled")
        default:
            break
        }
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        let client = ClientConnection(connection: connection)
        connections[client.id] = client
        connectionCount = connections.count
        
        print("[WebSocketServer] New connection: \(client.id)")
        
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleConnectionState(state, client: client)
            }
        }
        
        connection.start(queue: .main)
    }
    
    private func handleConnectionState(_ state: NWConnection.State, client: ClientConnection) {
        switch state {
        case .ready:
            print("[WebSocketServer] Connection ready: \(client.id)")
            // Send welcome message
            let welcome = WelcomeMessage()
            sendMessage(welcome, to: client)
            // Start receiving messages
            receiveMessage(from: client)
            
        case .failed(let error):
            print("[WebSocketServer] Connection failed: \(error)")
            removeConnection(client)
            
        case .cancelled:
            print("[WebSocketServer] Connection cancelled: \(client.id)")
            removeConnection(client)
            
        default:
            break
        }
    }
    
    private func removeConnection(_ client: ClientConnection) {
        connections.removeValue(forKey: client.id)
        connectionCount = connections.count
        
        if let deviceId = client.deviceId {
            onDeviceDisconnected?(deviceId)
        }
    }
    
    private func receiveMessage(from client: ClientConnection) {
        client.connection.receiveMessage { [weak self] content, context, isComplete, error in
            Task { @MainActor in
                if let error = error {
                    print("[WebSocketServer] Receive error: \(error)")
                    return
                }
                
                if let content = content, !content.isEmpty {
                    self?.handleMessage(content, from: client)
                }
                
                // Continue receiving if connection is still valid
                if client.connection.state == .ready {
                    self?.receiveMessage(from: client)
                }
            }
        }
    }
    
    private func handleMessage(_ data: Data, from client: ClientConnection) {
        guard let text = String(data: data, encoding: .utf8) else {
            print("[WebSocketServer] Invalid message data")
            return
        }
        
        print("[WebSocketServer] Received: \(text)")
        
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else {
                print("[WebSocketServer] Invalid message format")
                return
            }
            
            switch type {
            case "register":
                let message = try JSONDecoder().decode(RegistrationMessage.self, from: data)
                handleRegistration(message, from: client)
                
            case "status":
                let message = try JSONDecoder().decode(StatusMessage.self, from: data)
                if let deviceId = client.deviceId {
                    onStatusUpdate?(deviceId, message)
                }
                
            case "localVideos":
                let message = try JSONDecoder().decode(LocalVideosMessage.self, from: data)
                if let deviceId = client.deviceId {
                    onLocalVideos?(deviceId, message.videos)
                }
                
            case "ping":
                let pong = ["type": "pong", "timestamp": Int(Date().timeIntervalSince1970 * 1000)] as [String : Any]
                if let data = try? JSONSerialization.data(withJSONObject: pong) {
                    sendData(data, to: client)
                }
                
            default:
                print("[WebSocketServer] Unknown message type: \(type)")
            }
            
        } catch {
            print("[WebSocketServer] Failed to parse message: \(error)")
        }
    }
    
    private func handleRegistration(_ message: RegistrationMessage, from client: ClientConnection) {
        client.deviceId = message.deviceId
        client.deviceName = message.deviceName
        client.deviceType = message.deviceType
        
        print("[WebSocketServer] ✅ Device registered: \(message.deviceName) (\(message.deviceType))")
        
        // Send acknowledgement
        let ack = RegisteredAckMessage(
            deviceId: message.deviceId,
            message: "Successfully registered as \(message.deviceType)"
        )
        sendMessage(ack, to: client)
        
        // Notify delegate
        if message.deviceType == "visionpro" {
            onDeviceRegistered?(client, message)
        }
    }
    
    private func sendMessage<T: Encodable>(_ message: T, to client: ClientConnection) {
        do {
            let data = try JSONEncoder().encode(message)
            sendData(data, to: client)
        } catch {
            print("[WebSocketServer] Failed to encode message: \(error)")
        }
    }
    
    private func sendData(_ data: Data, to client: ClientConnection) {
        // Create WebSocket metadata for text message
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "textMessage", metadata: [metadata])
        
        client.connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { error in
            if let error = error {
                print("[WebSocketServer] Send error: \(error)")
            }
        })
    }
}
