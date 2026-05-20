// MARK: - Image Attachment Models
// Models for image attachments in chat messages

import Foundation

// MARK: - Image Format

/// Output format for processed images
enum ImageFormat: String, Codable, Equatable, Hashable {
    case jpeg
    case png

    var mimeType: String {
        switch self {
        case .jpeg: return "image/jpeg"
        case .png: return "image/png"
        }
    }

    var fileExtension: String {
        rawValue
    }
}

// MARK: - Image Source Type

/// How the image was attached to the message
enum ImageSourceType: String, Codable, Equatable, Hashable {
    case clipboard
    case filePicker = "file_picker"
    case dragAndDrop = "drag_and_drop"
}

// MARK: - Image Processing Error

/// Errors that can occur during image processing
enum ImageProcessingError: Error, Equatable, LocalizedError {
    case unsupportedFormat
    case inputTooLarge(Int)
    case processingFailed(String)
    case outputTooLarge(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "Unsupported image format. Supported formats: PNG, JPEG, GIF, WebP, HEIC."
        case .inputTooLarge(let size):
            let mb = Double(size) / 1_048_576
            return String(format: "Image too large (%.1f MB). Maximum input size is 10 MB.", mb)
        case .processingFailed(let reason):
            return "Image processing failed: \(reason)"
        case .outputTooLarge(let size):
            let mb = Double(size) / 1_048_576
            return String(format: "Processed image too large (%.1f MB). Maximum is 4 MB.", mb)
        }
    }
}

// MARK: - Image Attachment

/// Represents a single image attached to a chat message
struct ImageAttachment: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let imageData: Data
    let thumbnailData: Data
    let originalFilename: String?
    let width: Int
    let height: Int
    let fileSize: Int
    let format: ImageFormat
    let mimeType: String
    let sourceType: ImageSourceType
    let createdAt: Date

    init(
        id: UUID = UUID(),
        imageData: Data,
        thumbnailData: Data,
        originalFilename: String? = nil,
        width: Int,
        height: Int,
        fileSize: Int,
        format: ImageFormat,
        mimeType: String,
        sourceType: ImageSourceType,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.imageData = imageData
        self.thumbnailData = thumbnailData
        self.originalFilename = originalFilename
        self.width = width
        self.height = height
        self.fileSize = fileSize
        self.format = format
        self.mimeType = mimeType
        self.sourceType = sourceType
        self.createdAt = createdAt
    }

    /// Base64-encoded image data for LLM API payloads
    var base64EncodedData: String {
        imageData.base64EncodedString()
    }
}

// MARK: - Image Ref (Persistence Reference)

/// Lightweight reference stored in PersistedMessage to reference images on disk
/// Contains inline thumbnail for fast preview without file I/O
struct ImageRef: Codable, Equatable, Hashable {
    let id: UUID
    let filename: String
    let thumbnailBase64: String
    let originalFilename: String?
    let width: Int
    let height: Int
    let format: String

    /// Create from an ImageAttachment (for saving)
    init(from attachment: ImageAttachment) {
        self.id = attachment.id
        self.filename = "\(attachment.id.uuidString).\(attachment.format.fileExtension)"
        self.thumbnailBase64 = attachment.thumbnailData.base64EncodedString()
        self.originalFilename = attachment.originalFilename
        self.width = attachment.width
        self.height = attachment.height
        self.format = attachment.format.rawValue
    }

    /// Direct initializer (for loading/testing)
    init(id: UUID, filename: String, thumbnailBase64: String, originalFilename: String?, width: Int, height: Int, format: String) {
        self.id = id
        self.filename = filename
        self.thumbnailBase64 = thumbnailBase64
        self.originalFilename = originalFilename
        self.width = width
        self.height = height
        self.format = format
    }

    /// Decode thumbnail data from base64
    var thumbnailData: Data? {
        Data(base64Encoded: thumbnailBase64)
    }

    /// Parsed image format
    var imageFormat: ImageFormat? {
        ImageFormat(rawValue: format)
    }
}
