import Foundation
import AVFoundation
import UIKit
import PhotosUI
import SwiftUI

/// A flat, mono "companion" video stored on the controller.
///
/// Companions are the operator-facing mirror of an immersive video playing on a
/// Vision Pro: same running time, ordinary 2D framing, small enough to sit on a
/// phone. See `docs/adr/2026-08-12-controller-live-preview.md`.
struct CompanionVideo: Identifiable, Codable, Hashable {
    let id: String
    /// File name on disk inside the library directory.
    let storedFilename: String
    /// Name shown to the operator (the original file name).
    let displayName: String
    let duration: Double
    let fileSize: Int64
    let addedAt: Date

    /// Name without extension — used to suggest a pairing.
    var baseName: String {
        (displayName as NSString).deletingPathExtension
    }

    var formattedDuration: String {
        guard duration.isFinite, duration > 0 else { return "--:--" }
        let total = Int(duration.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

/// On-device library of companion videos, persisted across launches.
///
/// Files live in Application Support (not Documents) because they are app data
/// the operator manages through this UI, not documents to be exposed over file
/// sharing.
@MainActor
final class CompanionLibrary: ObservableObject {
    @Published private(set) var items: [CompanionVideo] = []
    @Published private(set) var importState: ImportState = .idle

    enum ImportState: Equatable {
        case idle
        case importing(name: String, progress: Double)
        case failed(message: String)

        var isImporting: Bool {
            if case .importing = self { return true }
            return false
        }
    }

    private let fileManager = FileManager.default

    private lazy var directory: URL = {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("CompanionVideos", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private var indexURL: URL {
        directory.appendingPathComponent("index.json")
    }

    init() {
        load()
    }

    // MARK: - Access

    func url(for companion: CompanionVideo) -> URL {
        directory.appendingPathComponent(companion.storedFilename)
    }

    func thumbnailURL(for companion: CompanionVideo) -> URL {
        directory.appendingPathComponent("\(companion.id).jpg")
    }

    func companion(withId id: String) -> CompanionVideo? {
        items.first { $0.id == id }
    }

    /// Best guess pairing for a headset video, matched on base file name.
    /// Only ever a *suggestion* — the operator confirms it.
    func suggestedCompanion(forHeadsetFilename filename: String) -> CompanionVideo? {
        let base = (filename as NSString).deletingPathExtension.lowercased()
        return items.first { $0.baseName.lowercased() == base }
    }

    func clearError() {
        if case .failed = importState { importState = .idle }
    }

    // MARK: - Import

    /// Imports a file chosen in the Files app (iCloud Drive, an external drive,
    /// another provider). Document-picker URLs are security scoped.
    func importFile(from sourceURL: URL) async {
        let name = sourceURL.lastPathComponent
        importState = .importing(name: name, progress: 0)

        let didScope = sourceURL.startAccessingSecurityScopedResource()
        defer { if didScope { sourceURL.stopAccessingSecurityScopedResource() } }

        await ingest(from: sourceURL, displayName: name)
    }

    /// Imports an item picked from the Photos library.
    func importPhotosItem(_ item: PhotosPickerItem) async {
        importState = .importing(name: "Video", progress: 0)
        do {
            guard let movie = try await item.loadTransferable(type: CompanionTransferable.self) else {
                importState = .failed(message: "That item could not be read as a video.")
                return
            }
            await ingest(from: movie.url, displayName: movie.url.lastPathComponent)
            // Clean up the whole staging directory, not just the file.
            try? fileManager.removeItem(at: movie.url.deletingLastPathComponent())
        } catch {
            importState = .failed(message: "Could not import from Photos: \(error.localizedDescription)")
        }
    }

    /// Copies the file into the library, reads its duration and makes a thumbnail.
    private func ingest(from sourceURL: URL, displayName: String) async {
        let id = UUID().uuidString
        let ext = sourceURL.pathExtension.isEmpty ? "mp4" : sourceURL.pathExtension
        let storedFilename = "\(id).\(ext)"
        let destination = directory.appendingPathComponent(storedFilename)

        do {
            try await copy(from: sourceURL, to: destination) { [weak self] progress in
                Task { @MainActor in
                    self?.importState = .importing(name: displayName, progress: progress)
                }
            }

            let asset = AVURLAsset(url: destination)
            let duration = try await asset.load(.duration).seconds
            guard duration.isFinite, duration > 0 else {
                try? fileManager.removeItem(at: destination)
                importState = .failed(message: "\(displayName) has no readable video track.")
                return
            }

            let attributes = try? fileManager.attributesOfItem(atPath: destination.path)
            let size = (attributes?[.size] as? Int64) ?? 0

            let companion = CompanionVideo(
                id: id,
                storedFilename: storedFilename,
                displayName: displayName,
                duration: duration,
                fileSize: size,
                addedAt: Date()
            )

            await generateThumbnail(for: companion, asset: asset)

            items.append(companion)
            items.sort { $0.addedAt > $1.addedAt }
            save()
            importState = .idle
            print("[CompanionLibrary] ✅ Imported \(displayName) (\(companion.formattedDuration))")
        } catch {
            try? fileManager.removeItem(at: destination)
            importState = .failed(message: "Could not import \(displayName): \(error.localizedDescription)")
            print("[CompanionLibrary] ❌ Import failed: \(error)")
        }
    }

    /// Streams the file across in chunks so a multi-hundred-megabyte import
    /// neither loads into memory nor blocks the main actor, and can report real
    /// progress rather than a fake spinner.
    private nonisolated func copy(
        from source: URL,
        to destination: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            try? fm.removeItem(at: destination)

            let total = (try fm.attributesOfItem(atPath: source.path)[.size] as? Int64) ?? 0
            guard total > 0 else { throw CocoaError(.fileReadUnknown) }

            guard fm.createFile(atPath: destination.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }

            let input = try FileHandle(forReadingFrom: source)
            let output = try FileHandle(forWritingTo: destination)
            defer { try? input.close(); try? output.close() }

            let chunkSize = 4 * 1024 * 1024
            var written: Int64 = 0
            var lastReported = 0.0

            while true {
                guard let chunk = try input.read(upToCount: chunkSize), !chunk.isEmpty else { break }
                try output.write(contentsOf: chunk)
                written += Int64(chunk.count)

                let progress = min(1.0, Double(written) / Double(total))
                // Report at most every 2% so the UI is not flooded.
                if progress - lastReported >= 0.02 || progress >= 1.0 {
                    lastReported = progress
                    onProgress(progress)
                }
            }
        }.value
    }

    private func generateThumbnail(for companion: CompanionVideo, asset: AVURLAsset) async {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)

        // A frame a little into the video — the first frame is often black.
        let target = CMTime(seconds: min(1.0, companion.duration / 4), preferredTimescale: 600)
        do {
            let (image, _) = try await generator.image(at: target)
            let uiImage = UIImage(cgImage: image)
            if let data = uiImage.jpegData(compressionQuality: 0.8) {
                try? data.write(to: thumbnailURL(for: companion))
            }
        } catch {
            print("[CompanionLibrary] Thumbnail failed for \(companion.displayName): \(error)")
        }
    }

    // MARK: - Delete

    func delete(_ companion: CompanionVideo) {
        try? fileManager.removeItem(at: url(for: companion))
        try? fileManager.removeItem(at: thumbnailURL(for: companion))
        items.removeAll { $0.id == companion.id }
        save()
        print("[CompanionLibrary] Deleted \(companion.displayName)")
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([CompanionVideo].self, from: data) else {
            items = []
            return
        }
        // Drop entries whose file vanished (e.g. restored backup without data).
        items = decoded.filter { fileManager.fileExists(atPath: url(for: $0).path) }
        if items.count != decoded.count { save() }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}

// MARK: - Photos transfer

/// Receives a Photos pick into a temporary file we then ingest.
struct CompanionTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            // Unique *directory*, original *filename* — the name is what the
            // operator sees and what name-based pairing suggestions match on, so
            // it must survive the round trip intact.
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("companion-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let temp = directory.appendingPathComponent(received.file.lastPathComponent)
            try FileManager.default.copyItem(at: received.file, to: temp)
            return CompanionTransferable(url: temp)
        }
    }
}
