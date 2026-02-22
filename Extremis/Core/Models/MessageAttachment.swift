// MARK: - Message Attachment Models
// Extensible attachment types for multimodal messages (images now, files/audio/video later)

import Foundation

// MARK: - Image Media Type

/// Supported image MIME types for LLM API payloads
enum ImageMediaType: String, Codable, Equatable, Hashable {
    case jpeg = "image/jpeg"
    case png = "image/png"
    case gif = "image/gif"
    case webp = "image/webp"

    /// File extension for disk storage
    var fileExtension: String {
        switch self {
        case .jpeg: return "jpeg"
        case .png: return "png"
        case .gif: return "gif"
        case .webp: return "webp"
        }
    }

    /// Initialize from file extension
    init?(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "jpeg", "jpg": self = .jpeg
        case "png": self = .png
        case "gif": self = .gif
        case "webp": self = .webp
        default: return nil
        }
    }
}

// MARK: - Message Attachment

/// Extensible attachment enum — image support now, file/audio/video later
enum MessageAttachment: Codable, Equatable, Identifiable {
    case image(ImageAttachment)
    // Future: case file(FileAttachment), case audio(AudioAttachment)

    var id: UUID {
        switch self {
        case .image(let img): return img.id
        }
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case type
        case payload
    }

    private enum AttachmentType: String, Codable {
        case image
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .image(let attachment):
            try container.encode(AttachmentType.image, forKey: .type)
            try container.encode(attachment, forKey: .payload)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(AttachmentType.self, forKey: .type)
        switch type {
        case .image:
            let attachment = try container.decode(ImageAttachment.self, forKey: .payload)
            self = .image(attachment)
        }
    }
}

// MARK: - Image Attachment

/// Image attachment data for multimodal messages
struct ImageAttachment: Codable, Equatable, Identifiable, Hashable {
    let id: UUID
    let mediaType: ImageMediaType
    /// Base64-encoded image data — held in memory for API calls, stored separately on disk
    let base64Data: String
    let width: Int?
    let height: Int?
    let fileSizeBytes: Int?
    let sourceFileName: String?

    init(
        id: UUID = UUID(),
        mediaType: ImageMediaType,
        base64Data: String,
        width: Int? = nil,
        height: Int? = nil,
        fileSizeBytes: Int? = nil,
        sourceFileName: String? = nil
    ) {
        self.id = id
        self.mediaType = mediaType
        self.base64Data = base64Data
        self.width = width
        self.height = height
        self.fileSizeBytes = fileSizeBytes
        self.sourceFileName = sourceFileName
    }

    /// Human-readable file size (e.g. "245 KB")
    var formattedFileSize: String? {
        guard let bytes = fileSizeBytes else { return nil }
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return "\(bytes / 1024) KB"
        } else {
            let mb = Double(bytes) / (1024.0 * 1024.0)
            return String(format: "%.1f MB", mb)
        }
    }
}

// MARK: - Persisted Attachment Reference

/// Lightweight reference for persistence — stores metadata but NOT image data
/// Image data is stored as separate files on disk via ImageStorageManager
struct PersistedAttachmentRef: Codable, Equatable {
    let id: UUID
    let type: String              // "image"
    let mediaType: String         // "image/jpeg"
    let width: Int?
    let height: Int?
    let fileSizeBytes: Int?
    let sourceFileName: String?

    /// Create from an ImageAttachment
    init(from attachment: ImageAttachment) {
        self.id = attachment.id
        self.type = "image"
        self.mediaType = attachment.mediaType.rawValue
        self.width = attachment.width
        self.height = attachment.height
        self.fileSizeBytes = attachment.fileSizeBytes
        self.sourceFileName = attachment.sourceFileName
    }

    /// Create from a MessageAttachment
    static func fromAttachment(_ attachment: MessageAttachment) -> PersistedAttachmentRef {
        switch attachment {
        case .image(let img):
            return PersistedAttachmentRef(from: img)
        }
    }
}
