import SwiftUI

/// Group-control panel for synchronized playback across all connected devices.
/// Shows the videos available on every device, a format picker, and
/// play/pause/resume/stop-all controls with per-device session status.
struct SyncControlPanel: View {
    @EnvironmentObject var deviceManager: DeviceManager
    @ObservedObject var syncManager: SyncSessionManager

    @State private var selectedFilename: String = ""
    @State private var selectedFormat: VideoFormat = .sphere360SBS
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// How many video rows to show before the list starts scrolling.
    ///
    /// A phone can only spare a few, and the half-row is a deliberate hint that
    /// there is more below. A tablet has the height to show a realistic library
    /// outright — clipping the 4th item there just hides content behind an
    /// inner scroll that reads as the page scroll.
    private var visibleVideoRows: CGFloat {
        horizontalSizeClass == .regular ? 8.5 : 3.5
    }

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
                VStack(spacing: 8) {
                    Image(systemName: "film.stack")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("No videos available on all devices")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    Text("Transfer the same video to every headset first using the share button above.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                // Readable, selectable video list
                Text("Videos on all devices".uppercased())
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(commonVideos, id: \.self) { filename in
                            SyncVideoRow(
                                filename: filename,
                                size: videoSize(for: filename),
                                isSelected: selectedFilename == filename,
                                isDisabled: isSessionActive
                            ) {
                                selectedFilename = filename
                            }
                        }
                    }
                    // These rows put a small icon on the left and a selection
                    // circle on the right. Across a tablet's full width the two
                    // end up a screen apart and stop reading as one row, so hold
                    // the list to a measure the eye can span. No-op on a phone.
                    .frame(maxWidth: Layout.maxReadableWidth, alignment: .leading)
                }
                .frame(height: min(CGFloat(commonVideos.count), visibleVideoRows) * 64)

                // Format picker, visually separated from the list
                HStack(spacing: 8) {
                    Text("Format")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Menu {
                        ForEach(VideoFormat.allCases, id: \.self) { format in
                            Button {
                                selectedFormat = format
                            } label: {
                                if format == selectedFormat {
                                    Label(format.displayName, systemImage: "checkmark")
                                } else {
                                    Text(format.displayName)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(selectedFormat.displayName)
                                .fontWeight(.medium)
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

                // Group seek bar — the whole session's position, only while it runs
                if syncManager.state == .playing || syncManager.state == .paused {
                    PlaybackScrubber(
                        position: syncManager.groupPosition,
                        duration: syncManager.groupDuration,
                        isEnabled: !syncManager.isRestartPending,
                        hint: "Restarting the group…"
                    ) { target in
                        syncManager.seekAll(to: target)
                    }
                    .padding(.vertical, 4)
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

    /// File size of a common video, read from the first device that has it
    private func videoSize(for filename: String) -> Int64? {
        for device in deviceManager.devices {
            if let video = device.localVideos.first(where: { $0.filename == filename }) {
                return video.size
            }
        }
        return nil
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

/// One selectable row in the sync panel's video list.
/// Shows a cleaned-up, human-readable name plus the file size.
struct SyncVideoRow: View {
    let filename: String
    let size: Int64?
    let isSelected: Bool
    let isDisabled: Bool
    let action: () -> Void

    /// "1140_SCOPE_360sbs_test_meta.mp4" → "1140 SCOPE 360sbs test meta"
    private var displayName: String {
        (filename as NSString).deletingPathExtension
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }

    private var fileExtension: String {
        (filename as NSString).pathExtension.uppercased()
    }

    private var sizeText: String? {
        size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "film")
                    .font(.subheadline)
                    .foregroundColor(isSelected ? .purple : .secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.subheadline)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    HStack(spacing: 6) {
                        if !fileExtension.isEmpty {
                            Text(fileExtension)
                                .font(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color(.systemGray4))
                                .cornerRadius(3)
                        }
                        if let sizeText {
                            Text(sizeText)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundColor(isSelected ? .purple : Color(.systemGray3))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? Color.purple.opacity(0.1) : Color(.systemGray5).opacity(0.6))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.purple.opacity(0.5) : Color.clear, lineWidth: 1)
            )
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
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
        case .ended:
            Image(systemName: "flag.checkered").font(.caption2).foregroundColor(.secondary)
        }
    }
}
