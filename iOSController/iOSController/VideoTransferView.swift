import SwiftUI
import PhotosUI
import AVFoundation
import Network

struct VideoTransferView: View {
    @EnvironmentObject var deviceManager: DeviceManager
    @ObservedObject var transferServer: FileTransferServer
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedPhotosItems: [PhotosPickerItem] = []
    @State private var selectedVideos: [TransferableVideo] = []
    @State private var selectedDeviceId: String?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var transferInProgress = false
    @State private var currentTransferFilename: String?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header Info
                if !transferServer.isRunning {
                    ServerNotRunningBanner()
                }
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Step 1: Select Videos
                        VideoSelectionSection(
                            selectedPhotosItems: $selectedPhotosItems,
                            selectedVideos: $selectedVideos,
                            isLoading: $isLoading
                        )
                        
                        // Step 2: Select Device
                        if !selectedVideos.isEmpty {
                            DeviceSelectionSection(
                                selectedDeviceId: $selectedDeviceId,
                                devices: deviceManager.devices
                            )
                        }
                        
                        // Step 3: Transfer Status
                        if !transferServer.activeTransfers.isEmpty {
                            TransferProgressSection(transfers: Array(transferServer.activeTransfers.values))
                        }
                    }
                    .padding()
                }
                
                // Transfer Button
                if !selectedVideos.isEmpty && selectedDeviceId != nil {
                    TransferButton(
                        isTransferring: transferInProgress,
                        videoCount: selectedVideos.count,
                        action: startTransfer
                    )
                }
            }
            .navigationTitle("Send Videos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isLoading {
                        ProgressView()
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
            .onChange(of: selectedPhotosItems) { _, newItems in
                Task {
                    await loadVideos(from: newItems)
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func loadVideos(from items: [PhotosPickerItem]) async {
        await MainActor.run { isLoading = true }
        
        var videos: [TransferableVideo] = []
        
        for item in items {
            do {
                // Load as movie
                if let movie = try await item.loadTransferable(type: VideoTransferable.self) {
                    let video = TransferableVideo(
                        id: UUID().uuidString,
                        url: movie.url,
                        filename: movie.url.lastPathComponent,
                        fileSize: movie.fileSize
                    )
                    videos.append(video)
                }
            } catch {
                print("[VideoTransfer] Failed to load video: \(error)")
            }
        }
        
        await MainActor.run {
            selectedVideos = videos
            isLoading = false
        }
    }
    
    private func startTransfer() {
        guard let deviceId = selectedDeviceId,
              let device = deviceManager.devices.first(where: { $0.deviceId == deviceId }) else {
            errorMessage = "No device selected"
            showError = true
            return
        }
        
        guard transferServer.isRunning else {
            errorMessage = "Transfer server is not running"
            showError = true
            return
        }
        
        transferInProgress = true
        
        Task {
            for video in selectedVideos {
                await transferVideo(video, to: device)
            }
            
            await MainActor.run {
                transferInProgress = false
                currentTransferFilename = nil
                // Clear selection after successful transfer
                selectedVideos.removeAll()
                selectedPhotosItems.removeAll()
            }
        }
    }
    
    private func transferVideo(_ video: TransferableVideo, to device: ConnectedDevice) async {
        await MainActor.run {
            currentTransferFilename = video.filename
        }
        
        // Get local IP
        guard let localIP = NetworkUtils.getLocalIPAddress() else {
            await MainActor.run {
                errorMessage = "Cannot determine local IP address"
                showError = true
            }
            return
        }
        
        // Add file to server
        guard let path = transferServer.serveFile(url: video.url, filename: video.filename) else {
            await MainActor.run {
                errorMessage = "Cannot serve file: \(video.filename)"
                showError = true
            }
            return
        }
        
        let downloadUrl = transferServer.getDownloadURL(path: path, localIP: localIP)
        
        print("[VideoTransfer] ========== TRANSFER INFO ==========")
        print("[VideoTransfer] Local IP: \(localIP)")
        print("[VideoTransfer] HTTP Server Port: \(transferServer.port)")
        print("[VideoTransfer] Download URL: \(downloadUrl)")
        print("[VideoTransfer] Filename: \(video.filename)")
        print("[VideoTransfer] File Size: \(video.fileSize) bytes")
        print("[VideoTransfer] Target Device: \(device.deviceName)")
        print("[VideoTransfer] ====================================")
        
        // Send transfer command to Vision Pro
        let command = TransferCommand(
            downloadUrl: downloadUrl,
            filename: video.filename,
            fileSize: video.fileSize
        )
        
        deviceManager.sendTransferCommand(to: device.deviceId, command: command)
        deviceManager.log("📤 Sending \(video.filename) to \(device.deviceName)", type: .info)
        deviceManager.log("📍 URL: \(downloadUrl)", type: .info)
        
        // Wait a bit for the transfer to start
        try? await Task.sleep(nanoseconds: 500_000_000)
    }
}

// MARK: - Supporting Views

struct ServerNotRunningBanner: View {
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text("Start the server to enable transfers")
                .font(.subheadline)
            Spacer()
        }
        .padding()
        .background(Color.orange.opacity(0.1))
    }
}

struct VideoSelectionSection: View {
    @Binding var selectedPhotosItems: [PhotosPickerItem]
    @Binding var selectedVideos: [TransferableVideo]
    @Binding var isLoading: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Select Videos", systemImage: "1.circle.fill")
                .font(.headline)
            
            PhotosPicker(
                selection: $selectedPhotosItems,
                maxSelectionCount: 10,
                matching: .videos,
                photoLibrary: .shared()
            ) {
                HStack {
                    Image(systemName: "photo.on.rectangle.angled")
                    Text(selectedVideos.isEmpty ? "Choose from Library" : "Change Selection")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
            
            // Selected videos list
            if !selectedVideos.isEmpty {
                VStack(spacing: 8) {
                    ForEach(selectedVideos) { video in
                        SelectedVideoRow(video: video) {
                            // Remove video
                            if let index = selectedVideos.firstIndex(where: { $0.id == video.id }) {
                                selectedVideos.remove(at: index)
                                if let pickerIndex = selectedPhotosItems.indices.first(where: { $0 == index }) {
                                    selectedPhotosItems.remove(at: pickerIndex)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8)
    }
}

struct SelectedVideoRow: View {
    let video: TransferableVideo
    let onRemove: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "film")
                .foregroundColor(.secondary)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(video.filename)
                    .font(.subheadline)
                    .lineLimit(1)
                
                Text(video.formattedSize)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

struct DeviceSelectionSection: View {
    @Binding var selectedDeviceId: String?
    let devices: [ConnectedDevice]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Select Device", systemImage: "2.circle.fill")
                .font(.headline)
            
            if devices.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "visionpro")
                            .font(.title)
                            .foregroundColor(.secondary)
                        Text("No devices connected")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 20)
                    Spacer()
                }
            } else {
                ForEach(devices) { device in
                    DeviceSelectionRow(
                        device: device,
                        isSelected: selectedDeviceId == device.deviceId
                    ) {
                        selectedDeviceId = device.deviceId
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8)
    }
}

struct DeviceSelectionRow: View {
    @ObservedObject var device: ConnectedDevice
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: "visionpro")
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : .primary)
                    .frame(width: 40)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.deviceName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(isSelected ? .white : .primary)
                    
                    Text("\(device.localVideos.count) videos stored")
                        .font(.caption)
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.white)
                }
            }
            .padding()
            .background(isSelected ? Color.accentColor : Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

struct TransferProgressSection: View {
    let transfers: [FileTransferServer.TransferInfo]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Transfer Progress", systemImage: "arrow.up.circle.fill")
                .font(.headline)
            
            ForEach(transfers) { transfer in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(transfer.filename)
                            .font(.subheadline)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        if transfer.isComplete {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Text("\(Int(transfer.progress * 100))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    ProgressView(value: transfer.progress)
                        .tint(transfer.isComplete ? .green : .accentColor)
                    
                    Text("\(formatBytes(transfer.bytesSent)) / \(formatBytes(transfer.totalBytes))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8)
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

struct TransferButton: View {
    let isTransferring: Bool
    let videoCount: Int
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                if isTransferring {
                    ProgressView()
                        .tint(.white)
                        .padding(.trailing, 8)
                    Text("Sending...")
                } else {
                    Image(systemName: "paperplane.fill")
                    Text("Send \(videoCount) Video\(videoCount > 1 ? "s" : "")")
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isTransferring ? Color.gray : Color.accentColor)
            .foregroundColor(.white)
            .font(.headline)
        }
        .disabled(isTransferring)
        .padding()
        .background(Color(.systemBackground))
    }
}

// MARK: - Video Transferable

struct VideoTransferable: Transferable {
    let url: URL
    let fileSize: Int64
    
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            // Copy to temp directory
            let tempDir = FileManager.default.temporaryDirectory
            let targetURL = tempDir.appendingPathComponent(received.file.lastPathComponent)
            
            // Remove existing file if present
            try? FileManager.default.removeItem(at: targetURL)
            
            // Copy file
            try FileManager.default.copyItem(at: received.file, to: targetURL)
            
            // Get file size
            let attributes = try FileManager.default.attributesOfItem(atPath: targetURL.path)
            let fileSize = (attributes[.size] as? Int64) ?? 0
            
            return VideoTransferable(url: targetURL, fileSize: fileSize)
        }
    }
}

#Preview {
    VideoTransferView(transferServer: FileTransferServer())
        .environmentObject(DeviceManager())
}
