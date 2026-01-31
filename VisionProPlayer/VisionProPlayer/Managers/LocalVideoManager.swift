import Foundation

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

/// Manages local video files stored on the Vision Pro device.
/// Videos should be placed in the app's Documents folder.
@MainActor
class LocalVideoManager: ObservableObject {
    /// List of locally available videos
    @Published var localVideos: [LocalVideo] = []
    
    /// Whether scanning is in progress
    @Published var isScanning: Bool = false
    
    /// Last scan error
    @Published var lastError: String?
    
    /// Supported video extensions
    private let videoExtensions = ["mp4", "mov", "m4v", "mkv", "webm"]
    
    /// The folder where videos should be placed
    var videosFolder: URL? {
        // Use the Documents folder - this is accessible via Files app
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }
    
    /// Alternative: Use a "Videos" subfolder within Documents
    var videosFolderPath: String {
        videosFolder?.path ?? "Unknown"
    }
    
    init() {
        // Create Videos folder if it doesn't exist
        createVideosFolderIfNeeded()
    }
    
    /// Creates the videos folder if it doesn't exist
    private func createVideosFolderIfNeeded() {
        guard let folder = videosFolder else {
            print("[LocalVideo] Could not access Documents folder")
            return
        }
        
        // Create a Videos subfolder for organization
        let videosSubfolder = folder.appendingPathComponent("Videos")
        
        if !FileManager.default.fileExists(atPath: videosSubfolder.path) {
            do {
                try FileManager.default.createDirectory(at: videosSubfolder, withIntermediateDirectories: true)
                print("[LocalVideo] Created Videos folder at: \(videosSubfolder.path)")
            } catch {
                print("[LocalVideo] Failed to create Videos folder: \(error)")
            }
        }
    }
    
    /// Scans the local videos folder and updates the list
    func scanVideos() {
        isScanning = true
        lastError = nil
        
        guard let documentsFolder = videosFolder else {
            lastError = "Cannot access Documents folder"
            isScanning = false
            return
        }
        
        // Check both Documents root and Videos subfolder
        let videosSubfolder = documentsFolder.appendingPathComponent("Videos")
        
        var foundVideos: [LocalVideo] = []
        
        // Scan Documents folder
        foundVideos.append(contentsOf: scanFolder(documentsFolder))
        
        // Scan Videos subfolder if it exists
        if FileManager.default.fileExists(atPath: videosSubfolder.path) {
            foundVideos.append(contentsOf: scanFolder(videosSubfolder))
        }
        
        // Sort by name
        foundVideos.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        
        localVideos = foundVideos
        isScanning = false
        
        print("[LocalVideo] Found \(localVideos.count) local videos")
        for video in localVideos {
            print("[LocalVideo]   - \(video.name) (\(formatFileSize(video.size)))")
        }
    }
    
    /// Scans a specific folder for video files
    private func scanFolder(_ folder: URL) -> [LocalVideo] {
        var videos: [LocalVideo] = []
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            
            for fileURL in contents {
                let ext = fileURL.pathExtension.lowercased()
                guard videoExtensions.contains(ext) else { continue }
                
                do {
                    let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                    let fileSize = Int64(resourceValues.fileSize ?? 0)
                    let modified = resourceValues.contentModificationDate ?? Date()
                    
                    let video = LocalVideo(
                        id: UUID().uuidString,
                        filename: fileURL.lastPathComponent,
                        name: fileURL.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " "),
                        url: fileURL.absoluteString,  // file:// URL
                        size: fileSize,
                        modified: modified,
                        fileExtension: ext
                    )
                    
                    videos.append(video)
                    
                } catch {
                    print("[LocalVideo] Error reading file attributes: \(error)")
                }
            }
        } catch {
            print("[LocalVideo] Error scanning folder \(folder.path): \(error)")
        }
        
        return videos
    }
    
    /// Returns a video by its ID
    func getVideo(byId id: String) -> LocalVideo? {
        return localVideos.first { $0.id == id }
    }
    
    /// Returns a video by its filename
    func getVideo(byFilename filename: String) -> LocalVideo? {
        return localVideos.first { $0.filename == filename }
    }
    
    /// Formats file size for display
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    /// Returns formatted file size for a video
    func formattedSize(for video: LocalVideo) -> String {
        return formatFileSize(video.size)
    }
}
