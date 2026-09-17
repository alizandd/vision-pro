import SwiftUI

/// A seek bar for a headset (or a whole group). Shows the live position while
/// idle, the finger's target while dragging, and sends exactly one seek when
/// the finger lifts. See `ScrubberModel` for the hold-after-release rule.
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
    /// The finger's position while dragging. Kept apart from `model` so the
    /// Slider binding never reads a value that is one render behind.
    @State private var dragValue: Double = 0

    private var shown: Double {
        model.isDragging ? dragValue : model.displayPosition(live: position)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let duration, duration > 0 {
                Slider(
                    value: Binding(
                        get: { shown },
                        set: { value in
                            dragValue = value
                            model.drag(to: value, duration: duration)
                        }
                    ),
                    in: 0...duration,
                    onEditingChanged: { editing in
                        if editing {
                            dragValue = shown
                            model.beginDrag(at: shown, duration: duration)
                        } else if let target = model.endDrag(now: Date()) {
                            onSeek(target)
                        }
                    }
                )
                .disabled(!isEnabled)
                .accessibilityLabel("Playback position")
                .accessibilityValue(formatPosition(shown))

                HStack {
                    Text(formatPosition(shown))
                    Spacer()
                    Text(formatDuration(duration))
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            } else {
                Slider(value: .constant(0), in: 0...1)
                    .disabled(true)
                    .accessibilityLabel("Playback position, running time not known yet")
                HStack {
                    Text("--:--")
                    Spacer()
                    Text("--:--")
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            if let hint, !isEnabled {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: position) { _, live in
            model.observe(live: live, now: Date())
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
