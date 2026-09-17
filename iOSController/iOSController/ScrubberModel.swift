import Foundation

/// The drag and hold-after-release logic behind `PlaybackScrubber`.
///
/// Kept free of SwiftUI so it can be exercised by `Tests/run.sh` with plain
/// swiftc. The view owns one of these and feeds it the live position; this
/// decides what the thumb should show.
///
/// Three phases:
/// - `following`: the thumb tracks the headset's live position.
/// - `dragging`: the thumb tracks the finger; nothing is sent.
/// - `holding`: the finger lifted and the seek was sent, but the headset has
///   not caught up yet. The thumb stays at the target so it does not snap
///   back to the stale position for the half-second before the seek lands.
struct ScrubberModel: Equatable {
    enum Phase: Equatable {
        case following
        case dragging(target: Double)
        case holding(target: Double, since: Date)
    }

    /// A live position this close to the target counts as "the seek landed".
    static let holdTolerance: Double = 1.0
    /// A hold never outlives this, even if no confirming position arrives.
    static let holdTimeout: TimeInterval = 2.0

    private(set) var phase: Phase = .following

    var isDragging: Bool {
        if case .dragging = phase { return true }
        return false
    }

    static func clamp(_ time: Double, duration: Double) -> Double {
        guard duration.isFinite, duration > 0 else { return 0 }
        return min(max(time, 0), duration)
    }

    mutating func beginDrag(at time: Double, duration: Double) {
        phase = .dragging(target: Self.clamp(time, duration: duration))
    }

    mutating func drag(to time: Double, duration: Double) {
        phase = .dragging(target: Self.clamp(time, duration: duration))
    }

    /// Ends the drag. Returns the time to send to the headset, or nil when no
    /// drag was in progress.
    mutating func endDrag(now: Date) -> Double? {
        guard case .dragging(let target) = phase else { return nil }
        phase = .holding(target: target, since: now)
        return target
    }

    /// Feed the newest live position. Releases the hold once the headset has
    /// caught up, or once the hold has outlived its timeout.
    mutating func observe(live: Double, now: Date) {
        guard case .holding(let target, let since) = phase else { return }
        if abs(live - target) <= Self.holdTolerance || now.timeIntervalSince(since) >= Self.holdTimeout {
            phase = .following
        }
    }

    /// The position the thumb should show for this live position.
    func displayPosition(live: Double) -> Double {
        switch phase {
        case .following: return live
        case .dragging(let target), .holding(let target, _): return target
        }
    }
}
