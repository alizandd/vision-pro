import SwiftUI
import AVFoundation

/// Shows what the headset wearer is watching: the paired flat companion video,
/// held in step with the headset, with a seek bar under it.
///
/// With no companion paired the picture is replaced by a one-line notice, but
/// the seek bar stays — it controls the headset, not the preview. Renders
/// nothing at all while the headset has no video loaded.
struct CompanionPreviewView: View {
    @ObservedObject var device: ConnectedDevice
    /// Observed directly (not through `deviceManager`) so the card re-renders
    /// the moment a group session starts or ends and greys its bar out.
    @ObservedObject var sync: SyncSessionManager
    @EnvironmentObject var deviceManager: DeviceManager

    @StateObject private var preview = CompanionPreviewPlayer()

    /// The companion paired to whatever the headset currently has loaded.
    private var pairedCompanion: CompanionVideo? {
        guard let filename = device.state.currentFilename,
              let id = deviceManager.pairingStore.companionId(forHeadsetFilename: filename) else {
            return nil
        }
        return deviceManager.companionLibrary.companion(withId: id)
    }

    private var isPlaying: Bool {
        device.state.playbackState == .playing
    }

    private var hasActiveVideo: Bool {
        switch device.state.playbackState {
        case .playing, .paused, .loading: return true
        default: return false
        }
    }

    /// True while this headset is an active member of a group session. Seeking
    /// one headset out of a running group would silently desync it, so the
    /// card's scrubber is read-only then and points at the group bar instead.
    private var isInActiveGroup: Bool {
        guard sync.state == .playing || sync.state == .paused else { return false }
        switch sync.deviceStatus[device.deviceId] {
        case .playing, .paused, .ready: return true
        default: return false
        }
    }

    private var scrubber: some View {
        PlaybackScrubber(
            position: position,
            duration: device.state.duration,
            isEnabled: !isInActiveGroup,
            hint: "Use the Synchronized Playback bar"
        ) { target in
            deviceManager.seek(deviceId: device.deviceId, to: target)
        }
    }

    var body: some View {
        Group {
            if let companion = pairedCompanion, hasActiveVideo {
                content(for: companion)
            } else if hasActiveVideo {
                unpairedNotice
            }
        }
        // The 10 Hz position feed used to be switched on only while a paired
        // preview was on screen. The scrubber needs it for every loaded video,
        // paired or not — and still nothing while the card shows no video.
        .onChange(of: hasActiveVideo, initial: true) { _, active in
            deviceManager.setPreviewSubscription(deviceId: device.deviceId, enabled: active)
        }
        .onDisappear {
            deviceManager.setPreviewSubscription(deviceId: device.deviceId, enabled: false)
            preview.teardown()
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private func content(for companion: CompanionVideo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Viewer Preview", systemImage: "eye")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let viewer = device.state.viewer, !viewer.isStale {
                    Text("LIVE")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red, in: Capsule())
                        .foregroundStyle(.white)
                        .accessibilityLabel("Live")
                }
            }

            if let reason = preview.withheldReason {
                withheldNotice(reason)
            } else {
                PlayerLayerView(player: preview.player)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.primary.opacity(0.08))
                    }
            }

            scrubber

            // Where the head is pointed — only meaningful for immersive
            // projections, so flat formats show nothing rather than a fake.
            if let range = device.state.currentFormat?.lookRange {
                ViewerDirectionIndicator(
                    yaw: device.state.viewer?.yaw ?? 0,
                    range: range,
                    isStale: device.state.viewer?.isStale ?? true
                )
            }

            Text(companion.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.top, 8)
        .task(id: companion.id) {
            start(companion)
        }
        .onChange(of: device.state.currentTime) { _, _ in tick() }
        .onChange(of: device.state.viewer?.mediaTime) { _, _ in tick() }
        .onChange(of: device.state.playbackState) { _, _ in tick() }
        // The running time usually arrives after playback has already begun, so
        // the length check has to run again when it does — not only on appear.
        .onChange(of: device.state.duration) { _, _ in
            verifyAndLoad(companion)
            tick()
        }
    }

    /// Where the wearer is in the video.
    ///
    /// Status updates only fire on state changes, so reading `currentTime` alone
    /// left this frozen at the start. viewerState carries a live media time at
    /// 10 Hz, so prefer it and fall back to status.
    private var position: Double {
        if let viewer = device.state.viewer, !viewer.isStale {
            return viewer.mediaTime
        }
        return device.state.currentTime
    }

    private var unpairedNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.on.rectangle.angled")
                    .foregroundStyle(.secondary)
                Text("No preview video — long-press the tile above to pair one.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            scrubber
        }
        .padding(.vertical, 8)
    }

    private func withheldNotice(_ reason: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Preview not shown")
                    .font(.caption.weight(.semibold))
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Driving

    private func start(_ companion: CompanionVideo) {
        verifyAndLoad(companion)
        tick()
    }

    /// Refuse to show a companion whose running time disagrees with the asset
    /// the headset actually loaded — it would sit on the wrong moment and look
    /// entirely convincing doing it. Safe to call repeatedly: loading the
    /// companion that is already loaded does nothing.
    private func verifyAndLoad(_ companion: CompanionVideo) {
        switch CompanionPairingStore.verify(
            companion: companion,
            againstHeadsetDuration: device.state.duration
        ) {
        case .mismatch(let headset, let companionDuration):
            preview.withhold(
                reason: "\(companion.displayName) runs \(formatDuration(companionDuration)) but the headset video runs \(formatDuration(headset)). Pair a preview cut to the same length."
            )
        case .verified, .unverified:
            preview.load(
                companion: companion,
                url: deviceManager.companionLibrary.url(for: companion)
            )
        }
    }

    /// Feeds the newest headset position into the player.
    private func tick() {
        guard preview.isReady else { return }

        // Viewer state arrives at 10 Hz and carries its own media time, which is
        // a far better sync source than the much slower status updates.
        if let viewer = device.state.viewer, !viewer.isStale {
            preview.sync(
                headsetTime: viewer.mediaTime,
                sampleAge: Date().timeIntervalSince(viewer.receivedAt),
                isPlaying: isPlaying
            )
        } else {
            preview.sync(
                headsetTime: device.state.currentTime,
                sampleAge: 0,
                isPlaying: isPlaying
            )
        }
    }
}

/// AVPlayerLayer without transport controls — this is a monitor, not a player
/// the operator scrubs.
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }
}

final class PlayerContainerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
