import Foundation
import Combine

/// How the two eye views are packed inside a single decoded video frame.
enum StereoFrameLayout: String {
    /// No stereo packing — a single image shown to both eyes (no depth).
    case mono
    /// Left eye = left half of the frame, right eye = right half.
    case sideBySide
    /// Left eye = top half of the frame, right eye = bottom half.
    case overUnder
    /// Native multi-layer stereo (MV-HEVC / spatial). The system splits eyes itself.
    case nativeStereo

    var displayName: String {
        switch self {
        case .mono: return "Mono (no depth)"
        case .sideBySide: return "Side-by-Side (SBS)"
        case .overUnder: return "Over-Under (OU)"
        case .nativeStereo: return "Native MV-HEVC / Spatial"
        }
    }
}

/// Manual override for which region of the texture maps onto the screen.
/// Used by the debug test mode to visually prove what each eye is being shown.
enum UVOverride: String, CaseIterable {
    case auto       // Use the mapping derived from the video format
    case full       // Entire frame
    case leftHalf   // Left half only
    case rightHalf  // Right half only
    case topHalf    // Top half only
    case bottomHalf // Bottom half only

    var displayName: String {
        switch self {
        case .auto: return "Auto (from format)"
        case .full: return "Full frame"
        case .leftHalf: return "Left half"
        case .rightHalf: return "Right half"
        case .topHalf: return "Top half"
        case .bottomHalf: return "Bottom half"
        }
    }
}

/// Snapshot of the currently loaded video's measurable properties.
/// This is what the on-screen diagnostics panel renders, and is the data
/// we use to figure out *what kind* of video the user is actually playing.
struct VideoDiagnostics: Equatable {
    var width: Int = 0
    var height: Int = 0
    var codec: String = "—"
    var hasNativeStereoMetadata: Bool = false
    var selectedFormat: String = "—"

    /// Frame aspect ratio (width / height). 0 when unknown.
    var aspectRatio: Double {
        guard height > 0 else { return 0 }
        return Double(width) / Double(height)
    }

    /// Best-effort guess of how the eyes are packed, derived from the
    /// aspect ratio and metadata. This is a *hint* — aspect ratio alone is
    /// ambiguous (e.g. 2:1 can be 360° mono OR 180° SBS), so the user can
    /// confirm using the live UV-mapping test.
    var suggestedLayout: StereoFrameLayout {
        if hasNativeStereoMetadata { return .nativeStereo }
        let ar = aspectRatio
        guard ar > 0 else { return .mono }
        // Each SBS eye doubles the width; each OU eye doubles the height.
        if ar >= 3.0 {
            // ~3.55 (16:9 per eye SBS) or ~4.0 (2:1 per eye 360 SBS)
            return .sideBySide
        } else if ar >= 1.7 {
            // ~2.0 — ambiguous: 360° mono equirect OR 180° SBS (square eyes).
            return .sideBySide
        } else if ar <= 0.75 {
            // Tall frame — eyes stacked vertically.
            return .overUnder
        }
        return .mono
    }

    var suggestedNote: String {
        switch suggestedLayout {
        case .nativeStereo:
            return "Native stereo metadata present — system handles per-eye automatically."
        case .sideBySide:
            return "Aspect \(String(format: "%.2f", aspectRatio)):1 suggests Side-by-Side. Note: 2:1 can also be 360° mono — confirm with the eye test below."
        case .overUnder:
            return "Tall aspect \(String(format: "%.2f", aspectRatio)) suggests Over-Under packing."
        case .mono:
            return "Aspect \(String(format: "%.2f", aspectRatio)) looks like a single (mono) image."
        }
    }
}

/// User-facing debug/test settings, persisted in UserDefaults.
///
/// IMPORTANT context for the test mode:
/// The visionOS *simulator renders only a single eye*, so true stereo depth
/// can never be observed in the simulator — only on a real Vision Pro.
/// What the simulator CAN show is the diagnostics panel (resolution, aspect,
/// detected packing, codec) and the result of live UV-mapping changes, which
/// is enough to identify *what* the video is and *what* each eye is being fed.
@MainActor
final class StereoDebugSettings: ObservableObject {
    static let shared = StereoDebugSettings()

    private enum Keys {
        static let testMode = "debug_test_mode_enabled"
        static let showDiagnostics = "debug_show_diagnostics"
        static let uvOverride = "debug_uv_override"
        static let trueStereo = "debug_true_stereo_enabled"
        static let eyeCompare = "debug_eye_compare_enabled"
    }

    /// Master switch for the whole debug/test experience.
    @Published var testModeEnabled: Bool {
        didSet { UserDefaults.standard.set(testModeEnabled, forKey: Keys.testMode) }
    }

    /// Whether to render the floating diagnostics panel in the immersive space.
    @Published var showDiagnostics: Bool {
        didSet { UserDefaults.standard.set(showDiagnostics, forKey: Keys.showDiagnostics) }
    }

    /// Force a specific region of the frame onto the screen, overriding the
    /// format-derived mapping. Lets the user/QA confirm left vs right halves.
    @Published var uvOverride: UVOverride {
        didSet { UserDefaults.standard.set(uvOverride.rawValue, forKey: Keys.uvOverride) }
    }

    /// Opt-in: render true per-eye stereo via APMP metadata injection
    /// (visionOS 26+). When off, the app uses the original single-texture path.
    /// Kept opt-in so the stable playback path is never disturbed.
    @Published var trueStereoEnabled: Bool {
        didSet { UserDefaults.standard.set(trueStereoEnabled, forKey: Keys.trueStereo) }
    }

    /// Debug-only: show the two eye source images side-by-side on flat panels
    /// so per-eye extraction can be verified on the SIMULATOR (which renders a
    /// single eye and therefore can't show true stereo). Remove later by
    /// turning this off — it never affects normal playback.
    @Published var eyeCompareEnabled: Bool {
        didSet { UserDefaults.standard.set(eyeCompareEnabled, forKey: Keys.eyeCompare) }
    }

    /// The live diagnostics for the currently prepared video.
    @Published var diagnostics: VideoDiagnostics = VideoDiagnostics()

    private init() {
        let defaults = UserDefaults.standard
        self.testModeEnabled = defaults.bool(forKey: Keys.testMode)
        // Default diagnostics panel ON when test mode is used.
        self.showDiagnostics = defaults.object(forKey: Keys.showDiagnostics) as? Bool ?? true
        let stored = defaults.string(forKey: Keys.uvOverride) ?? UVOverride.auto.rawValue
        self.uvOverride = UVOverride(rawValue: stored) ?? .auto
        // Default ON: true per-eye stereo (APMP) is the actual fix for "no depth".
        // The legacy single-texture path can never produce stereo depth, so we
        // opt in by default and let it fall back automatically when unsupported.
        self.trueStereoEnabled = defaults.object(forKey: Keys.trueStereo) as? Bool ?? true
        self.eyeCompareEnabled = defaults.bool(forKey: Keys.eyeCompare)
    }
}
