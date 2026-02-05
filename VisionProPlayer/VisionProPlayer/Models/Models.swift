import Foundation

// MARK: - WebSocket Message Types

/// Represents a command received from the WebSocket server
struct ServerCommand: Codable {
    let type: String
    let action: CommandAction
    let videoUrl: String?
    let videoFormat: VideoFormat?
    let timestamp: Int?

    enum CodingKeys: String, CodingKey {
        case type
        case action
        case videoUrl
        case videoFormat
        case timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        let actionString = try container.decode(String.self, forKey: .action)
        action = CommandAction(rawValue: actionString) ?? .stop
        videoUrl = try container.decodeIfPresent(String.self, forKey: .videoUrl)
        
        // Parse video format - support both enum value and raw string
        if let formatString = try container.decodeIfPresent(String.self, forKey: .videoFormat) {
            videoFormat = VideoFormat(rawValue: formatString)
        } else {
            videoFormat = nil
        }
        
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
    case download      // Download video from controller
    case deleteVideo   // Delete a local video
}

// MARK: - Download Command

/// Command to download a video from the iOS controller
struct DownloadCommand: Codable {
    let type: String
    let action: String
    let downloadUrl: String
    let filename: String
    let fileSize: Int64
    let timestamp: Int?
}

/// Transfer progress message sent back to controller
struct TransferProgressMessage: Codable {
    let type: String = "transferProgress"
    let deviceId: String
    let filename: String
    let progress: Double
    let bytesDownloaded: Int64
    let totalBytes: Int64
    let status: String  // started, downloading, completed, failed
}

// MARK: - Delete Video

/// Command to delete a video
struct DeleteVideoCommand: Codable {
    let type: String
    let action: String
    let filename: String
    let timestamp: Int?
}

/// Response after video deletion
struct DeleteVideoResponse: Codable {
    let type: String = "deleteVideoResponse"
    let deviceId: String
    let filename: String
    let success: Bool
    let message: String?
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

// MARK: - Local Video Types

/// Information about a locally stored video file
struct LocalVideo: Codable, Identifiable {
    let id: String
    let filename: String
    let name: String
    let url: String  // file:// URL
    let size: Int64
    let modified: Date
    let fileExtension: String
    
    enum CodingKeys: String, CodingKey {
        case id, filename, name, url, size, modified
        case fileExtension = "extension"
    }
}

/// Message to send local video list to server
struct LocalVideosMessage: Codable {
    let type: String = "localVideos"
    let deviceId: String
    let videos: [LocalVideo]
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

// MARK: - Video Format

/// Video projection and stereoscopy formats
enum VideoFormat: String, Codable, CaseIterable {
    /// Regular 2D flat video (default)
    case mono2D = "mono2d"
    /// Stereoscopic Side-by-Side (left eye on left, right eye on right)
    case sideBySide3D = "sbs3d"
    /// Stereoscopic Over-Under (left eye on top, right eye on bottom)
    case overUnder3D = "ou3d"
    /// 180° equirectangular (hemisphere)
    case hemisphere180 = "hemisphere180"
    /// 180° stereoscopic Side-by-Side
    case hemisphere180SBS = "hemisphere180sbs"
    /// 360° equirectangular (full sphere)
    case sphere360 = "sphere360"
    /// 360° stereoscopic Over-Under
    case sphere360OU = "sphere360ou"
    /// 360° stereoscopic Side-by-Side
    case sphere360SBS = "sphere360sbs"
    
    /// Human-readable display name
    var displayName: String {
        switch self {
        case .mono2D: return "2D Flat"
        case .sideBySide3D: return "3D Side-by-Side"
        case .overUnder3D: return "3D Over-Under"
        case .hemisphere180: return "180° VR"
        case .hemisphere180SBS: return "180° VR 3D"
        case .sphere360: return "360° VR"
        case .sphere360OU: return "360° VR 3D (OU)"
        case .sphere360SBS: return "360° VR 3D (SBS)"
        }
    }
    
    /// Whether this format is stereoscopic (3D)
    var isStereoscopic: Bool {
        switch self {
        case .sideBySide3D, .overUnder3D, .hemisphere180SBS, .sphere360OU, .sphere360SBS:
            return true
        default:
            return false
        }
    }
    
    /// Whether this format is immersive (180° or 360°)
    var isImmersive: Bool {
        switch self {
        case .hemisphere180, .hemisphere180SBS, .sphere360, .sphere360OU, .sphere360SBS:
            return true
        default:
            return false
        }
    }
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
