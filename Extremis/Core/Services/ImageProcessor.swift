// MARK: - Image Processor
// Handles image resizing, compression, thumbnail generation, and format conversion

import Foundation
import ImageIO
import UniformTypeIdentifiers

#if canImport(AppKit)
import AppKit
#endif

// MARK: - Image Processor

@MainActor
final class ImageProcessor {
    static let shared = ImageProcessor()

    // MARK: - Configuration Constants

    /// Maximum pixels on the longest edge after resize
    let maxImageLongEdge: Int = 1568

    /// Maximum bytes per image after processing (4MB)
    let maxImageFileSize: Int = 4_194_304

    /// Maximum bytes for input image before processing (10MB)
    let maxInputImageSize: Int = 10_485_760

    /// Maximum images per single message
    let maxImagesPerMessage: Int = 5

    /// Maximum pixels on longest edge for thumbnails
    let thumbnailMaxSize: Int = 200

    /// JPEG compression quality for full images
    let jpegQuality: CGFloat = 0.85

    /// JPEG compression quality for thumbnails
    let thumbnailJpegQuality: CGFloat = 0.6

    // MARK: - Supported Types

    /// UTTypes accepted for image input
    /// Includes .tiff since macOS pasteboard commonly provides copied images as TIFF
    static let supportedUTTypes: [UTType] = [
        .png, .jpeg, .gif, .webP, .heic, .tiff
    ]

    // MARK: - Public API

    /// Process raw image data into an ImageAttachment
    /// Validates, resizes, compresses, and generates thumbnail
    func process(data: Data, sourceType: ImageSourceType, originalFilename: String? = nil) throws -> ImageAttachment {
        // 1. Validate input size
        guard data.count <= maxInputImageSize else {
            throw ImageProcessingError.inputTooLarge(data.count)
        }

        // 2. Create image source
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ImageProcessingError.unsupportedFormat
        }

        // 3. Validate format
        guard let utType = CGImageSourceGetType(imageSource) as? String else {
            throw ImageProcessingError.unsupportedFormat
        }

        let isSupported = Self.supportedUTTypes.contains { type in
            UTType(utType)?.conforms(to: type) ?? false
        }
        guard isSupported else {
            throw ImageProcessingError.unsupportedFormat
        }

        // 4. Get original dimensions
        guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int,
              let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw ImageProcessingError.processingFailed("Cannot read image dimensions")
        }

        // 5. Determine if image has alpha (use PNG) or not (use JPEG)
        let hasAlpha = Self.imageHasAlpha(properties: properties, utType: utType)
        let outputFormat: ImageFormat = hasAlpha ? .png : .jpeg

        // 6. Resize if needed
        let needsResize = max(pixelWidth, pixelHeight) > maxImageLongEdge
        let (processedData, finalWidth, finalHeight) = try resizeAndCompress(
            imageSource: imageSource,
            originalWidth: pixelWidth,
            originalHeight: pixelHeight,
            maxEdge: maxImageLongEdge,
            format: outputFormat,
            quality: jpegQuality,
            needsResize: needsResize
        )

        // 7. Validate output size
        guard processedData.count <= maxImageFileSize else {
            throw ImageProcessingError.outputTooLarge(processedData.count)
        }

        // 8. Generate thumbnail
        let thumbnailData = generateThumbnail(
            imageSource: imageSource,
            maxSize: thumbnailMaxSize,
            quality: thumbnailJpegQuality
        ) ?? Data()

        return ImageAttachment(
            imageData: processedData,
            thumbnailData: thumbnailData,
            originalFilename: originalFilename,
            width: finalWidth,
            height: finalHeight,
            fileSize: processedData.count,
            format: outputFormat,
            mimeType: outputFormat.mimeType,
            sourceType: sourceType
        )
    }

    // MARK: - Private Helpers

    /// Resize and compress image using ImageIO (memory-efficient)
    private func resizeAndCompress(
        imageSource: CGImageSource,
        originalWidth: Int,
        originalHeight: Int,
        maxEdge: Int,
        format: ImageFormat,
        quality: CGFloat,
        needsResize: Bool
    ) throws -> (Data, Int, Int) {
        let finalWidth: Int
        let finalHeight: Int

        let cgImage: CGImage

        if needsResize {
            // Use CGImageSourceCreateThumbnailAtIndex for memory-efficient resize
            let scale = Double(maxEdge) / Double(max(originalWidth, originalHeight))
            finalWidth = Int(round(Double(originalWidth) * scale))
            finalHeight = Int(round(Double(originalHeight) * scale))

            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxEdge,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]

            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
                throw ImageProcessingError.processingFailed("Failed to resize image")
            }
            cgImage = thumbnail
        } else {
            finalWidth = originalWidth
            finalHeight = originalHeight

            guard let original = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw ImageProcessingError.processingFailed("Failed to decode image")
            }
            cgImage = original
        }

        // Compress to output format
        let outputData = try compressImage(cgImage, format: format, quality: quality)

        return (outputData, finalWidth, finalHeight)
    }

    /// Generate a small thumbnail for preview
    private func generateThumbnail(imageSource: CGImageSource, maxSize: Int, quality: CGFloat) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSize,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            return nil
        }

        return try? compressImage(thumbnail, format: .jpeg, quality: quality)
    }

    /// Compress a CGImage to JPEG or PNG data
    private func compressImage(_ image: CGImage, format: ImageFormat, quality: CGFloat) throws -> Data {
        let data = NSMutableData()

        let utType: CFString
        switch format {
        case .jpeg:
            utType = UTType.jpeg.identifier as CFString
        case .png:
            utType = UTType.png.identifier as CFString
        }

        guard let destination = CGImageDestinationCreateWithData(data, utType, 1, nil) else {
            throw ImageProcessingError.processingFailed("Failed to create image destination")
        }

        var options: [CFString: Any] = [:]
        if format == .jpeg {
            options[kCGImageDestinationLossyCompressionQuality] = quality
        }

        CGImageDestinationAddImage(destination, image, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw ImageProcessingError.processingFailed("Failed to finalize image compression")
        }

        return data as Data
    }

    /// Check if image has alpha channel
    private static func imageHasAlpha(properties: [CFString: Any], utType: String) -> Bool {
        // Check the explicit alpha property first (works for any format)
        if let hasAlpha = properties[kCGImagePropertyHasAlpha] as? Bool {
            return hasAlpha
        }
        // If property missing, assume alpha for PNG only (conservative default)
        if UTType(utType)?.conforms(to: .png) == true {
            return true
        }
        return false
    }
}
