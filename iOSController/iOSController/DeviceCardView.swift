import SwiftUI
import Network

struct DeviceCardView: View {
    @ObservedObject var device: ConnectedDevice
    @EnvironmentObject var deviceManager: DeviceManager
    @State private var selectedVideoUrl: String = ""
    @State private var selectedFormat: VideoFormat = .hemisphere180SBS
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            DeviceHeaderView(device: device, isExpanded: $isExpanded)
            
            if isExpanded {
                Divider()
                
                // Video Selection
                VideoSelectionView(
                    device: device,
                    selectedVideoUrl: $selectedVideoUrl,
                    selectedFormat: $selectedFormat
                )
                
                Divider()
                
                // Playback Controls
                PlaybackControlsView(
                    device: device,
                    selectedVideoUrl: selectedVideoUrl,
                    selectedFormat: selectedFormat
                )
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Device Header

struct DeviceHeaderView: View {
    @ObservedObject var device: ConnectedDevice
    @Binding var isExpanded: Bool
    
    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                // Device Icon
                Image(systemName: "visionpro")
                    .font(.title2)
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
                    .background(Color(.systemGray5))
                    .cornerRadius(10)
                
                // Device Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.deviceName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 8) {
                        // Status Badge
                        StatusBadge(state: device.state.playbackState)
                        
                        // Immersive Badge
                        if device.state.immersiveMode {
                            Label("Immersive", systemImage: "circle.inset.filled")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.2))
                                .foregroundColor(.purple)
                                .cornerRadius(4)
                        }
                    }
                }
                
                Spacer()
                
                // Video Count
                if !device.localVideos.isEmpty {
                    Label("\(device.localVideos.count)", systemImage: "film.stack")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Expand Chevron
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let state: PlaybackState
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            
            Text(state.rawValue.capitalized)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.15))
        .foregroundColor(statusColor)
        .cornerRadius(6)
    }
    
    var statusColor: Color {
        switch state {
        case .playing: return .green
        case .paused: return .orange
        case .loading: return .blue
        case .stopped, .idle: return .gray
        case .error: return .red
        case .unknown: return .gray
        }
    }
}

// MARK: - Video Selection

struct VideoSelectionView: View {
    @ObservedObject var device: ConnectedDevice
    @Binding var selectedVideoUrl: String
    @Binding var selectedFormat: VideoFormat
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section Header
            HStack {
                Label("Local Videos", systemImage: "film")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("\(device.localVideos.count) available")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if device.localVideos.isEmpty {
                // Empty State
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "film.stack")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("No videos found on device")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Add videos to Documents/Videos folder")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 20)
                    Spacer()
                }
            } else {
                // Video List
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(device.localVideos) { video in
                            VideoThumbnailButton(
                                video: video,
                                isSelected: selectedVideoUrl == video.url
                            ) {
                                selectedVideoUrl = video.url
                            }
                        }
                    }
                }
            }
            
            // Format Picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Video Format")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Picker("Format", selection: $selectedFormat) {
                    ForEach(VideoFormat.allCases, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.menu)
                .tint(.primary)
            }
            
            // Currently Playing
            if let currentVideo = device.state.currentVideo {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Now Playing")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(videoName(from: currentVideo))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }
                .padding(.top, 8)
            }
        }
        .padding()
    }
    
    func videoName(from url: String) -> String {
        guard let urlObj = URL(string: url) else { return url }
        return urlObj.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }
}

// MARK: - Video Thumbnail Button

struct VideoThumbnailButton: View {
    let video: LocalVideo
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                // Thumbnail Placeholder
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))
                    
                    Image(systemName: "film")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .frame(width: 120, height: 70)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                )
                
                // Video Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(video.name)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .foregroundColor(.primary)
                    
                    Text(video.formattedSize)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(width: 120, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Playback Controls

struct PlaybackControlsView: View {
    @ObservedObject var device: ConnectedDevice
    @EnvironmentObject var deviceManager: DeviceManager
    let selectedVideoUrl: String
    let selectedFormat: VideoFormat
    
    var body: some View {
        VStack(spacing: 12) {
            // Top row: Play button (full width)
            Button {
                deviceManager.play(
                    deviceId: device.deviceId,
                    videoUrl: selectedVideoUrl,
                    format: selectedFormat
                )
            } label: {
                Label("Play", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedVideoUrl.isEmpty)
            
            // Bottom row: Pause, Resume, Stop
            HStack(spacing: 12) {
                // Pause Button
                Button {
                    deviceManager.pause(deviceId: device.deviceId)
                } label: {
                    Image(systemName: "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(device.state.playbackState != .playing)
                
                // Resume Button
                Button {
                    deviceManager.resume(deviceId: device.deviceId)
                } label: {
                    Image(systemName: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.green)
                .disabled(device.state.playbackState != .paused)
                
                // Stop Button
                Button {
                    deviceManager.stop(deviceId: device.deviceId)
                } label: {
                    Image(systemName: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(device.state.playbackState == .idle || device.state.playbackState == .stopped)
            }
        }
        .padding()
    }
}

#Preview {
    DeviceCardView(
        device: {
            let device = ConnectedDevice(
                deviceId: "test-123",
                deviceName: "Ali's Vision Pro",
                connection: ClientConnection(connection: NWConnection(host: "localhost", port: 8080, using: .tcp))
            )
            device.localVideos = [
                LocalVideo(id: "1", filename: "test.mp4", name: "Test Video", url: "file://test.mp4", size: 1024000, modified: Date(), fileExtension: "mp4"),
                LocalVideo(id: "2", filename: "demo.mp4", name: "Demo Video", url: "file://demo.mp4", size: 2048000, modified: Date(), fileExtension: "mp4")
            ]
            return device
        }()
    )
    .environmentObject(DeviceManager())
    .padding()
}
