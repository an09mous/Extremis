// MARK: - Image Processor
// Processes images for LLM API consumption: resize, compress, format selection, base64 encoding

import AppKit
import Foundation

/// Stateless image processing utility for preparing images for LLM APIs
struct ImageProcessor {

    /// Maximum edge length for images sent to LLM APIs
    /// All major providers handle 1568px well (Anthropic recommends this)
    static let maxEdgeLength: CGFloat = 1568

    /// JPEG compression quality (0.8 is a good balance of quality vs size)
    static let jpegQuality: CGFloat = 0.8

    /// Maximum raw image data size in bytes before base64 (approx 15MB to stay under 20MB base64 limit)
    static let maxDataBytes: Int = 15 * 1024 * 1024

    // MARK: - Public Methods

    /// Process an NSImage for LLM consumption
    /// - Resizes if larger than maxEdgeLength (preserving aspect ratio)
    /// - Selects format: PNG if has transparency, JPEG otherwise
    /// - Compresses to target quality
    /// - Returns nil if processing fails
    static func process(_ image: NSImage) -> ImageAttachment? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let originalWidth = CGFloat(cgImage.width)
        let originalHeight = CGFloat(cgImage.height)

        // Calculate target size (may be unchanged if already small enough)
        let (targetWidth, targetHeight) = calculateTargetSize(
            width: originalWidth, height: originalHeight,
            maxEdge: maxEdgeLength
        )

        // Resize if needed
        let processedImage: NSImage
        if targetWidth != originalWidth || targetHeight != originalHeight {
            guard let resized = resizeImage(image, to: NSSize(width: targetWidth, height: targetHeight)) else {
                return nil
            }
            processedImage = resized
        } else {
            processedImage = image
        }

        // Detect alpha channel
        let hasAlpha = imageHasAlpha(cgImage)

        // Encode to appropriate format
        let (data, mediaType) = encodeImage(processedImage, hasAlpha: hasAlpha)
        guard let imageData = data else { return nil }

        // Check size limit
        guard imageData.count <= maxDataBytes else { return nil }

        let base64 = imageData.base64EncodedString()

        return ImageAttachment(
            mediaType: mediaType,
            base64Data: base64,
            width: Int(targetWidth),
            height: Int(targetHeight),
            fileSizeBytes: imageData.count
        )
    }

    /// Process image from a file URL (preserves source filename)
    static func processFromURL(_ url: URL) -> ImageAttachment? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        guard let attachment = process(image) else { return nil }

        // Reconstruct with filename
        let fileName = url.lastPathComponent
        return ImageAttachment(
            id: attachment.id,
            mediaType: attachment.mediaType,
            base64Data: attachment.base64Data,
            width: attachment.width,
            height: attachment.height,
            fileSizeBytes: attachment.fileSizeBytes,
            sourceFileName: fileName
        )
    }

    /// Process all images from the pasteboard
    /// Returns empty array if no images found
    static func processFromPasteboard() -> [ImageAttachment] {
        let pasteboard = NSPasteboard.general

        // Try reading NSImage objects from pasteboard (handles TIFF, PNG, JPEG, etc.)
        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage] {
            return images.compactMap { process($0) }
        }

        // Try reading image data directly for specific types
        for type in [NSPasteboard.PasteboardType.png, NSPasteboard.PasteboardType.tiff] {
            if let data = pasteboard.data(forType: type),
               let image = NSImage(data: data) {
                if let attachment = process(image) {
                    return [attachment]
                }
            }
        }

        return []
    }

    /// Check if the pasteboard currently contains image data
    static func pasteboardHasImage() -> Bool {
        let pasteboard = NSPasteboard.general
        let imageTypes: [NSPasteboard.PasteboardType] = [.tiff, .png]
        return pasteboard.availableType(from: imageTypes) != nil
    }

    // MARK: - Internal Helpers (visible for testing)

    /// Calculate target dimensions preserving aspect ratio
    static func calculateTargetSize(width: CGFloat, height: CGFloat, maxEdge: CGFloat) -> (CGFloat, CGFloat) {
        let maxDimension = max(width, height)
        guard maxDimension > maxEdge else { return (width, height) }
        let scale = maxEdge / maxDimension
        return (round(width * scale), round(height * scale))
    }

    /// Resize an NSImage to the target size
    static func resizeImage(_ image: NSImage, to size: NSSize) -> NSImage? {
        let newImage = NSImage(size: size)
        newImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: size),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1.0
        )
        newImage.unlockFocus()
        return newImage
    }

    /// Encode an NSImage to PNG or JPEG data based on alpha presence
    static func encodeImage(_ image: NSImage, hasAlpha: Bool) -> (Data?, ImageMediaType) {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return (nil, .jpeg)
        }

        if hasAlpha {
            return (bitmap.representation(using: .png, properties: [:]), .png)
        } else {
            return (
                bitmap.representation(using: .jpeg, properties: [.compressionFactor: jpegQuality]),
                .jpeg
            )
        }
    }

    /// Check if a CGImage has an alpha channel
    private static func imageHasAlpha(_ cgImage: CGImage) -> Bool {
        let alphaInfo = cgImage.alphaInfo
        switch alphaInfo {
        case .none, .noneSkipLast, .noneSkipFirst:
            return false
        default:
            return true
        }
    }
}
