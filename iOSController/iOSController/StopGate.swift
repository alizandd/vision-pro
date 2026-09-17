import Foundation

/// The two rules behind "stop the previous video fully before the next one".
///
/// Pure so `Tests/run.sh` can exercise them. See
/// docs/superpowers/specs/2026-09-17-stop-before-switch-design.md.
enum StopGate {
    /// A headset that still has something loaded, or still has its immersive
    /// view open, must be stopped before it is told to play something else.
    static func isBusy(state: PlaybackState, immersive: Bool) -> Bool {
        switch state {
        case .playing, .paused, .loading: return true
        default: return immersive
        }
    }

    /// Stopped only counts once the immersive view is closed too. The headset
    /// reports `stopped` before it starts closing the view, and a `play` that
    /// lands during that teardown is exactly the race being removed.
    static func isFullyStopped(state: PlaybackState, immersive: Bool) -> Bool {
        (state == .stopped || state == .idle) && !immersive
    }
}
