import Foundation
import Photos
import UIKit

/// Helper class to add sample videos to the Photos library for testing
class SampleVideoHelper {
    
    /// Sample videos available for testing (public domain / royalty free)
    static let sampleVideos: [(name: String, url: String, size: String)] = [
        ("Big Buck Bunny (10s)", "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/360/Big_Buck_Bunny_360_10s_1MB.mp4", "1 MB"),
        ("Big Buck Bunny (30s)", "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/720/Big_Buck_Bunny_720_10s_2MB.mp4", "2 MB"),
        ("Jellyfish (10s)", "https://test-videos.co.uk/vids/jellyfish/mp4/h264/360/Jellyfish_360_10s_1MB.mp4", "1 MB"),
    ]
    
    /// Downloads a sample video and saves it to Photos library
    static func downloadAndSaveToPhotos(
        urlString: String,
        progressHandler: @escaping (Double) -> Void,
        completion: @escaping (Bool, String?) -> Void
    ) {
        guard let url = URL(string: urlString) else {
            completion(false, "Invalid URL")
            return
        }
        
        // Request Photos permission
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    completion(false, "Photos access denied. Please enable in Settings.")
                }
                return
            }
            
            // Download the video
            let task = URLSession.shared.downloadTask(with: url) { tempURL, response, error in
                if let error = error {
                    DispatchQueue.main.async {
                        completion(false, error.localizedDescription)
                    }
                    return
                }
                
                guard let tempURL = tempURL else {
                    DispatchQueue.main.async {
                        completion(false, "Download failed")
                    }
                    return
                }
                
                // Move to a location we can access
                let fileManager = FileManager.default
                let tempDir = fileManager.temporaryDirectory
                let destinationURL = tempDir.appendingPathComponent(UUID().uuidString + ".mp4")
                
                do {
                    try? fileManager.removeItem(at: destinationURL)
                    try fileManager.moveItem(at: tempURL, to: destinationURL)
                    
                    // Save to Photos library
                    PHPhotoLibrary.shared().performChanges {
                        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: destinationURL)
                    } completionHandler: { success, error in
                        // Clean up temp file
                        try? fileManager.removeItem(at: destinationURL)
                        
                        DispatchQueue.main.async {
                            if success {
                                completion(true, nil)
                            } else {
                                completion(false, error?.localizedDescription ?? "Failed to save to Photos")
                            }
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        completion(false, error.localizedDescription)
                    }
                }
            }
            
            // Observe progress
            let observation = task.progress.observe(\.fractionCompleted) { progress, _ in
                DispatchQueue.main.async {
                    progressHandler(progress.fractionCompleted)
                }
            }
            
            // Store observation to keep it alive
            objc_setAssociatedObject(task, "progressObservation", observation, .OBJC_ASSOCIATION_RETAIN)
            
            task.resume()
        }
    }
}
