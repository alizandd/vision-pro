import SwiftUI
import PhotosUI

/// Manages the flat companion videos used to preview what a headset viewer is
/// watching. Import from Photos or from Files (iCloud Drive, an external drive,
/// any provider the Files app can reach).
struct CompanionLibraryView: View {
    @ObservedObject var library: CompanionLibrary
    @Environment(\.dismiss) private var dismiss

    @State private var photosSelection: [PhotosPickerItem] = []
    @State private var showFileImporter = false
    @State private var pendingDeletion: CompanionVideo?

    var body: some View {
        NavigationStack {
            Group {
                if library.items.isEmpty && !library.importState.isImporting {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Preview Videos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    addMenu
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    Task {
                        for url in urls { await library.importFile(from: url) }
                    }
                case .failure(let error):
                    print("[CompanionLibraryView] File import failed: \(error)")
                }
            }
            .onChange(of: photosSelection) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    for item in items { await library.importPhotosItem(item) }
                    photosSelection = []
                }
            }
            .alert(
                "Remove preview video?",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                presenting: pendingDeletion
            ) { target in
                Button("Cancel", role: .cancel) { pendingDeletion = nil }
                Button("Remove", role: .destructive) {
                    library.delete(target)
                    pendingDeletion = nil
                }
            } message: { target in
                Text("\(target.displayName) will be deleted from this device. Any headset video paired to it falls back to showing the timeline only.")
            }
        }
    }

    // MARK: - Pieces

    private var addMenu: some View {
        Menu {
            PhotosPicker(selection: $photosSelection, maxSelectionCount: 5, matching: .videos) {
                Label("From Photos", systemImage: "photo.on.rectangle")
            }
            Button {
                showFileImporter = true
            } label: {
                Label("From Files or a Drive", systemImage: "folder")
            }
        } label: {
            Label("Add", systemImage: "plus")
        }
        .disabled(library.importState.isImporting)
    }

    private var list: some View {
        List {
            if case .importing(let name, let progress) = library.importState {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Importing \(name)")
                            .font(.subheadline)
                        ProgressView(value: progress)
                        Text("\(Int(progress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Importing \(name), \(Int(progress * 100)) percent complete")
                }
            }

            if case .failed(let message) = library.importState {
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Import failed").font(.subheadline.weight(.semibold))
                            Text(message).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Dismiss") { library.clearError() }
                            .font(.caption)
                    }
                }
            }

            Section {
                ForEach(library.items) { companion in
                    CompanionRow(companion: companion, thumbnailURL: library.thumbnailURL(for: companion))
                        .swipeActions {
                            Button(role: .destructive) {
                                pendingDeletion = companion
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                }
            } footer: {
                Text("A preview video must have the same running time as the immersive video it represents. Different lengths would show the operator the wrong moment.")
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No preview videos", systemImage: "rectangle.on.rectangle.angled")
        } description: {
            Text("Add a flat version of an immersive video and the controller can show you what the headset viewer is watching, in step with them.\n\nIt must be the same length as the immersive original.")
        } actions: {
            Menu {
                PhotosPicker(selection: $photosSelection, maxSelectionCount: 5, matching: .videos) {
                    Label("From Photos", systemImage: "photo.on.rectangle")
                }
                Button {
                    showFileImporter = true
                } label: {
                    Label("From Files or a Drive", systemImage: "folder")
                }
            } label: {
                Text("Add a Preview Video")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

/// One row in the companion library.
struct CompanionRow: View {
    let companion: CompanionVideo
    let thumbnailURL: URL

    /// Loaded once off the render path rather than re-read from disk on every
    /// layout pass.
    @State private var thumbnail: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            thumbnailView
            VStack(alignment: .leading, spacing: 4) {
                Text(companion.displayName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .truncationMode(.middle)
                Text("\(companion.formattedDuration) · \(companion.formattedSize)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(companion.displayName), \(companion.formattedDuration)")
        .task {
            guard thumbnail == nil else { return }
            let url = thumbnailURL
            thumbnail = await Task.detached {
                guard let data = try? Data(contentsOf: url) else { return nil as UIImage? }
                return UIImage(data: data)
            }.value
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let image = thumbnail {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 76, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.tertiarySystemFill))
                .frame(width: 76, height: 44)
                .overlay {
                    Image(systemName: "film")
                        .foregroundStyle(.secondary)
                }
        }
    }
}

#Preview {
    CompanionLibraryView(library: CompanionLibrary())
}
