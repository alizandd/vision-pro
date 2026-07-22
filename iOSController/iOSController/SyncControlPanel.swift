import SwiftUI

/// Group-control panel for synchronized playback across all connected devices.
/// Shows the videos available on every device, a format picker, and
/// play/pause/resume/stop-all controls with per-device session status.
struct SyncControlPanel: View {
    @EnvironmentObject var deviceManager: DeviceManager
    @ObservedObject var syncManager: SyncSessionManager

    @State private var selectedFilename: String = ""
    @State private var selectedFormat: VideoFormat = .sphere360SBS

    /// Videos present on ALL connected devices (intersection by filename)
    private var commonVideos: [String] {
        let videoSets = deviceManager.devices.map { Set($0.localVideos.map(\.filename)) }
        guard let first = videoSets.first else { return [] }
        return Array(videoSets.dropFirst().reduce(first) { $0.intersection($1) }).sorted()
    }

    private var isSessionActive: Bool {
        syncManager.state != .idle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "play.square.stack")
                    .foregroundColor(.purple)
                Text("Synchronized Playback")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                stateBadge
            }

            if commonVideos.isEmpty {
                // Empty state: no video exists on every device
                VStack(alignment: .leading, spacing: 4) {
                    Text("No videos available on all devices")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Transfer the same video to every Vision Pro first (share button above).")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else {
                // Video + format pickers
                HStack(spacing: 8) {
                    Menu {
                        ForEach(commonVideos, id: \.self) { filename in
                            Button(filename) { selectedFilename = filename }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "film")
                            Text(selectedFilename.isEmpty ? "Select video" : selectedFilename)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                        }
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray5))
                        .cornerRadius(8)
                    }
                    .disabled(isSessionActive)

                    Menu {
                        ForEach(VideoFormat.allCases, id: \.self) { format in
                            Button(format.displayName) { selectedFormat = format }
                        }
                    } label: {
                        HStack {
                            Text(selectedFormat.displayName)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                        }
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray5))
                        .cornerRadius(8)
                    }
                    .disabled(isSessionActive)

                    Spacer()
                }

                // Group controls
                HStack(spacing: 10) {
                    switch syncManager.state {
                    case .idle:
                        Button {
                            let targets = deviceManager.devices.map(\.deviceId)
                            let filename = selectedFilename
                            let format = selectedFormat
                            Task {
                                await syncManager.playOnAll(
                                    filename: filename,
                                    format: format,
                                    deviceIds: targets
                                )
                            }
                        } label: {
                            Label("Play on All", systemImage: "play.fill")
                                .font(.subheadline)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                        .disabled(selectedFilename.isEmpty)

                    case .syncingClocks, .preparing:
                        ProgressView()
                            .controlSize(.small)
                        Text(syncManager.state == .syncingClocks ? "Syncing clocks…" : "Preparing devices…")
                            .font(.caption)
                            .foregroundColor(.secondary)

                    case .playing:
                        Button {
                            syncManager.pauseAll()
                        } label: {
                            Label("Pause All", systemImage: "pause.fill")
                                .font(.subheadline)
                        }
                        .buttonStyle(.bordered)

                    case .paused:
                        Button {
                            syncManager.resumeAll()
                        } label: {
                            Label("Resume All", systemImage: "play.fill")
                                .font(.subheadline)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                    }

                    if isSessionActive && syncManager.state != .syncingClocks {
                        Button {
                            syncManager.stopAll()
                        } label: {
                            Label("Stop All", systemImage: "stop.fill")
                                .font(.subheadline)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }

                    Spacer()
                }

                // Per-device status chips during an active session
                if isSessionActive && !syncManager.deviceStatus.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(deviceManager.devices) { device in
                                if let status = syncManager.deviceStatus[device.deviceId] {
                                    DeviceSyncChip(name: device.deviceName, status: status)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
        .padding(.top, 8)
        .onChange(of: commonVideos) { _, videos in
            if !videos.contains(selectedFilename) {
                selectedFilename = videos.first ?? ""
            }
        }
        .onAppear {
            if selectedFilename.isEmpty {
                selectedFilename = commonVideos.first ?? ""
            }
        }
    }

    private var stateBadge: some View {
        Group {
            switch syncManager.state {
            case .idle:
                EmptyView()
            case .syncingClocks:
                badge("SYNCING", color: .orange)
            case .preparing:
                badge("PREPARING", color: .orange)
            case .playing:
                badge("PLAYING", color: .green)
            case .paused:
                badge("PAUSED", color: .yellow)
            }
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.bold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(6)
    }
}

/// Small chip showing one device's status within a sync session
struct DeviceSyncChip: View {
    let name: String
    let status: SyncSessionManager.DeviceSyncStatus

    var body: some View {
        HStack(spacing: 4) {
            statusIcon
            Text(name)
                .font(.caption2)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.systemGray5))
        .cornerRadius(6)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .measuringClock:
            Image(systemName: "clock").font(.caption2).foregroundColor(.orange)
        case .preparing:
            ProgressView().controlSize(.mini)
        case .ready:
            Image(systemName: "checkmark.circle.fill").font(.caption2).foregroundColor(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill").font(.caption2).foregroundColor(.red)
        case .playing:
            Image(systemName: "play.circle.fill").font(.caption2).foregroundColor(.green)
        case .paused:
            Image(systemName: "pause.circle.fill").font(.caption2).foregroundColor(.yellow)
        }
    }
}
