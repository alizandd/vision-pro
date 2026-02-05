import Foundation

/// Manages video downloads from the iOS controller to Vision Pro
@MainActor
class DownloadManager: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isDownloading: Bool = false
    @Published var currentDownload: DownloadInfo?
    @Published var downloadHistory: [DownloadInfo] = []
    @Published var lastError: String?
    
    // MARK: - Callbacks
    
    /// Called when download progress updates
    var onProgress: ((String, Double, Int64, Int64) -> Void)?
    
    /// Called when download completes
    var onComplete: ((String, URL) -> Void)?
    
    /// Called when download fails
    var onError: ((String, String) -> Void)?
    
    // MARK: - Private Properties
    
    private var urlSession: URLSession!
    private var downloadTask: URLSessionDownloadTask?
    private var currentFilename: String?
    private var totalBytes: Int64 = 0
    
    // MARK: - Download Info
    
    struct DownloadInfo: Identifiable {
        let id: String
        let filename: String
        var progress: Double
        var bytesDownloaded: Int64
        var totalBytes: Int64
        var status: DownloadStatus
        var savedURL: URL?
        let startTime: Date
        var endTime: Date?
        
        enum DownloadStatus: String {
            case pending
            case downloading
            case completed
            case failed
        }
        
        var formattedProgress: String {
            "\(Int(progress * 100))%"
        }
        
        var formattedSize: String {
            let downloaded = ByteCountFormatter.string(fromByteCount: bytesDownloaded, countStyle: .file)
            let total = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
            return "\(downloaded) / \(total)"
        }
    }
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300  // 5 minutes
        config.timeoutIntervalForResource = 3600  // 1 hour for large files
        
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }
    
    // MARK: - Public Methods
    
    /// Start downloading a video from the given URL
    func downloadVideo(from urlString: String, filename: String, expectedSize: Int64) {
        // If already downloading, cancel the previous download first
        if isDownloading {
            print("[DownloadManager] Cancelling previous download to start new one")
            downloadTask?.cancel()
            downloadTask = nil
            isDownloading = false
            currentDownload = nil
            currentFilename = nil
        }
        
        guard let url = URL(string: urlString) else {
            print("[DownloadManager] Invalid URL: \(urlString)")
            lastError = "Invalid download URL"
            onError?(filename, "Invalid URL")
            return
        }
        
        print("[DownloadManager] Starting download: \(filename)")
        print("[DownloadManager] URL: \(urlString)")
        print("[DownloadManager] Expected size: \(ByteCountFormatter.string(fromByteCount: expectedSize, countStyle: .file))")
        
        currentFilename = filename
        totalBytes = expectedSize
        isDownloading = true
        lastError = nil
        
        // Create download info
        let info = DownloadInfo(
            id: UUID().uuidString,
            filename: filename,
            progress: 0,
            bytesDownloaded: 0,
            totalBytes: expectedSize,
            status: .downloading,
            savedURL: nil,
            startTime: Date(),
            endTime: nil
        )
        currentDownload = info
        
        // Create and start download task
        let request = URLRequest(url: url)
        downloadTask = urlSession.downloadTask(with: request)
        downloadTask?.resume()
        
        // Notify progress started
        onProgress?(filename, 0, 0, expectedSize)
    }
    
    /// Cancel current download
    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        
        if var download = currentDownload {
            download.status = .failed
            download.endTime = Date()
            downloadHistory.append(download)
        }
        currentDownload = nil
        currentFilename = nil
        
        print("[DownloadManager] Download cancelled")
    }
    
    /// Reset the download manager state (use if stuck)
    func reset() {
        print("[DownloadManager] Resetting state...")
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        currentDownload = nil
        currentFilename = nil
        totalBytes = 0
        lastError = nil
        print("[DownloadManager] State reset complete")
    }
    
    // MARK: - Private Methods
    
    /// Get the videos folder URL
    private func getVideosFolder() -> URL? {
        guard let documentsFolder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        let videosFolder = documentsFolder.appendingPathComponent("Videos")
        
        // Create folder if it doesn't exist
        if !FileManager.default.fileExists(atPath: videosFolder.path) {
            do {
                try FileManager.default.createDirectory(at: videosFolder, withIntermediateDirectories: true)
            } catch {
                print("[DownloadManager] Failed to create Videos folder: \(error)")
                return nil
            }
        }
        
        return videosFolder
    }
    
    /// Move downloaded file to videos folder
    private func moveToVideosFolder(tempURL: URL, filename: String) -> URL? {
        guard let videosFolder = getVideosFolder() else {
            print("[DownloadManager] Cannot access Videos folder")
            return nil
        }
        
        var targetURL = videosFolder.appendingPathComponent(filename)
        
        // If file exists, add a number suffix
        var counter = 1
        let nameWithoutExt = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        
        while FileManager.default.fileExists(atPath: targetURL.path) {
            let newName = "\(nameWithoutExt)_\(counter).\(ext)"
            targetURL = videosFolder.appendingPathComponent(newName)
            counter += 1
        }
        
        do {
            try FileManager.default.moveItem(at: tempURL, to: targetURL)
            print("[DownloadManager] ✅ Saved to: \(targetURL.path)")
            return targetURL
        } catch {
            print("[DownloadManager] Failed to move file: \(error)")
            return nil
        }
    }
}

// MARK: - URLSessionDownloadDelegate

extension DownloadManager: URLSessionDownloadDelegate {
    
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // IMPORTANT: Must copy file BEFORE this method returns, because the system
        // deletes the temporary file immediately after this method completes.
        
        // Copy to a safe location first (still on background thread)
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
        let safeTempURL = tempDir.appendingPathComponent(UUID().uuidString + ".tmp")
        
        do {
            try fileManager.copyItem(at: location, to: safeTempURL)
            print("[DownloadManager] Copied to safe location: \(safeTempURL.path)")
        } catch {
            print("[DownloadManager] ❌ Failed to copy temp file: \(error)")
            Task { @MainActor in
                self.isDownloading = false
                self.currentFilename = nil
                self.lastError = "Failed to copy downloaded file"
                if var download = self.currentDownload {
                    download.status = .failed
                    download.endTime = Date()
                    self.downloadHistory.append(download)
                    self.currentDownload = nil
                }
            }
            return
        }
        
        // Now process on MainActor
        Task { @MainActor in
            guard let filename = currentFilename else {
                try? fileManager.removeItem(at: safeTempURL)
                return
            }
            
            print("[DownloadManager] Download finished, moving file...")
            
            if let savedURL = moveToVideosFolder(tempURL: safeTempURL, filename: filename) {
                // Update download info
                if var download = currentDownload {
                    download.status = .completed
                    download.progress = 1.0
                    download.bytesDownloaded = download.totalBytes
                    download.savedURL = savedURL
                    download.endTime = Date()
                    downloadHistory.append(download)
                    currentDownload = nil
                }
                
                isDownloading = false
                currentFilename = nil
                
                print("[DownloadManager] ✅ Download complete: \(filename)")
                onComplete?(filename, savedURL)
            } else {
                // Failed to save - clean up temp file
                try? fileManager.removeItem(at: safeTempURL)
                
                if var download = currentDownload {
                    download.status = .failed
                    download.endTime = Date()
                    downloadHistory.append(download)
                    currentDownload = nil
                }
                
                isDownloading = false
                currentFilename = nil
                lastError = "Failed to save file"
                
                onError?(filename, "Failed to save file to Videos folder")
            }
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        Task { @MainActor in
            guard let filename = currentFilename else { return }
            
            // Use expected size from command if available
            let total = totalBytes > 0 ? totalBytes : totalBytesExpectedToWrite
            let progress = total > 0 ? Double(totalBytesWritten) / Double(total) : 0
            
            // Update current download
            if var download = currentDownload {
                download.progress = progress
                download.bytesDownloaded = totalBytesWritten
                if total > 0 {
                    download.totalBytes = total
                }
                currentDownload = download
            }
            
            // Log progress periodically (every 10%)
            let progressPercent = Int(progress * 100)
            if progressPercent % 10 == 0 {
                print("[DownloadManager] Progress: \(progressPercent)% (\(ByteCountFormatter.string(fromByteCount: totalBytesWritten, countStyle: .file)))")
            }
            
            onProgress?(filename, progress, totalBytesWritten, total)
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // Check HTTP response for status code
        if let httpResponse = task.response as? HTTPURLResponse {
            print("[DownloadManager] HTTP Status Code: \(httpResponse.statusCode)")
            if httpResponse.statusCode >= 400 {
                Task { @MainActor in
                    let filename = currentFilename ?? "unknown"
                    let errorMsg = "HTTP Error: \(httpResponse.statusCode)"
                    print("[DownloadManager] ❌ \(errorMsg)")
                    
                    if var download = currentDownload {
                        download.status = .failed
                        download.endTime = Date()
                        downloadHistory.append(download)
                        currentDownload = nil
                    }
                    
                    isDownloading = false
                    currentFilename = nil
                    lastError = errorMsg
                    
                    onError?(filename, errorMsg)
                }
                return
            }
        }
        
        Task { @MainActor in
            guard let error = error else { return }  // No error means success
            
            let filename = currentFilename ?? "unknown"
            print("[DownloadManager] ❌ Download failed: \(error.localizedDescription)")
            print("[DownloadManager] Error details: \(error)")
            
            // Check for specific network errors
            let nsError = error as NSError
            print("[DownloadManager] Error domain: \(nsError.domain), code: \(nsError.code)")
            
            // Update download info
            if var download = currentDownload {
                download.status = .failed
                download.endTime = Date()
                downloadHistory.append(download)
                currentDownload = nil
            }
            
            isDownloading = false
            currentFilename = nil
            lastError = error.localizedDescription
            
            onError?(filename, error.localizedDescription)
        }
    }
}
