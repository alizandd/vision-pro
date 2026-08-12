import Foundation
import Network
import UIKit

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

/// WebSocket Server using Network framework with Bonjour advertising
@MainActor
class WebSocketServer: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var port: UInt16 = 8080
    @Published var connectionCount: Int = 0
    /// True while the `_visionproctl._tcp` record is published. This listener is
    /// the single advertiser for the controller — nothing else may publish the
    /// service or bind this port.
    @Published var isAdvertising: Bool = false
    
    private var listener: NWListener?
    private var connections: [String: ClientConnection] = [:]
    
    // Bonjour service advertising
    private let bonjourServiceType = "_visionproctl._tcp"
    private var serviceName: String {
        UIDevice.current.name
    }

    /// Port of the companion HTTP file-transfer server, published in the TXT
    /// record so the Vision Pro never has to assume 8081.
    var fileTransferPort: UInt16 = 8081

    /// Version of the controller protocol carried in the TXT record, so a
    /// headset can refuse a controller it is too old to talk to.
    static let protocolVersion = 1

    /// Stable identity for this controller, persisted so a headset can keep
    /// following the same controller across restarts and IP changes.
    static var controllerId: String {
        let key = "controller_id"
        if let stored = UserDefaults.standard.string(forKey: key) {
            return stored
        }
        let created = UUID().uuidString
        UserDefaults.standard.set(created, forKey: key)
        return created
    }

    /// TXT record advertised alongside the service.
    ///
    /// Keys: `name` (human-readable controller name), `ws` (WebSocket port),
    /// `http` (file-transfer port), `v` (protocol version), `id` (stable id).
    private func makeTXTRecord() -> NWTXTRecord {
        var txt = NWTXTRecord()
        txt["name"] = serviceName
        txt["ws"] = String(port)
        txt["http"] = String(fileTransferPort)
        txt["v"] = String(Self.protocolVersion)
        txt["id"] = Self.controllerId
        return txt
    }

    /// Re-publishes the TXT record — call after the service name or a port changes.
    func refreshAdvertisement() {
        guard listener != nil else { return }
        listener?.service = NWListener.Service(
            name: serviceName,
            type: bonjourServiceType,
            txtRecord: makeTXTRecord()
        )
        print("[WebSocketServer] 📡 Bonjour TXT refreshed: name=\(serviceName) ws=\(port) http=\(fileTransferPort) v=\(Self.protocolVersion)")
    }
    
    /// Callback when a new device registers
    var onDeviceRegistered: ((ClientConnection, RegistrationMessage) -> Void)?
    
    /// Callback when a device sends status update
    var onStatusUpdate: ((String, StatusMessage) -> Void)?
    
    /// Callback when a device sends local videos
    var onLocalVideos: ((String, [LocalVideo]) -> Void)?
    
    /// Callback when a device sends transfer progress
    var onTransferProgress: ((String, TransferProgressMessage) -> Void)?
    
    /// Callback when a device sends delete response
    var onDeleteVideoResponse: ((String, DeleteVideoResponse) -> Void)?
    
    /// Callback when a device replies to a clock sync request
    var onClockSyncResponse: ((String, ClockSyncResponse) -> Void)?

    /// Callback when a device reports sync readiness
    var onSyncReady: ((String, SyncReadyMessage) -> Void)?

    /// Callback when a device reports where its wearer is looking
    var onViewerState: ((String, ViewerStateMessage) -> Void)?

    /// Callback when a device disconnects
    var onDeviceDisconnected: ((String) -> Void)?
    
    init() {}
    
    /// Start the WebSocket server with Bonjour advertising
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
            
            // Enable Bonjour advertising so Vision Pro can auto-discover this
            // controller. The TXT record carries the identity and both ports, so
            // the headset needs no hardcoded assumptions.
            listener?.service = NWListener.Service(
                name: serviceName,
                type: bonjourServiceType,
                txtRecord: makeTXTRecord()
            )
            
            listener?.serviceRegistrationUpdateHandler = { [weak self] serviceChange in
                Task { @MainActor in
                    switch serviceChange {
                    case .add(let endpoint):
                        self?.isAdvertising = true
                        if case .service(let name, let type, _, _) = endpoint {
                            print("[WebSocketServer] 📡 Bonjour service registered: \(name) (\(type))")
                        }
                    case .remove(let endpoint):
                        self?.isAdvertising = false
                        if case .service(let name, _, _, _) = endpoint {
                            print("[WebSocketServer] Bonjour service removed: \(name)")
                        }
                    @unknown default:
                        break
                    }
                }
            }
            
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
            print("[WebSocketServer] Starting on port \(port) with Bonjour advertising...")
            
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
    
    /// Best connection for a device: prefer one whose socket is ready.
    private func liveConnection(for deviceId: String) -> ClientConnection? {
        let candidates = connections.values.filter { $0.deviceId == deviceId }
        return candidates.first(where: { $0.connection.state == .ready }) ?? candidates.first
    }

    /// Send command to a specific device
    func sendCommand(to deviceId: String, command: CommandMessage) {
        guard let client = liveConnection(for: deviceId) else {
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
    
    /// Send any encodable message to a specific device (used by sync playback)
    func send<T: Encodable>(to deviceId: String, message: T) {
        guard let client = liveConnection(for: deviceId) else {
            print("[WebSocketServer] Device not found: \(deviceId)")
            return
        }

        sendMessage(message, to: client)
    }

    /// Send transfer command to a specific device
    func sendTransferCommand(to deviceId: String, command: TransferCommand) {
        guard let client = liveConnection(for: deviceId) else {
            print("[WebSocketServer] Device not found: \(deviceId)")
            return
        }
        
        sendMessage(command, to: client)
    }
    
    /// Send delete video command to a specific device
    func sendDeleteVideoCommand(to deviceId: String, command: DeleteVideoCommand) {
        guard let client = liveConnection(for: deviceId) else {
            print("[WebSocketServer] Device not found: \(deviceId)")
            return
        }
        
        sendMessage(command, to: client)
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
            print("[WebSocketServer] 📡 Bonjour: advertising as '\(serviceName)' on \(bonjourServiceType)")
        case .failed(let error):
            isRunning = false
            isAdvertising = false
            print("[WebSocketServer] ❌ Server failed: \(error)")
        case .cancelled:
            isRunning = false
            isAdvertising = false
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
        // Already removed (e.g. replaced by a re-registration) — nothing to do.
        guard connections.removeValue(forKey: client.id) != nil else { return }
        connectionCount = connections.count

        // Only report the device as gone when NO other connection carries the
        // same deviceId — a dying stale connection must not remove a device
        // that reconnected on a fresh socket.
        if let deviceId = client.deviceId,
           !connections.values.contains(where: { $0.deviceId == deviceId }) {
            onDeviceDisconnected?(deviceId)
        }
    }
    
    private func receiveMessage(from client: ClientConnection) {
        client.connection.receiveMessage { [weak self] content, context, isComplete, error in
            Task { @MainActor in
                if let error = error {
                    print("[WebSocketServer] Receive error: \(error)")
                    // A dead receive loop means a dead connection — clean it up
                    // instead of leaving a zombie entry in `connections`.
                    client.connection.cancel()
                    self?.removeConnection(client)
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
                
            case "transferProgress":
                let message = try JSONDecoder().decode(TransferProgressMessage.self, from: data)
                if let deviceId = client.deviceId {
                    onTransferProgress?(deviceId, message)
                }
                
            case "deleteVideoResponse":
                let response = try JSONDecoder().decode(DeleteVideoResponse.self, from: data)
                if let deviceId = client.deviceId {
                    onDeleteVideoResponse?(deviceId, response)
                }
                
            case "clockSyncResponse":
                let response = try JSONDecoder().decode(ClockSyncResponse.self, from: data)
                if let deviceId = client.deviceId {
                    onClockSyncResponse?(deviceId, response)
                }

            case "syncReady":
                let ready = try JSONDecoder().decode(SyncReadyMessage.self, from: data)
                if let deviceId = client.deviceId {
                    onSyncReady?(deviceId, ready)
                }

            case "viewerState":
                let viewer = try JSONDecoder().decode(ViewerStateMessage.self, from: data)
                if let deviceId = client.deviceId {
                    onViewerState?(deviceId, viewer)
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
        // Replace any older connection for this deviceId: remove it from the
        // table FIRST (so its cancellation is a no-op in removeConnection),
        // then cancel it. Otherwise stale sockets accumulate and sends may be
        // routed to a dead connection, whose failure would then remove the
        // live device.
        let duplicates = connections.values.filter { $0.deviceId == message.deviceId && $0.id != client.id }
        for duplicate in duplicates {
            print("[WebSocketServer] Replacing stale connection \(duplicate.id) for device \(message.deviceId)")
            connections.removeValue(forKey: duplicate.id)
            duplicate.connection.cancel()
        }
        connectionCount = connections.count

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
