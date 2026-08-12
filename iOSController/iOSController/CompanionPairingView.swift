import SwiftUI

/// Choose which flat preview video represents an immersive video on a headset.
///
/// A base-filename match is only ever *suggested* — the operator confirms it.
/// Nothing is paired silently, because a wrong pairing shows a confident,
/// plausible, and completely wrong picture.
struct CompanionPairingView: View {
    let headsetVideo: LocalVideo
    /// Duration the headset last reported for this asset, when known.
    let headsetDuration: Double?

    @ObservedObject var library: CompanionLibrary
    @ObservedObject var pairings: CompanionPairingStore

    @Environment(\.dismiss) private var dismiss
    @State private var rejected: RejectedPairing?

    private struct RejectedPairing: Identifiable {
        let id = UUID()
        let name: String
        let headset: Double
        let companion: Double
    }

    private var currentCompanion: CompanionVideo? {
        pairings.companionId(forHeadsetFilename: headsetVideo.filename)
            .flatMap { library.companion(withId: $0) }
    }

    private var suggestion: CompanionVideo? {
        guard currentCompanion == nil else { return nil }
        return library.suggestedCompanion(forHeadsetFilename: headsetVideo.filename)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(headsetVideo.name)
                            .font(.subheadline.weight(.semibold))
                        Text(headsetVideo.filename)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .truncationMode(.middle)
                            .lineLimit(1)
                        if let headsetDuration {
                            Text("Running time \(formatDuration(headsetDuration))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        } else {
                            Text("Running time not reported yet — it is checked the first time this video plays.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                } header: {
                    Text("Headset video")
                }

                if let suggestion {
                    Section {
                        Button {
                            apply(suggestion)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "wand.and.stars")
                                    .foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Use \(suggestion.displayName)")
                                        .font(.subheadline.weight(.medium))
                                    Text("Matches by name · \(suggestion.formattedDuration)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text("Suggested")
                    } footer: {
                        Text("Suggested because the file names match. Confirm it — the names matching does not prove the content does.")
                    }
                }

                Section {
                    if library.items.isEmpty {
                        Text("No preview videos on this device yet. Add one from the Preview Videos screen.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(library.items) { companion in
                        Button {
                            apply(companion)
                        } label: {
                            HStack(spacing: 12) {
                                CompanionRow(
                                    companion: companion,
                                    thumbnailURL: library.thumbnailURL(for: companion)
                                )
                                if companion.id == currentCompanion?.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .trailing) {
                            verdictLabel(for: companion)
                        }
                    }
                } header: {
                    Text("Preview videos on this device")
                }

                if currentCompanion != nil {
                    Section {
                        Button(role: .destructive) {
                            pairings.unpair(headsetFilename: headsetVideo.filename)
                            dismiss()
                        } label: {
                            Label("Remove pairing", systemImage: "xmark.circle")
                        }
                    } footer: {
                        Text("Without a pairing the device card shows the timeline only — never a picture that might be wrong.")
                    }
                }
            }
            .navigationTitle("Preview Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert(
                "Running times do not match",
                isPresented: Binding(
                    get: { rejected != nil },
                    set: { if !$0 { rejected = nil } }
                ),
                presenting: rejected
            ) { _ in
                Button("OK", role: .cancel) { rejected = nil }
            } message: { detail in
                Text("The headset video runs \(formatDuration(detail.headset)) but \(detail.name) runs \(formatDuration(detail.companion)).\n\nPairing them would put the preview on the wrong moment, so it has not been paired. Use a preview cut to exactly the same length.")
            }
        }
    }

    /// Applies a pairing, refusing outright when the durations disagree.
    private func apply(_ companion: CompanionVideo) {
        switch CompanionPairingStore.verify(companion: companion, againstHeadsetDuration: headsetDuration) {
        case .mismatch(let headset, let companionDuration):
            rejected = RejectedPairing(
                name: companion.displayName,
                headset: headset,
                companion: companionDuration
            )
        case .verified, .unverified:
            pairings.pair(headsetFilename: headsetVideo.filename, companionId: companion.id)
            dismiss()
        }
    }

    /// Marks entries that cannot be paired, so the operator sees why before tapping.
    @ViewBuilder
    private func verdictLabel(for companion: CompanionVideo) -> some View {
        if case .mismatch = CompanionPairingStore.verify(companion: companion, againstHeadsetDuration: headsetDuration) {
            Text("Length differs")
                .font(.caption2)
                .foregroundStyle(.orange)
                .accessibilityLabel("Cannot pair, running time differs")
        }
    }
}
