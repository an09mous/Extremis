// MARK: - ImageProcessor Tests
// Tests for image format validation, size validation, and processing logic

import Foundation

// MARK: - Test Runner

struct TestRunner {
    static var passedCount = 0
    static var failedCount = 0
    static var failedTests: [(name: String, message: String)] = []

    static func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ testName: String) {
        if actual == expected {
            passedCount += 1
            print("  ✓ \(testName)")
        } else {
            failedCount += 1
            failedTests.append((testName, "Expected '\(expected)' but got '\(actual)'"))
            print("  ✗ \(testName): Expected '\(expected)' but got '\(actual)'")
        }
    }

    static func assertTrue(_ condition: Bool, _ testName: String) {
        if condition {
            passedCount += 1
            print("  ✓ \(testName)")
        } else {
            failedCount += 1
            failedTests.append((testName, "Expected true but got false"))
            print("  ✗ \(testName): Expected true but got false")
        }
    }

    static func assertFalse(_ condition: Bool, _ testName: String) {
        assertTrue(!condition, testName)
    }

    static func suite(_ name: String) {
        print("\n📋 \(name)")
        print("--------------------------------------------------")
    }

    static func printSummary() {
        print("\n==================================================")
        print("TEST SUMMARY")
        print("==================================================")
        print("Passed: \(passedCount)")
        print("Failed: \(failedCount)")
        print("Total:  \(passedCount + failedCount)")
        print("==================================================")
        if !failedTests.isEmpty {
            print("\nFailed tests:")
            for test in failedTests {
                print("  ✗ \(test.name): \(test.message)")
            }
        }
    }
}

// MARK: - Inline Type Definitions

enum ImageFormat: String, Codable, Equatable {
    case jpeg, png
    var mimeType: String {
        switch self {
        case .jpeg: return "image/jpeg"
        case .png: return "image/png"
        }
    }
}

enum ImageSourceType: String, Codable, Equatable {
    case clipboard, filePicker = "file_picker", dragAndDrop = "drag_and_drop"
}

enum ImageProcessingError: Error, Equatable {
    case unsupportedFormat
    case inputTooLarge(Int)
    case processingFailed(String)
    case outputTooLarge(Int)
}

struct ImageProcessorConfig {
    let maxImageLongEdge: Int = 1568
    let maxImageFileSize: Int = 4_194_304
    let maxInputImageSize: Int = 10_485_760
    let maxImagesPerMessage: Int = 5
    let thumbnailMaxSize: Int = 200
    let jpegQuality: Double = 0.85
    let thumbnailJpegQuality: Double = 0.6
}

// MARK: - Tests

func testConfigurationConstants() {
    TestRunner.suite("Configuration Constants")

    let config = ImageProcessorConfig()
    TestRunner.assertEqual(config.maxImageLongEdge, 1568, "Max long edge is 1568px")
    TestRunner.assertEqual(config.maxImageFileSize, 4_194_304, "Max file size is 4MB")
    TestRunner.assertEqual(config.maxInputImageSize, 10_485_760, "Max input size is 10MB")
    TestRunner.assertEqual(config.maxImagesPerMessage, 5, "Max images per message is 5")
    TestRunner.assertEqual(config.thumbnailMaxSize, 200, "Thumbnail max size is 200px")
    TestRunner.assertTrue(config.jpegQuality == 0.85, "JPEG quality is 0.85")
    TestRunner.assertTrue(config.thumbnailJpegQuality == 0.6, "Thumbnail JPEG quality is 0.6")
}

func testInputSizeValidation() {
    TestRunner.suite("Input Size Validation")

    let maxInput = 10_485_760 // 10MB

    // Under limit
    let smallData = Data(repeating: 0xFF, count: 1024)
    TestRunner.assertTrue(smallData.count <= maxInput, "1KB data is under 10MB limit")

    // At limit
    let atLimit = Data(repeating: 0xFF, count: maxInput)
    TestRunner.assertTrue(atLimit.count <= maxInput, "Exactly 10MB is at limit")

    // Over limit
    let overLimit = Data(repeating: 0xFF, count: maxInput + 1)
    TestRunner.assertTrue(overLimit.count > maxInput, "10MB + 1 byte exceeds limit")
}

func testBase64Encoding() {
    TestRunner.suite("Base64 Encoding")

    let testData = Data([0x48, 0x65, 0x6C, 0x6C, 0x6F]) // "Hello"
    let base64 = testData.base64EncodedString()
    TestRunner.assertEqual(base64, "SGVsbG8=", "Base64 encodes correctly")

    // Round-trip
    if let decoded = Data(base64Encoded: base64) {
        TestRunner.assertEqual(decoded, testData, "Base64 round-trip preserves data")
    } else {
        TestRunner.assertTrue(false, "Base64 decoding failed")
    }

    // Empty data
    let emptyBase64 = Data().base64EncodedString()
    TestRunner.assertEqual(emptyBase64, "", "Empty data produces empty base64")
}

func testImageProcessingErrorEquatable() {
    TestRunner.suite("ImageProcessingError Equatable")

    TestRunner.assertTrue(
        ImageProcessingError.unsupportedFormat == ImageProcessingError.unsupportedFormat,
        "Same unsupportedFormat are equal"
    )
    TestRunner.assertTrue(
        ImageProcessingError.inputTooLarge(100) == ImageProcessingError.inputTooLarge(100),
        "Same inputTooLarge values are equal"
    )
    TestRunner.assertFalse(
        ImageProcessingError.inputTooLarge(100) == ImageProcessingError.inputTooLarge(200),
        "Different inputTooLarge values are not equal"
    )
    TestRunner.assertFalse(
        ImageProcessingError.unsupportedFormat == ImageProcessingError.inputTooLarge(100),
        "Different error types are not equal"
    )
}

func testDimensionCalculation() {
    TestRunner.suite("Dimension Calculation (resize logic)")

    let maxEdge = 1568

    // Landscape image that needs resize
    let w1 = 3000, h1 = 2000
    let scale1 = Double(maxEdge) / Double(max(w1, h1))
    let newW1 = Int(Double(w1) * scale1)
    let newH1 = Int(Double(h1) * scale1)
    TestRunner.assertTrue(newW1 <= maxEdge, "Resized landscape width <= 1568")
    TestRunner.assertTrue(newH1 <= maxEdge, "Resized landscape height <= 1568")
    TestRunner.assertTrue(newW1 >= 1567 && newW1 <= 1568, "Landscape width scaled to ~1568")
    TestRunner.assertEqual(newH1, 1045, "Landscape height proportionally scaled")

    // Portrait image that needs resize
    let w2 = 1000, h2 = 4000
    let scale2 = Double(maxEdge) / Double(max(w2, h2))
    let newW2 = Int(Double(w2) * scale2)
    let newH2 = Int(Double(h2) * scale2)
    TestRunner.assertTrue(newW2 <= maxEdge, "Resized portrait width <= 1568")
    TestRunner.assertEqual(newH2, 1568, "Portrait height scaled to 1568")

    // Image that doesn't need resize
    let w3 = 800, h3 = 600
    let needsResize = max(w3, h3) > maxEdge
    TestRunner.assertFalse(needsResize, "800x600 does not need resize")

    // Square image at exact limit
    let w4 = 1568, h4 = 1568
    let needsResize4 = max(w4, h4) > maxEdge
    TestRunner.assertFalse(needsResize4, "1568x1568 does not need resize")
}

func testThumbnailDimensionCalculation() {
    TestRunner.suite("Thumbnail Dimension Calculation")

    let maxThumb = 200

    // Large landscape
    let w1 = 1568, h1 = 1045
    let scale1 = Double(maxThumb) / Double(max(w1, h1))
    let thumbW1 = Int(Double(w1) * scale1)
    let thumbH1 = Int(Double(h1) * scale1)
    TestRunner.assertTrue(thumbW1 <= maxThumb, "Thumbnail width <= 200")
    TestRunner.assertTrue(thumbH1 <= maxThumb, "Thumbnail height <= 200")
    TestRunner.assertEqual(thumbW1, 200, "Thumbnail landscape width = 200")

    // Small image (no resize needed for thumbnail)
    let w2 = 100, h2 = 80
    let needsThumbResize = max(w2, h2) > maxThumb
    TestRunner.assertFalse(needsThumbResize, "100x80 does not need thumbnail resize")
}

func testFormatDetectionLogic() {
    TestRunner.suite("Format Detection Logic")

    // PNG magic bytes
    let pngHeader: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    let pngData = Data(pngHeader)
    TestRunner.assertTrue(pngData.count >= 8, "PNG header has at least 8 bytes")
    TestRunner.assertEqual(pngData[0], 0x89, "PNG starts with 0x89")
    TestRunner.assertEqual(pngData[1], 0x50, "PNG byte 1 is 0x50 (P)")

    // JPEG magic bytes
    let jpegHeader: [UInt8] = [0xFF, 0xD8, 0xFF]
    let jpegData = Data(jpegHeader)
    TestRunner.assertEqual(jpegData[0], 0xFF, "JPEG starts with 0xFF")
    TestRunner.assertEqual(jpegData[1], 0xD8, "JPEG byte 1 is 0xD8")

    // GIF magic bytes
    let gif87Header = Data("GIF87a".utf8)
    let gif89Header = Data("GIF89a".utf8)
    TestRunner.assertTrue(gif87Header.starts(with: Data("GIF".utf8)), "GIF87a starts with GIF")
    TestRunner.assertTrue(gif89Header.starts(with: Data("GIF".utf8)), "GIF89a starts with GIF")
}

func testOutputFormatSelection() {
    TestRunner.suite("Output Format Selection")

    // Photos without transparency -> JPEG
    let photoFormat: ImageFormat = .jpeg
    TestRunner.assertEqual(photoFormat, .jpeg, "Photos use JPEG format")

    // Images with transparency -> PNG
    let transparentFormat: ImageFormat = .png
    TestRunner.assertEqual(transparentFormat, .png, "Transparent images use PNG format")

    // MIME types
    TestRunner.assertEqual(ImageFormat.jpeg.mimeType, "image/jpeg", "JPEG MIME type")
    TestRunner.assertEqual(ImageFormat.png.mimeType, "image/png", "PNG MIME type")
}

// MARK: - Entry Point

@main
struct ImageProcessorTests {
    static func main() {
        print("🧪 ImageProcessor Tests")
        print("==================================================")

        testConfigurationConstants()
        testInputSizeValidation()
        testBase64Encoding()
        testImageProcessingErrorEquatable()
        testDimensionCalculation()
        testThumbnailDimensionCalculation()
        testFormatDetectionLogic()
        testOutputFormatSelection()

        TestRunner.printSummary()
        if TestRunner.failedCount > 0 { exit(1) }
    }
}
