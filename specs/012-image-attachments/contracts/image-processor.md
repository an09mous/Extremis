# Contract: ImageProcessor

**Module**: `Core/Services/ImageProcessor.swift`
**Type**: `@MainActor final class` (singleton via `.shared`)

## Public Interface

```swift
@MainActor
final class ImageProcessor {
    static let shared = ImageProcessor()

    // MARK: - Configuration Constants
    static let maxImageLongEdge: Int = 1568
    static let maxImageFileSize: Int = 4_194_304      // 4MB
    static let maxInputImageSize: Int = 10_485_760     // 10MB
    static let maxImagesPerMessage: Int = 5
    static let thumbnailMaxSize: Int = 200
    static let jpegQuality: CGFloat = 0.85
    static let thumbnailJpegQuality: CGFloat = 0.6

    // MARK: - Supported Formats
    static let supportedUTTypes: [UTType] = [.png, .jpeg, .gif, .webP, .heic]

    // MARK: - Processing

    /// Process raw image data into a send-ready ImageAttachment.
    /// Resizes, compresses, converts format, and generates thumbnail.
    /// - Parameters:
    ///   - data: Raw input image data (any supported format)
    ///   - sourceType: How the image was attached (clipboard/filePicker/dragAndDrop)
    ///   - originalFilename: Original filename if available
    /// - Returns: Processed ImageAttachment ready for display and sending
    /// - Throws: ImageProcessingError
    func process(
        data: Data,
        sourceType: ImageSourceType,
        originalFilename: String?
    ) throws -> ImageAttachment

    /// Validate that input data is a supported image format and within size limits.
    /// - Returns: true if valid
    func validate(data: Data) -> Result<Void, ImageProcessingError>

    /// Generate a thumbnail from existing image data.
    /// - Parameters:
    ///   - data: Processed image data (JPEG/PNG)
    ///   - maxSize: Maximum pixel dimension on longest edge
    /// - Returns: Thumbnail data as JPEG
    func generateThumbnail(from data: Data, maxSize: Int) -> Data?

    /// Convert image data to base64 string for LLM API transmission.
    func base64Encode(_ data: Data) -> String
}
```

## Error Type

```swift
enum ImageProcessingError: LocalizedError {
    case unsupportedFormat(String)      // "TIFF files are not supported"
    case inputTooLarge(Int)             // Exceeds maxInputImageSize
    case processingFailed(String)       // ImageIO operation failed
    case outputTooLarge(Int)            // After compression, still exceeds maxImageFileSize

    var errorDescription: String? { ... }
}
```

## Behavior Contract

1. **Input validation**: Reject data >10MB or unsupported formats before processing.
2. **Format detection**: Use `CGImageSourceGetType()` to determine input format from data (not filename extension).
3. **Resizing**: Only resize if either dimension exceeds `maxImageLongEdge`. Maintain aspect ratio. Use `CGImageSourceCreateThumbnailAtIndex` for memory efficiency.
4. **Format conversion**: HEIC, GIF, WebP → JPEG. PNG with alpha → PNG. PNG without alpha → JPEG.
5. **Compression**: Apply `jpegQuality` for JPEG output. If result exceeds `maxImageFileSize`, retry at 0.7 quality.
6. **Thumbnail**: Always generate 200px thumbnail at 0.6 JPEG quality regardless of output format.
7. **Thread safety**: All operations are synchronous and pure — no shared mutable state.
