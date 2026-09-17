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
    case syncPrepare   // Prepare a local video for synchronized playback (no autoplay)
    case syncStart     // Start prepared video at a scheduled wall-clock time
    case syncPause     // Pause synchronized playback on all devices
    case syncResume    // Resume synchronized playback at a scheduled time
    case syncStop      // Stop synchronized playback
    case seek          // Jump to an absolute media time; playback state unchanged
}

// MARK: - Synchronized Playback

/// Command to prepare a local video for synchronized playback.
/// The device opens the immersive space and prerolls the player,
/// then reports readiness via SyncReadyMessage without starting playback.
struct SyncPrepareCommand: Codable {
    let type: String
    let action: String
    let filename: String
    let videoFormat: String?
    let timestamp: Int?
}

/// Command to start prepared playback at `startAt` (epoch ms, already
/// converted to this device's clock by the controller).
struct SyncStartCommand: Codable {
    let type: String
    let action: String
    let startAt: Int64
    let timestamp: Int?
}

/// Command to resume paused synchronized playback: seek to `mediaTime`
/// seconds and start at `startAt` (epoch ms, device clock).
struct SyncResumeCommand: Codable {
    let type: String
    let action: String
    let mediaTime: Double
    let startAt: Int64
    let timestamp: Int?
}

/// Jump to an absolute media time on the operator's behalf. Sent to one
/// headset; a group seek arrives as syncPause + syncResume instead.
struct SeekCommand: Codable {
    let type: String
    let action: String
    let mediaTime: Double
    let timestamp: Int?
}

/// Clock sync request from the controller (t0 = controller epoch ms).
struct ClockSyncMessage: Codable {
    let type: String
    let t0: Int64
}

/// Clock sync reply: echoes t0 and adds this device's clock t1 (epoch ms).
struct ClockSyncResponse: Codable {
    var type: String = "clockSyncResponse"
    let deviceId: String
    let t0: Int64
    let t1: Int64
}

/// Readiness report after a syncPrepare command.
struct SyncReadyMessage: Codable {
    var type: String = "syncReady"
    let deviceId: String
    let filename: String
    let success: Bool
    let message: String?
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
    /// Running time of the asset currently loaded. The controller uses it to
    /// confirm a paired preview video really matches before showing it.
    let duration: Double?
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

/// Where the wearer is looking, plus exactly where playback is.
///
/// Sent only while an immersive space is open **and** a controller has asked
/// for it, so a headset nobody is previewing adds no traffic at all.
///
/// Head pose only — visionOS does not expose eye/gaze tracking to apps, and
/// this deliberately does not attempt to infer it.
struct ViewerStateMessage: Codable {
    let type: String = "viewerState"
    let deviceId: String
    /// Horizontal look direction in radians, 0 = the video's forward centre.
    let yaw: Double
    /// Vertical look direction in radians, positive is up.
    let pitch: Double
    /// Playback position at the moment the pose was sampled.
    let mediaTime: Double
    /// Headset epoch milliseconds, so the controller can age the sample.
    let timestamp: Int64

    enum CodingKeys: String, CodingKey {
        case type, deviceId, yaw, pitch, mediaTime, timestamp
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(deviceId, forKey: .deviceId)
        try container.encode(yaw, forKey: .yaw)
        try container.encode(pitch, forKey: .pitch)
        try container.encode(mediaTime, forKey: .mediaTime)
        try container.encode(timestamp, forKey: .timestamp)
    }
}

/// Controller asking this headset to start or stop reporting viewer state.
struct PreviewSubscribeCommand: Codable {
    let type: String
    let action: String
    let enabled: Bool
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
    static let preferredControllerIdKey = "preferred_controller_id"

    /// Registers the shipped defaults. Call once at launch, before anything
    /// reads configuration.
    ///
    /// `autoConnect` defaults to **true**: the headset is meant to find its
    /// controller by itself, and `UserDefaults.bool` would otherwise silently
    /// return `false` on a fresh install and leave it sitting idle.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            autoConnectKey: true
        ])
    }

    /// WebSocket URL of the controller.
    ///
    /// Empty on a fresh install — deliberately **not** `ws://localhost:8080`,
    /// which made the headset connect to itself and masked discovery failures.
    /// It is filled in by Bonjour discovery, or by hand for non-Bonjour setups.
    static var serverURL: String {
        get {
            UserDefaults.standard.string(forKey: serverURLKey) ?? ""
        }
        set {
            UserDefaults.standard.set(newValue, forKey: serverURLKey)
        }
    }

    /// Stable id of the controller this headset should follow, as published in
    /// the Bonjour TXT record. Stored instead of an IP address so a controller
    /// that moves to a new DHCP lease is still recognised.
    static var preferredControllerId: String? {
        get {
            UserDefaults.standard.string(forKey: preferredControllerIdKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: preferredControllerIdKey)
        }
    }

    /// Longest name the device card can show without truncating awkwardly.
    static let deviceNameMaxLength = 40

    /// Name this headset introduces itself with.
    ///
    /// Persisted in UserDefaults, so it survives quitting and relaunching the
    /// app and is only cleared when the app itself is deleted. Nothing but the
    /// user changes it — reconnects, controller restarts and network changes all
    /// leave it alone.
    ///
    /// Setting an empty or whitespace-only name falls back to the default
    /// rather than leaving a blank entry on the operator's device list.
    static var deviceName: String {
        get {
            let stored = UserDefaults.standard.string(forKey: deviceNameKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let stored, !stored.isEmpty else { return defaultDeviceName }
            return stored
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                UserDefaults.standard.removeObject(forKey: deviceNameKey)
                return
            }
            UserDefaults.standard.set(String(trimmed.prefix(deviceNameMaxLength)), forKey: deviceNameKey)
        }
    }

    /// Default name for a headset whose owner hasn't chosen one.
    ///
    /// Suffixed with part of this device's persistent id, because a room full of
    /// headsets all called "VPC Player" is exactly the problem the name exists
    /// to solve. Any name the user sets replaces this entirely.
    static var defaultDeviceName: String {
        let suffix = deviceIdentifier.replacingOccurrences(of: "-", with: "").suffix(4).uppercased()
        return suffix.isEmpty ? "VPC Player" : "VPC Player \(suffix)"
    }

    /// Stable per-install identifier, shared with `WebSocketManager`.
    static var deviceIdentifier: String {
        let key = "device_id"
        if let stored = UserDefaults.standard.string(forKey: key) {
            return stored
        }
        let created = UUID().uuidString
        UserDefaults.standard.set(created, forKey: key)
        return created
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
