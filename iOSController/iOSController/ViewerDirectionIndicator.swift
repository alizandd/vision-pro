import SwiftUI

/// Shows where the wearer is looking within the content.
///
/// The companion video shows what the *content* contains; this shows where the
/// *head* is pointed. In 360° material the two can disagree completely — the
/// wearer may be facing away from whatever the editor framed — and without this
/// the operator would never know.
///
/// Deliberately draws nothing for flat formats: on a fixed screen there is no
/// meaningful look direction, and drawing one anyway would be invented data.
struct ViewerDirectionIndicator: View {
    /// Look direction in radians, 0 = centre of the content.
    let yaw: Double
    /// Full angular extent of the content (π for 180°, 2π for 360°).
    let range: Double
    /// True when reports have stopped arriving.
    let isStale: Bool

    private var normalized: Double {
        // Map yaw into −0.5…0.5 of the content extent, wrapping for 360°.
        var value = yaw
        let half = range / 2
        if range >= 2 * .pi - 0.001 {
            while value > .pi { value -= 2 * .pi }
            while value < -.pi { value += 2 * .pi }
        }
        return max(-1, min(1, value / half))
    }

    /// Whether the wearer has turned outside the content entirely — only
    /// possible with 180° material, and worth saying plainly.
    private var isLookingAway: Bool {
        range < 2 * .pi - 0.001 && abs(yaw) > range / 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let centre = width / 2
                let x = centre + normalized * centre

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.10))
                        .frame(height: 6)

                    // Centre tick: where the content is framed.
                    Rectangle()
                        .fill(Color.primary.opacity(0.35))
                        .frame(width: 1.5, height: 12)
                        .position(x: centre, y: 6)

                    Image(systemName: isLookingAway ? "exclamationmark.triangle.fill" : "eye.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(markerColor)
                        .position(x: x, y: 6)
                        .animation(.easeOut(duration: 0.18), value: normalized)
                }
                .frame(height: 12)
            }
            .frame(height: 12)

            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Viewer direction")
        .accessibilityValue(accessibilityDescription)
    }

    private var markerColor: Color {
        if isStale { return .secondary }
        return isLookingAway ? .orange : .accentColor
    }

    private var caption: String {
        if isStale { return "Direction not updating" }
        if isLookingAway { return "Looking away from the video" }
        let degrees = Int((yaw * 180 / .pi).rounded())
        if abs(degrees) <= 8 { return "Facing the centre" }
        return degrees > 0
            ? "Looking \(abs(degrees))° right of centre"
            : "Looking \(abs(degrees))° left of centre"
    }

    /// Spoken form — never relies on the marker's position or colour alone.
    private var accessibilityDescription: String {
        if isStale { return "Direction not updating" }
        if isLookingAway { return "Looking away from the video" }
        let degrees = Int((yaw * 180 / .pi).rounded())
        if abs(degrees) <= 8 { return "Facing the centre of the video" }
        return degrees > 0
            ? "\(abs(degrees)) degrees right of centre"
            : "\(abs(degrees)) degrees left of centre"
    }
}

#Preview {
    VStack(spacing: 24) {
        ViewerDirectionIndicator(yaw: 0, range: .pi, isStale: false)
        ViewerDirectionIndicator(yaw: 0.7, range: .pi, isStale: false)
        ViewerDirectionIndicator(yaw: 2.6, range: .pi, isStale: false)
        ViewerDirectionIndicator(yaw: -1.2, range: 2 * .pi, isStale: false)
        ViewerDirectionIndicator(yaw: 0.4, range: 2 * .pi, isStale: true)
    }
    .padding()
}
