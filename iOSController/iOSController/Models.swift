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
    /// Running time the headset reported for the loaded asset. Nil until it
    /// reports one (or if the headset runs an older build).
    var duration: Double? = nil

    /// File name of the video currently loaded, derived from its URL.
    var currentFilename: String? {
        guard let currentVideo, let url = URL(string: currentVideo) else { return nil }
        return url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
    }
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
    /// Running time of the asset on the headset. Optional — a headset running an
    /// older build simply omits it, and the preview stays unverified.
    let duration: Double?
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
    case deleteVideo  // Delete a video from Vision Pro
    case syncPrepare  // Prepare a local video for synchronized playback
    case syncStart    // Start prepared video at a scheduled wall-clock time
    case syncPause    // Pause synchronized playback
    case syncResume   // Resume synchronized playback at a scheduled time
    case syncStop     // Stop synchronized playback
}

// MARK: - Synchronized Playback Messages

/// Tell a device to prepare a local video for synchronized playback
/// (open immersive space, preroll, report readiness — no autoplay).
struct SyncPrepareCommand: Codable {
    var type: String = "command"
    var action: String = CommandAction.syncPrepare.rawValue
    let filename: String
    let videoFormat: String?
    let timestamp: Int

    init(filename: String, videoFormat: VideoFormat?) {
        self.filename = filename
        self.videoFormat = videoFormat?.rawValue
        self.timestamp = Int(Date().timeIntervalSince1970 * 1000)
    }
}

/// Start prepared playback at `startAt` — epoch ms already converted
/// to the target device's clock (controller applies the measured offset).
struct SyncStartCommand: Codable {
    var type: String = "command"
    var action: String = CommandAction.syncStart.rawValue
    let startAt: Int64
    let timestamp: Int

    init(startAt: Int64) {
        self.startAt = startAt
        self.timestamp = Int(Date().timeIntervalSince1970 * 1000)
    }
}

/// Resume paused synchronized playback: seek to `mediaTime` seconds
/// and start at `startAt` (epoch ms, target device's clock).
struct SyncResumeCommand: Codable {
    var type: String = "command"
    var action: String = CommandAction.syncResume.rawValue
    let mediaTime: Double
    let startAt: Int64
    let timestamp: Int

    init(mediaTime: Double, startAt: Int64) {
        self.mediaTime = mediaTime
        self.startAt = startAt
        self.timestamp = Int(Date().timeIntervalSince1970 * 1000)
    }
}

/// Clock sync request (t0 = controller epoch ms at send time).
struct ClockSyncMessage: Codable {
    var type: String = "clockSync"
    let t0: Int64

    init(t0: Int64) {
        self.t0 = t0
    }
}

/// Clock sync reply from a device: echoes t0, adds device clock t1 (epoch ms).
struct ClockSyncResponse: Codable {
    let type: String
    let deviceId: String
    let t0: Int64
    let t1: Int64
}

/// Readiness report from a device after syncPrepare.
struct SyncReadyMessage: Codable {
    let type: String
    let deviceId: String
    let filename: String
    let success: Bool
    let message: String?
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

// MARK: - Video Transfer Messages

/// Command to tell Vision Pro to download a video from the controller
struct TransferCommand: Codable {
    let type: String = "command"
    let action: String = "download"
    let downloadUrl: String        // HTTP URL to download from
    let filename: String           // Target filename on Vision Pro
    let fileSize: Int64            // File size in bytes
    let timestamp: Int
    
    init(downloadUrl: String, filename: String, fileSize: Int64) {
        self.downloadUrl = downloadUrl
        self.filename = filename
        self.fileSize = fileSize
        self.timestamp = Int(Date().timeIntervalSince1970 * 1000)
    }
}

/// Progress update from Vision Pro during download
struct TransferProgressMessage: Codable {
    let type: String
    let deviceId: String
    let filename: String
    let progress: Double       // 0.0 to 1.0
    let bytesDownloaded: Int64
    let totalBytes: Int64
    let status: TransferStatus
}

/// Transfer status enum
enum TransferStatus: String, Codable {
    case started
    case downloading
    case completed
    case failed
}

/// Video file info for transfer
struct TransferableVideo: Identifiable {
    let id: String
    let url: URL
    let filename: String
    let fileSize: Int64
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

// MARK: - Delete Video Command

/// Command to delete a video from Vision Pro
struct DeleteVideoCommand: Codable {
    let type: String = "command"
    let action: String = "deleteVideo"
    let filename: String
    let timestamp: Int
    
    init(filename: String) {
        self.filename = filename
        self.timestamp = Int(Date().timeIntervalSince1970 * 1000)
    }
}

/// Response after video deletion
struct DeleteVideoResponse: Codable {
    let type: String
    let deviceId: String
    let filename: String
    let success: Bool
    let message: String?
}
