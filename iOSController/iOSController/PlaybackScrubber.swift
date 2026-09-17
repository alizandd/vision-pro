import SwiftUI

/// A seek bar for a headset (or a whole group). Shows the live position while
/// idle, the finger's target while dragging, and sends exactly one seek when
/// the finger lifts. See `ScrubberModel` for the hold-after-release rule.
///
/// Drawn by hand rather than with `Slider`: on iPadOS 26 the slider's
/// `onEditingChanged(false)` did not reliably fire at the end of a drag, which
/// left the thumb stuck and no seek sent. A `DragGesture` ends dependably, and
/// it lets the operator grab anywhere on the track instead of hunting for a
/// thumb that is moving while the video plays.
struct PlaybackScrubber: View {
    let position: Double
    /// Nil while the headset has not reported a running time — the bar is then
    /// disabled and shows dashes rather than guessing.
    let duration: Double?
    var isEnabled: Bool = true
    /// Shown under the bar when it is disabled, to say why.
    var hint: String? = nil
    let onSeek: (Double) -> Void

    @State private var model = ScrubberModel()

    private let trackHeight: CGFloat = 6
    private let thumbSize: CGFloat = 22
    private let hitHeight: CGFloat = 32

    private var isUsable: Bool {
        isEnabled && (duration ?? 0) > 0
    }

    private var shown: Double {
        model.displayPosition(live: position)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            track
                .frame(height: hitHeight)

            HStack {
                Text(duration == nil ? "--:--" : formatPosition(shown))
                Spacer()
                Text(formatDuration(duration ?? 0))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)

            if let hint, !isEnabled {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(isUsable ? 1 : 0.5)
        .onChange(of: position) { _, live in
            model.observe(live: live, now: Date())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playback position")
        .accessibilityValue(duration == nil ? "running time not known yet" : formatPosition(shown))
        .accessibilityAdjustableAction { direction in
            guard isUsable, let duration else { return }
            let step: Double = direction == .increment ? 10 : -10
            onSeek(ScrubberModel.clamp(shown + step, duration: duration))
        }
    }

    private var track: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let fraction = (duration ?? 0) > 0 ? CGFloat(shown / duration!) : 0
            let thumbX = fraction * width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.systemFill))
                    .frame(height: trackHeight)
                Capsule()
                    .fill(isUsable ? Color.accentColor : Color.secondary)
                    .frame(width: max(thumbX, trackHeight), height: trackHeight)
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .frame(width: thumbSize, height: thumbSize)
                    .offset(x: min(max(thumbX - thumbSize / 2, 0), width - thumbSize))
            }
            .frame(width: width, height: hitHeight)
            .contentShape(Rectangle())
            .gesture(isUsable ? dragGesture(width: width) : nil)
        }
    }

    /// Any touch on the track starts a drag; a plain tap is a zero-length drag
    /// and seeks to the tapped point on release, which is what operators expect.
    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let duration else { return }
                let time = Double(value.location.x / width) * duration
                if !model.isDragging {
                    model.beginDrag(at: time, duration: duration)
                } else {
                    model.drag(to: time, duration: duration)
                }
            }
            .onEnded { _ in
                if let target = model.endDrag(now: Date()) {
                    onSeek(target)
                }
            }
    }
}

#Preview {
    VStack(spacing: 24) {
        PlaybackScrubber(position: 53, duration: 252) { _ in }
        PlaybackScrubber(position: 0, duration: nil) { _ in }
        PlaybackScrubber(position: 90, duration: 252, isEnabled: false, hint: "Use the Synchronized Playback bar") { _ in }
    }
    .padding()
}
