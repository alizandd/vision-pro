import Foundation
import AVFoundation
import Combine

/// Plays the flat companion video in step with what a headset is showing.
///
/// The companion runs on its own clock and is *corrected* toward the headset's
/// reported position rather than seeked on every update — seeking ten times a
/// second would stutter and look broken. See
/// `docs/adr/2026-08-12-controller-live-preview.md`.
@MainActor
final class CompanionPreviewPlayer: ObservableObject {
    @Published private(set) var isReady: Bool = false
    /// Set when the preview is deliberately withheld — better a stated reason
    /// than a confident, wrong picture.
    @Published private(set) var withheldReason: String?

    let player = AVPlayer()

    /// Companion currently loaded, so we don't rebuild the item needlessly.
    private(set) var loadedCompanionId: String?

    /// Drift under this is ignored — correcting it would be visible churn.
    private let deadband: Double = 0.3
    /// Drift under this is absorbed by nudging the rate; beyond it we seek.
    private let nudgeCeiling: Double = 1.0
    private let nudgeRate: Float = 0.06

    private var isSeeking = false

    init() {
        // The wearer hears the real soundtrack; a second one from the operator's
        // tablet would be noise in the room.
        player.isMuted = true
        player.actionAtItemEnd = .pause
        player.automaticallyWaitsToMinimizeStalling = false
    }

    // MARK: - Lifecycle

    /// Loads a companion, replacing whatever was playing.
    func load(companion: CompanionVideo, url: URL) {
        guard loadedCompanionId != companion.id else { return }
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        player.isMuted = true
        loadedCompanionId = companion.id
        withheldReason = nil
        isReady = true
        print("[CompanionPreview] Loaded \(companion.displayName)")
    }

    /// Withholds the preview with a reason the operator can act on.
    func withhold(reason: String) {
        guard withheldReason != reason else { return }
        teardown()
        withheldReason = reason
        print("[CompanionPreview] Withheld: \(reason)")
    }

    /// Releases the player. Called when the card collapses, the device
    /// disconnects, or the pairing goes away.
    func teardown() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        loadedCompanionId = nil
        isReady = false
        withheldReason = nil
    }

    // MARK: - Synchronisation

    /// Brings the preview in line with the headset.
    ///
    /// - Parameters:
    ///   - headsetTime: media position the headset last reported.
    ///   - sampleAge: how long ago that report was received. While the headset
    ///     is playing, its real position has moved on by this much, so it is
    ///     added rather than chasing a stale target. This is measured locally,
    ///     which avoids depending on a clock-offset measurement that only exists
    ///     after a sync session has run.
    ///   - isPlaying: whether the headset is playing right now.
    func sync(headsetTime: Double, sampleAge: Double, isPlaying: Bool) {
        guard isReady, player.currentItem != nil else { return }

        let target = isPlaying ? headsetTime + max(0, sampleAge) : headsetTime

        guard isPlaying else {
            if player.rate != 0 { player.pause() }
            seek(to: target)
            return
        }

        let current = player.currentTime().seconds
        guard current.isFinite else { return }

        let drift = current - target

        if abs(drift) > nudgeCeiling {
            seek(to: target)
            player.playImmediately(atRate: 1.0)
            return
        }

        if player.rate == 0 {
            player.playImmediately(atRate: 1.0)
        }

        if abs(drift) <= deadband {
            // Close enough — leave it alone, any correction would be visible.
            if player.rate != 1.0 { player.rate = 1.0 }
        } else {
            // Ease back into place instead of jumping.
            player.rate = drift > 0 ? 1.0 - nudgeRate : 1.0 + nudgeRate
        }
    }

    private func seek(to time: Double) {
        guard !isSeeking else { return }
        isSeeking = true
        let target = CMTime(seconds: max(0, time), preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in self?.isSeeking = false }
        }
    }
}
