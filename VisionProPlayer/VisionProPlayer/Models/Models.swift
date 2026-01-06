import Foundation

// MARK: - WebSocket Message Types

/// Represents a command received from the WebSocket server
struct ServerCommand: Codable {
    let type: String
    let action: CommandAction
    let videoUrl: String?
    let timestamp: Int?

    enum CodingKeys: String, CodingKey {
        case type
        case action
        case videoUrl
        case timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        let actionString = try container.decode(String.self, forKey: .action)
        action = CommandAction(rawValue: actionString) ?? .stop
        videoUrl = try container.decodeIfPresent(String.self, forKey: .videoUrl)
        timestamp = try container.decodeIfPresent(Int.self, forKey: .timestamp)
    }
}

/// Supported command actions
enum CommandAction: String, Codable {
    case play
    case pause
    case resume
    case change
    case stop
}

/// Message sent to register with the server
struct RegistrationMessage: Codable {
    let type: String = "register"
    let deviceId: String
    let deviceName: String
    let deviceType: String = "visionpro"
}

/// Status update sent to the server
struct StatusMessage: Codable {
    let type: String = "status"
    let deviceId: String
    let deviceName: String
    let state: String
    let currentVideo: String?
    let immersiveMode: Bool
    let currentTime: Double?
}

/// Welcome message received from server
struct WelcomeMessage: Codable {
    let type: String
    let message: String
    let serverVersion: String?
}

/// Registration acknowledgement from server
struct RegisteredMessage: Codable {
    let type: String
    let deviceId: String
    let message: String
}

/// Error message from server
struct ErrorMessage: Codable {
    let type: String
    let message: String
}

// MARK: - Playback State

/// Video playback states
enum PlaybackState: String {
    case idle
    case loading
    case playing
    case paused
    case stopped
    case error
}

// MARK: - App Configuration

/// App configuration stored in UserDefaults
struct AppConfiguration {
    static let serverURLKey = "websocket_server_url"
    static let deviceNameKey = "device_name"
    static let autoConnectKey = "auto_connect"

    static var serverURL: String {
        get {
            UserDefaults.standard.string(forKey: serverURLKey) ?? "ws://localhost:8080"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: serverURLKey)
        }
    }

    static var deviceName: String {
        get {
            UserDefaults.standard.string(forKey: deviceNameKey) ?? "Vision Pro"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: deviceNameKey)
        }
    }

    static var autoConnect: Bool {
        get {
            UserDefaults.standard.bool(forKey: autoConnectKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: autoConnectKey)
        }
    }
}
