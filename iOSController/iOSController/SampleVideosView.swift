import SwiftUI

/// View for downloading sample videos to test the transfer feature
struct SampleVideosView: View {
    @Environment(\.dismiss) var dismiss
    @State private var downloadingIndex: Int?
    @State private var downloadProgress: Double = 0
    @State private var showSuccess = false
    @State private var showError = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(SampleVideoHelper.sampleVideos.enumerated()), id: \.offset) { index, video in
                        SampleVideoRow(
                            name: video.name,
                            size: video.size,
                            isDownloading: downloadingIndex == index,
                            progress: downloadingIndex == index ? downloadProgress : 0,
                            onDownload: {
                                downloadVideo(at: index)
                            }
                        )
                    }
                } header: {
                    Text("Available Sample Videos")
                } footer: {
                    Text("These are royalty-free test videos. After downloading, they will appear in your Photos library and can be selected for transfer.")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("How to Test", systemImage: "info.circle")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        Text("1. Download a sample video above")
                        Text("2. Tap the upload button in the toolbar")
                        Text("3. Select the downloaded video from Photos")
                        Text("4. Choose a Vision Pro device")
                        Text("5. Tap Send to transfer")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Sample Videos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Success", isPresented: $showSuccess) {
                Button("OK") {}
            } message: {
                Text("Video saved to Photos! You can now select it for transfer.")
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }
    
    private func downloadVideo(at index: Int) {
        guard downloadingIndex == nil else { return }
        
        downloadingIndex = index
        downloadProgress = 0
        
        let video = SampleVideoHelper.sampleVideos[index]
        
        SampleVideoHelper.downloadAndSaveToPhotos(
            urlString: video.url,
            progressHandler: { progress in
                downloadProgress = progress
            },
            completion: { success, error in
                downloadingIndex = nil
                downloadProgress = 0
                
                if success {
                    showSuccess = true
                } else {
                    errorMessage = error
                    showError = true
                }
            }
        )
    }
}

struct SampleVideoRow: View {
    let name: String
    let size: String
    let isDownloading: Bool
    let progress: Double
    let onDownload: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.subheadline)
                
                Text(size)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isDownloading {
                ProgressView(value: progress)
                    .frame(width: 60)
            } else {
                Button(action: onDownload) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    SampleVideosView()
}
