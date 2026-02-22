// MARK: - Image Storage Manager
// File-based storage for image attachments, separate from session JSON

import Foundation

/// Manages file-based storage for image attachments
/// Images are stored as individual files in ~/Library/Application Support/Extremis/images/
/// Session JSON stores lightweight refs (PersistedAttachmentRef) pointing to these files
actor ImageStorageManager {

    static let shared = ImageStorageManager()

    /// Directory for storing image files
    private let imagesDirectory: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        imagesDirectory = appSupport.appendingPathComponent("Extremis/images", isDirectory: true)
    }

    // MARK: - Public Methods

    /// Save an image attachment to disk
    /// - Returns: The attachment's ID (same as input) for reference
    func saveImage(_ attachment: ImageAttachment) throws -> UUID {
        try ensureDirectoryExists()

        guard let data = Data(base64Encoded: attachment.base64Data) else {
            throw ImageStorageError.invalidBase64Data
        }

        let fileURL = fileURL(for: attachment.id, mediaType: attachment.mediaType)
        try data.write(to: fileURL, options: .atomic)

        return attachment.id
    }

    /// Save all image attachments from a message
    func saveAttachments(_ attachments: [MessageAttachment]) throws {
        for attachment in attachments {
            if case .image(let img) = attachment {
                _ = try saveImage(img)
            }
        }
    }

    /// Load an image attachment from disk by ID and metadata
    /// Reconstructs the full ImageAttachment with base64Data loaded from file
    func loadImage(ref: PersistedAttachmentRef) -> ImageAttachment? {
        guard let mediaType = ImageMediaType(rawValue: ref.mediaType) else { return nil }
        let fileURL = fileURL(for: ref.id, mediaType: mediaType)

        guard let data = try? Data(contentsOf: fileURL) else { return nil }

        let base64 = data.base64EncodedString()

        return ImageAttachment(
            id: ref.id,
            mediaType: mediaType,
            base64Data: base64,
            width: ref.width,
            height: ref.height,
            fileSizeBytes: ref.fileSizeBytes,
            sourceFileName: ref.sourceFileName
        )
    }

    /// Load all attachments from persisted refs
    func loadAttachments(refs: [PersistedAttachmentRef]) -> [MessageAttachment] {
        return refs.compactMap { ref in
            guard ref.type == "image" else { return nil }
            guard let img = loadImage(ref: ref) else { return nil }
            return .image(img)
        }
    }

    /// Delete an image file from disk
    func deleteImage(id: UUID) {
        // Try all known extensions since we don't know the format
        for ext in ["jpeg", "png", "gif", "webp"] {
            let url = imagesDirectory.appendingPathComponent("\(id.uuidString).\(ext)")
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Delete multiple image files
    func deleteImages(ids: [UUID]) {
        for id in ids {
            deleteImage(id: id)
        }
    }

    /// Check if an image file exists on disk
    func imageExists(id: UUID, mediaType: ImageMediaType) -> Bool {
        let url = fileURL(for: id, mediaType: mediaType)
        return FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - Private Helpers

    private func ensureDirectoryExists() throws {
        if !FileManager.default.fileExists(atPath: imagesDirectory.path) {
            try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        }
    }

    private func fileURL(for id: UUID, mediaType: ImageMediaType) -> URL {
        imagesDirectory.appendingPathComponent("\(id.uuidString).\(mediaType.fileExtension)")
    }
}

// MARK: - Errors

enum ImageStorageError: Error, LocalizedError {
    case invalidBase64Data
    case fileWriteFailed(URL)

    var errorDescription: String? {
        switch self {
        case .invalidBase64Data: return "Invalid base64 image data"
        case .fileWriteFailed(let url): return "Failed to write image to \(url.path)"
        }
    }
}
