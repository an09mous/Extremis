// MARK: - Image Persistence
// File-based image storage for chat session images

import Foundation

/// Manages saving and loading images to/from disk
/// Images stored in ~/Library/Application Support/Extremis/images/
actor ImagePersistence {
    static let shared = ImagePersistence()

    // MARK: - Paths

    private var imagesDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Extremis", isDirectory: true)
            .appendingPathComponent("images", isDirectory: true)
    }

    private var directoryEnsured = false

    // MARK: - Directory Setup

    /// Ensure images directory exists (called lazily on first access)
    private func ensureDirectory() throws {
        guard !directoryEnsured else { return }
        try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        directoryEnsured = true
    }

    // MARK: - Save

    /// Save a single image attachment to disk, returning an ImageRef
    /// Skips writing if the file already exists (idempotent for re-saves)
    func save(_ attachment: ImageAttachment) throws -> ImageRef {
        try ensureDirectory()

        let ref = ImageRef(from: attachment)
        let fileURL = imagesDirectory.appendingPathComponent(ref.filename)

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try attachment.imageData.write(to: fileURL, options: .atomic)
        }

        return ref
    }

    /// Save multiple image attachments to disk
    func save(_ attachments: [ImageAttachment]) throws -> [ImageRef] {
        try attachments.map { try save($0) }
    }

    // MARK: - Load

    /// Load full image data for an ImageRef
    func loadImageData(for ref: ImageRef) throws -> Data {
        try ensureDirectory()

        let fileURL = imagesDirectory.appendingPathComponent(ref.filename)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ImagePersistenceError.imageNotFound(ref.filename)
        }

        return try Data(contentsOf: fileURL)
    }

    /// Restore a full ImageAttachment from an ImageRef
    func restore(from ref: ImageRef) throws -> ImageAttachment {
        let imageData = try loadImageData(for: ref)
        let thumbnailData = ref.thumbnailData ?? Data()
        let format = ref.imageFormat ?? .jpeg

        return ImageAttachment(
            id: ref.id,
            imageData: imageData,
            thumbnailData: thumbnailData,
            originalFilename: ref.originalFilename,
            width: ref.width,
            height: ref.height,
            fileSize: imageData.count,
            format: format,
            mimeType: format.mimeType,
            sourceType: .clipboard // Source type not preserved in ref; default to clipboard
        )
    }

    /// Restore multiple ImageAttachments from ImageRefs
    /// Returns successfully restored attachments; logs failures for individual refs
    func restore(from refs: [ImageRef]) -> [ImageAttachment] {
        var attachments: [ImageAttachment] = []
        for ref in refs {
            do {
                let attachment = try restore(from: ref)
                attachments.append(attachment)
            } catch {
                print("[ImagePersistence] Warning: Failed to restore image \(ref.filename): \(error)")
            }
        }
        return attachments
    }

    // MARK: - Delete

    /// Delete image file for an ImageRef
    func delete(ref: ImageRef) throws {
        let fileURL = imagesDirectory.appendingPathComponent(ref.filename)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    // MARK: - Cleanup

    /// Remove orphaned image files that are not referenced by any active session
    /// Returns the count of files removed
    func cleanupOrphaned(activeRefs: Set<String>) throws -> Int {
        try ensureDirectory()

        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: imagesDirectory.path) else {
            return 0
        }

        var removedCount = 0
        for filename in files {
            if !activeRefs.contains(filename) {
                let fileURL = imagesDirectory.appendingPathComponent(filename)
                try? fm.removeItem(at: fileURL)
                removedCount += 1
            }
        }

        return removedCount
    }
}

// MARK: - Errors

enum ImagePersistenceError: Error, LocalizedError {
    case imageNotFound(String)

    var errorDescription: String? {
        switch self {
        case .imageNotFound(let filename):
            return "Image file not found: \(filename)"
        }
    }
}
