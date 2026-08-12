import Foundation

/// Links an immersive video on a headset to the flat companion video that
/// represents it on the controller.
///
/// Pairing is keyed by the headset's **filename**, so it holds across devices:
/// the same video transferred to three headsets uses one pairing.
@MainActor
final class CompanionPairingStore: ObservableObject {
    /// headset filename → companion id
    @Published private(set) var pairings: [String: String] = [:]

    /// Tolerance for the duration check. Companions are edited by hand, so a
    /// fraction of a second of encoder rounding is expected; a real recut is not.
    static let durationTolerance: Double = 0.5

    private let fileManager = FileManager.default

    private lazy var storeURL: URL = {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("companion-pairings.json")
    }()

    init() {
        load()
    }

    // MARK: - Queries

    func companionId(forHeadsetFilename filename: String) -> String? {
        pairings[filename]
    }

    func isPaired(headsetFilename: String) -> Bool {
        pairings[headsetFilename] != nil
    }

    // MARK: - Mutations

    func pair(headsetFilename: String, companionId: String) {
        pairings[headsetFilename] = companionId
        save()
        print("[CompanionPairing] Paired \(headsetFilename) → \(companionId)")
    }

    func unpair(headsetFilename: String) {
        pairings.removeValue(forKey: headsetFilename)
        save()
        print("[CompanionPairing] Unpaired \(headsetFilename)")
    }

    /// Drops pairings whose companion no longer exists in the library.
    func prune(against library: CompanionLibrary) {
        let liveIds = Set(library.items.map(\.id))
        let stale = pairings.filter { !liveIds.contains($0.value) }
        guard !stale.isEmpty else { return }
        for key in stale.keys { pairings.removeValue(forKey: key) }
        save()
        print("[CompanionPairing] Pruned \(stale.count) pairing(s) with missing companions")
    }

    // MARK: - Verification

    /// Whether a companion may be shown for a headset asset of a given duration.
    enum Verification: Equatable {
        /// Durations agree — safe to show.
        case verified
        /// Durations disagree; showing this would put the operator on the wrong
        /// moment, so the preview is withheld.
        case mismatch(headset: Double, companion: Double)
        /// The headset has not reported a duration yet (or runs an older build).
        case unverified

        var allowsPlayback: Bool {
            switch self {
            case .verified, .unverified: return true
            case .mismatch: return false
            }
        }
    }

    /// Compares a companion against the duration the headset reported for the
    /// asset it actually loaded — the real thing, not a filename guess.
    static func verify(companion: CompanionVideo, againstHeadsetDuration headsetDuration: Double?) -> Verification {
        guard let headsetDuration, headsetDuration.isFinite, headsetDuration > 0 else {
            return .unverified
        }
        let delta = abs(headsetDuration - companion.duration)
        return delta <= durationTolerance
            ? .verified
            : .mismatch(headset: headsetDuration, companion: companion.duration)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            pairings = [:]
            return
        }
        pairings = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(pairings) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}

/// Formats a duration for the operator.
func formatDuration(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds > 0 else { return "--:--" }
    let total = Int(seconds.rounded())
    let h = total / 3600, m = (total % 3600) / 60, s = total % 60
    return h > 0
        ? String(format: "%d:%02d:%02d", h, m, s)
        : String(format: "%d:%02d", m, s)
}
