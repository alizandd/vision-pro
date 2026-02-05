import Foundation

// MARK: - Connected Device

/// Represents a connected Vision Pro device
class ConnectedDevice: ObservableObject, Identifiable {
    let id: String
    let deviceId: String
    @Published var deviceName: String
    @Published var state: DeviceState
    @Published var localVideos: [LocalVideo]
    let connection: ClientConnection
    
    init(deviceId: String, deviceName: String, connection: ClientConnection) {
        self.id = deviceId
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.state = DeviceState()
        self.localVideos = []
        self.connection = connection
    }
}

/// Device playback state
struct DeviceState {
    var playbackState: PlaybackState = .idle
    var currentVideo: String? = nil
    var immersiveMode: Bool = false
    var currentTime: Double = 0
}

/// Playback states
enum PlaybackState: String, Codable {
    case idle
    case loading
    case playing
    case paused
    case stopped
    case error
    case unknown
}

// MARK: - Local Video

/// Information about a locally stored video file on Vision Pro
struct LocalVideo: Codable, Identifiable {
    let id: String
    let filename: String
    let name: String
    let url: String
    let size: Int64
    let modified: Date
    let fileExtension: String
    
    enum CodingKeys: String, CodingKey {
        case id, filename, name, url, size, modified
        case fileExtension = "extension"
    }
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

// MARK: - Video Format

/// Video projection and stereoscopy formats
enum VideoFormat: String, Codable, CaseIterable {
    case mono2D = "mono2d"
    case sideBySide3D = "sbs3d"
    case overUnder3D = "ou3d"
    case hemisphere180 = "hemisphere180"
    case hemisphere180SBS = "hemisphere180sbs"
    case sphere360 = "sphere360"
    case sphere360OU = "sphere360ou"
    case sphere360SBS = "sphere360sbs"
    
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
}

// MARK: - WebSocket Messages

/// Message types
enum MessageType: String, Codable {
    case register
    case registered
    case command
    case status
    case localVideos
    case welcome
    case error
    case ping
    case pong
}

/// Registration message from device
struct RegistrationMessage: Codable {
    let type: String
    let deviceId: String
    let deviceName: String
    let deviceType: String
}

/// Status update from device
struct StatusMessage: Codable {
    let type: String
    let deviceId: String
    let deviceName: String
    let state: String
    let currentVideo: String?
    let immersiveMode: Bool
    let currentTime: Double?
}

/// Local videos message from device
struct LocalVideosMessage: Codable {
    let type: String
    let deviceId: String
    let videos: [LocalVideo]
}

/// Command to send to device
struct CommandMessage: Codable {
    let type: String = "command"
    let action: String
    let videoUrl: String?
    let videoFormat: String?
    let timestamp: Int
    
    init(action: CommandAction, videoUrl: String? = nil, videoFormat: VideoFormat? = nil) {
        self.action = action.rawValue
        self.videoUrl = videoUrl
        self.videoFormat = videoFormat?.rawValue
        self.timestamp = Int(Date().timeIntervalSince1970 * 1000)
    }
}

/// Command actions
enum CommandAction: String, Codable {
    case play
    case pause
    case resume
    case change
    case stop
}

/// Welcome message sent to new connections
struct WelcomeMessage: Codable {
    let type: String = "welcome"
    let message: String = "Connected to iOS Vision Pro Controller"
    let serverVersion: String = "1.0.0"
}

/// Registered acknowledgement
struct RegisteredAckMessage: Codable {
    let type: String = "registered"
    let deviceId: String
    let message: String
}

/// Error message
struct ErrorMessage: Codable {
    let type: String = "error"
    let message: String
    let timestamp: Int
    
    init(message: String) {
        self.message = message
        self.timestamp = Int(Date().timeIntervalSince1970 * 1000)
    }
}
