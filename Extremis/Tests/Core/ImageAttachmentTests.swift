// MARK: - ImageAttachment Model Tests
// Tests for ImageAttachment, ImageRef, ImageFormat, ImageSourceType

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

    static func assertNotNil<T>(_ value: T?, _ testName: String) {
        if value != nil {
            passedCount += 1
            print("  ✓ \(testName)")
        } else {
            failedCount += 1
            failedTests.append((testName, "Expected non-nil but got nil"))
            print("  ✗ \(testName): Expected non-nil but got nil")
        }
    }

    static func assertNil<T>(_ value: T?, _ testName: String) {
        if value == nil {
            passedCount += 1
            print("  ✓ \(testName)")
        } else {
            failedCount += 1
            failedTests.append((testName, "Expected nil but got \(value!)"))
            print("  ✗ \(testName): Expected nil but got \(value!)")
        }
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

// MARK: - Inline Type Definitions (for standalone compilation)

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

enum ImageSourceType: String, Codable, Equatable, Hashable {
    case clipboard
    case filePicker = "file_picker"
    case dragAndDrop = "drag_and_drop"
}

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

    var base64EncodedData: String {
        imageData.base64EncodedString()
    }
}

struct ImageRef: Codable, Equatable {
    let id: UUID
    let filename: String
    let thumbnailBase64: String
    let originalFilename: String?
    let width: Int
    let height: Int
    let format: String

    init(from attachment: ImageAttachment) {
        self.id = attachment.id
        self.filename = "\(attachment.id.uuidString).\(attachment.format.rawValue)"
        self.thumbnailBase64 = attachment.thumbnailData.base64EncodedString()
        self.originalFilename = attachment.originalFilename
        self.width = attachment.width
        self.height = attachment.height
        self.format = attachment.format.rawValue
    }

    init(id: UUID, filename: String, thumbnailBase64: String, originalFilename: String?, width: Int, height: Int, format: String) {
        self.id = id
        self.filename = filename
        self.thumbnailBase64 = thumbnailBase64
        self.originalFilename = originalFilename
        self.width = width
        self.height = height
        self.format = format
    }

    var thumbnailData: Data? {
        Data(base64Encoded: thumbnailBase64)
    }

    var imageFormat: ImageFormat? {
        ImageFormat(rawValue: format)
    }
}

// MARK: - Tests

func testImageFormatEnum() {
    TestRunner.suite("ImageFormat Enum")

    TestRunner.assertEqual(ImageFormat.jpeg.rawValue, "jpeg", "JPEG raw value")
    TestRunner.assertEqual(ImageFormat.png.rawValue, "png", "PNG raw value")
    TestRunner.assertEqual(ImageFormat.jpeg.mimeType, "image/jpeg", "JPEG mime type")
    TestRunner.assertEqual(ImageFormat.png.mimeType, "image/png", "PNG mime type")

    // Codable round-trip
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    if let data = try? encoder.encode(ImageFormat.jpeg),
       let decoded = try? decoder.decode(ImageFormat.self, from: data) {
        TestRunner.assertEqual(decoded, ImageFormat.jpeg, "ImageFormat Codable round-trip JPEG")
    } else {
        TestRunner.assertTrue(false, "ImageFormat Codable round-trip JPEG")
    }
    if let data = try? encoder.encode(ImageFormat.png),
       let decoded = try? decoder.decode(ImageFormat.self, from: data) {
        TestRunner.assertEqual(decoded, ImageFormat.png, "ImageFormat Codable round-trip PNG")
    } else {
        TestRunner.assertTrue(false, "ImageFormat Codable round-trip PNG")
    }
}

func testImageSourceTypeEnum() {
    TestRunner.suite("ImageSourceType Enum")

    TestRunner.assertEqual(ImageSourceType.clipboard.rawValue, "clipboard", "Clipboard raw value")
    TestRunner.assertEqual(ImageSourceType.filePicker.rawValue, "file_picker", "File picker raw value")
    TestRunner.assertEqual(ImageSourceType.dragAndDrop.rawValue, "drag_and_drop", "Drag and drop raw value")

    // Codable round-trip
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    for sourceType in [ImageSourceType.clipboard, .filePicker, .dragAndDrop] {
        if let data = try? encoder.encode(sourceType),
           let decoded = try? decoder.decode(ImageSourceType.self, from: data) {
            TestRunner.assertEqual(decoded, sourceType, "ImageSourceType Codable round-trip \(sourceType.rawValue)")
        } else {
            TestRunner.assertTrue(false, "ImageSourceType Codable round-trip \(sourceType.rawValue)")
        }
    }
}

func testImageAttachmentCodable() {
    TestRunner.suite("ImageAttachment Codable")

    let imageData = Data(repeating: 0xFF, count: 100)
    let thumbData = Data(repeating: 0xAA, count: 50)
    let id = UUID()
    let date = Date(timeIntervalSince1970: 1700000000)

    let attachment = ImageAttachment(
        id: id,
        imageData: imageData,
        thumbnailData: thumbData,
        originalFilename: "test.jpg",
        width: 800,
        height: 600,
        fileSize: 100,
        format: .jpeg,
        mimeType: "image/jpeg",
        sourceType: .clipboard,
        createdAt: date
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    if let data = try? encoder.encode(attachment),
       let decoded = try? decoder.decode(ImageAttachment.self, from: data) {
        TestRunner.assertEqual(decoded.id, id, "Codable round-trip preserves id")
        TestRunner.assertEqual(decoded.imageData, imageData, "Codable round-trip preserves imageData")
        TestRunner.assertEqual(decoded.thumbnailData, thumbData, "Codable round-trip preserves thumbnailData")
        TestRunner.assertEqual(decoded.originalFilename, "test.jpg", "Codable round-trip preserves originalFilename")
        TestRunner.assertEqual(decoded.width, 800, "Codable round-trip preserves width")
        TestRunner.assertEqual(decoded.height, 600, "Codable round-trip preserves height")
        TestRunner.assertEqual(decoded.fileSize, 100, "Codable round-trip preserves fileSize")
        TestRunner.assertEqual(decoded.format, .jpeg, "Codable round-trip preserves format")
        TestRunner.assertEqual(decoded.mimeType, "image/jpeg", "Codable round-trip preserves mimeType")
        TestRunner.assertEqual(decoded.sourceType, .clipboard, "Codable round-trip preserves sourceType")
    } else {
        TestRunner.assertTrue(false, "ImageAttachment Codable encoding/decoding failed")
    }
}

func testImageAttachmentEquatable() {
    TestRunner.suite("ImageAttachment Equatable")

    let id = UUID()
    let imageData = Data(repeating: 0xFF, count: 100)
    let thumbData = Data(repeating: 0xAA, count: 50)
    let date = Date()

    let a = ImageAttachment(id: id, imageData: imageData, thumbnailData: thumbData,
                            width: 800, height: 600, fileSize: 100,
                            format: .jpeg, mimeType: "image/jpeg", sourceType: .clipboard, createdAt: date)
    let b = ImageAttachment(id: id, imageData: imageData, thumbnailData: thumbData,
                            width: 800, height: 600, fileSize: 100,
                            format: .jpeg, mimeType: "image/jpeg", sourceType: .clipboard, createdAt: date)
    let c = ImageAttachment(id: UUID(), imageData: imageData, thumbnailData: thumbData,
                            width: 800, height: 600, fileSize: 100,
                            format: .jpeg, mimeType: "image/jpeg", sourceType: .clipboard, createdAt: date)

    TestRunner.assertTrue(a == b, "Same fields are equal")
    TestRunner.assertFalse(a == c, "Different IDs are not equal")
}

func testImageAttachmentNilFilename() {
    TestRunner.suite("ImageAttachment Nil Filename")

    let attachment = ImageAttachment(
        imageData: Data(repeating: 0xFF, count: 10),
        thumbnailData: Data(repeating: 0xAA, count: 5),
        originalFilename: nil,
        width: 100, height: 100, fileSize: 10,
        format: .png, mimeType: "image/png", sourceType: .clipboard
    )

    TestRunner.assertNil(attachment.originalFilename, "Clipboard paste has nil filename")

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    encoder.dateEncodingStrategy = .iso8601
    decoder.dateDecodingStrategy = .iso8601

    if let data = try? encoder.encode(attachment),
       let decoded = try? decoder.decode(ImageAttachment.self, from: data) {
        TestRunner.assertNil(decoded.originalFilename, "Nil filename survives Codable round-trip")
    } else {
        TestRunner.assertTrue(false, "Nil filename Codable round-trip failed")
    }
}

func testImageRefFromAttachment() {
    TestRunner.suite("ImageRef from ImageAttachment")

    let id = UUID()
    let thumbData = Data(repeating: 0xBB, count: 20)
    let attachment = ImageAttachment(
        id: id,
        imageData: Data(repeating: 0xFF, count: 100),
        thumbnailData: thumbData,
        originalFilename: "screenshot.png",
        width: 1024, height: 768, fileSize: 100,
        format: .png, mimeType: "image/png", sourceType: .filePicker
    )

    let ref = ImageRef(from: attachment)

    TestRunner.assertEqual(ref.id, id, "ImageRef id matches attachment")
    TestRunner.assertEqual(ref.filename, "\(id.uuidString).png", "ImageRef filename has correct format")
    TestRunner.assertEqual(ref.thumbnailBase64, thumbData.base64EncodedString(), "ImageRef thumbnail is base64 encoded")
    TestRunner.assertEqual(ref.originalFilename, "screenshot.png", "ImageRef preserves originalFilename")
    TestRunner.assertEqual(ref.width, 1024, "ImageRef preserves width")
    TestRunner.assertEqual(ref.height, 768, "ImageRef preserves height")
    TestRunner.assertEqual(ref.format, "png", "ImageRef format is raw string")
}

func testImageRefCodable() {
    TestRunner.suite("ImageRef Codable")

    let ref = ImageRef(
        id: UUID(),
        filename: "test.jpg",
        thumbnailBase64: "base64data",
        originalFilename: "photo.jpg",
        width: 640, height: 480,
        format: "jpeg"
    )

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    if let data = try? encoder.encode(ref),
       let decoded = try? decoder.decode(ImageRef.self, from: data) {
        TestRunner.assertEqual(decoded.id, ref.id, "ImageRef Codable round-trip id")
        TestRunner.assertEqual(decoded.filename, "test.jpg", "ImageRef Codable round-trip filename")
        TestRunner.assertEqual(decoded.thumbnailBase64, "base64data", "ImageRef Codable round-trip thumbnail")
        TestRunner.assertEqual(decoded.originalFilename, "photo.jpg", "ImageRef Codable round-trip originalFilename")
        TestRunner.assertEqual(decoded.width, 640, "ImageRef Codable round-trip width")
        TestRunner.assertEqual(decoded.height, 480, "ImageRef Codable round-trip height")
        TestRunner.assertEqual(decoded.format, "jpeg", "ImageRef Codable round-trip format")
    } else {
        TestRunner.assertTrue(false, "ImageRef Codable encoding/decoding failed")
    }
}

func testImageRefNilOriginalFilename() {
    TestRunner.suite("ImageRef Nil Original Filename")

    let ref = ImageRef(
        id: UUID(), filename: "test.jpg", thumbnailBase64: "data",
        originalFilename: nil, width: 100, height: 100, format: "jpeg"
    )

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    if let data = try? encoder.encode(ref),
       let decoded = try? decoder.decode(ImageRef.self, from: data) {
        TestRunner.assertNil(decoded.originalFilename, "Nil originalFilename survives Codable round-trip")
    } else {
        TestRunner.assertTrue(false, "ImageRef nil originalFilename round-trip failed")
    }
}

// MARK: - ImageRef Computed Properties Tests

func testImageRefThumbnailData() {
    TestRunner.suite("ImageRef thumbnailData Computed Property")

    // Valid base64
    let originalData = Data([0xDE, 0xAD, 0xBE, 0xEF])
    let ref = ImageRef(
        id: UUID(), filename: "test.jpg",
        thumbnailBase64: originalData.base64EncodedString(),
        originalFilename: nil, width: 100, height: 100, format: "jpeg"
    )
    if let decoded = ref.thumbnailData {
        TestRunner.assertEqual(decoded, originalData, "thumbnailData decodes correctly from valid base64")
    } else {
        TestRunner.assertTrue(false, "thumbnailData should not be nil for valid base64")
    }

    // Invalid base64
    let badRef = ImageRef(
        id: UUID(), filename: "test.jpg",
        thumbnailBase64: "!!!not-base64!!!",
        originalFilename: nil, width: 100, height: 100, format: "jpeg"
    )
    TestRunner.assertNil(badRef.thumbnailData, "thumbnailData is nil for invalid base64")

    // Empty base64
    let emptyRef = ImageRef(
        id: UUID(), filename: "test.jpg",
        thumbnailBase64: "",
        originalFilename: nil, width: 100, height: 100, format: "jpeg"
    )
    if let decoded = emptyRef.thumbnailData {
        TestRunner.assertEqual(decoded, Data(), "Empty base64 decodes to empty Data")
    } else {
        TestRunner.assertTrue(false, "Empty base64 should decode to empty Data")
    }
}

func testImageRefImageFormat() {
    TestRunner.suite("ImageRef imageFormat Computed Property")

    let jpegRef = ImageRef(
        id: UUID(), filename: "test.jpg", thumbnailBase64: "",
        originalFilename: nil, width: 100, height: 100, format: "jpeg"
    )
    TestRunner.assertEqual(jpegRef.imageFormat, ImageFormat.jpeg, "imageFormat parses jpeg")

    let pngRef = ImageRef(
        id: UUID(), filename: "test.png", thumbnailBase64: "",
        originalFilename: nil, width: 100, height: 100, format: "png"
    )
    TestRunner.assertEqual(pngRef.imageFormat, ImageFormat.png, "imageFormat parses png")

    let unknownRef = ImageRef(
        id: UUID(), filename: "test.bmp", thumbnailBase64: "",
        originalFilename: nil, width: 100, height: 100, format: "bmp"
    )
    TestRunner.assertNil(unknownRef.imageFormat, "imageFormat returns nil for unknown format")

    let emptyRef = ImageRef(
        id: UUID(), filename: "test", thumbnailBase64: "",
        originalFilename: nil, width: 100, height: 100, format: ""
    )
    TestRunner.assertNil(emptyRef.imageFormat, "imageFormat returns nil for empty format string")
}

// MARK: - ImageFormat fileExtension Tests

func testImageFormatFileExtension() {
    TestRunner.suite("ImageFormat fileExtension")

    TestRunner.assertEqual(ImageFormat.jpeg.fileExtension, "jpeg", "JPEG file extension")
    TestRunner.assertEqual(ImageFormat.png.fileExtension, "png", "PNG file extension")
}

// MARK: - ImageRef filename format Tests

func testImageRefFilenameFormat() {
    TestRunner.suite("ImageRef Filename Format")

    let id = UUID()
    let jpegAttachment = ImageAttachment(
        id: id, imageData: Data([0xFF]), thumbnailData: Data([0xAA]),
        width: 100, height: 100, fileSize: 1,
        format: .jpeg, mimeType: "image/jpeg", sourceType: .clipboard
    )
    let jpegRef = ImageRef(from: jpegAttachment)
    TestRunner.assertEqual(jpegRef.filename, "\(id.uuidString).jpeg", "JPEG ref filename has .jpeg extension")

    let pngAttachment = ImageAttachment(
        id: id, imageData: Data([0xFF]), thumbnailData: Data([0xAA]),
        width: 100, height: 100, fileSize: 1,
        format: .png, mimeType: "image/png", sourceType: .filePicker
    )
    let pngRef = ImageRef(from: pngAttachment)
    TestRunner.assertEqual(pngRef.filename, "\(id.uuidString).png", "PNG ref filename has .png extension")
}

// MARK: - ImageAttachment base64EncodedData Tests

func testImageAttachmentBase64EncodedData() {
    TestRunner.suite("ImageAttachment base64EncodedData")

    let imageData = Data([0xDE, 0xAD, 0xBE, 0xEF])
    let attachment = ImageAttachment(
        imageData: imageData, thumbnailData: Data(),
        width: 10, height: 10, fileSize: 4,
        format: .jpeg, mimeType: "image/jpeg", sourceType: .clipboard
    )

    TestRunner.assertEqual(attachment.base64EncodedData, imageData.base64EncodedString(),
                           "base64EncodedData matches direct base64 encoding")

    // Empty data
    let emptyAttachment = ImageAttachment(
        imageData: Data(), thumbnailData: Data(),
        width: 0, height: 0, fileSize: 0,
        format: .png, mimeType: "image/png", sourceType: .clipboard
    )
    TestRunner.assertEqual(emptyAttachment.base64EncodedData, "", "Empty imageData produces empty base64")
}

// MARK: - ImageAttachment Hashable Tests

func testImageAttachmentHashable() {
    TestRunner.suite("ImageAttachment Hashable")

    let id = UUID()
    let date = Date()
    let a = ImageAttachment(
        id: id, imageData: Data([0xFF]), thumbnailData: Data([0xAA]),
        width: 100, height: 100, fileSize: 1,
        format: .jpeg, mimeType: "image/jpeg", sourceType: .clipboard, createdAt: date
    )
    let b = ImageAttachment(
        id: id, imageData: Data([0xFF]), thumbnailData: Data([0xAA]),
        width: 100, height: 100, fileSize: 1,
        format: .jpeg, mimeType: "image/jpeg", sourceType: .clipboard, createdAt: date
    )

    // Same objects should produce same hash
    TestRunner.assertEqual(a.hashValue, b.hashValue, "Equal attachments have equal hash values")

    // Can be used in a Set
    var set = Set<ImageAttachment>()
    set.insert(a)
    set.insert(b)
    TestRunner.assertEqual(set.count, 1, "Set deduplicates equal attachments")

    // Different attachment
    let c = ImageAttachment(
        id: UUID(), imageData: Data([0xFF]), thumbnailData: Data([0xAA]),
        width: 100, height: 100, fileSize: 1,
        format: .jpeg, mimeType: "image/jpeg", sourceType: .clipboard
    )
    set.insert(c)
    TestRunner.assertEqual(set.count, 2, "Set keeps distinct attachments")
}

// MARK: - Entry Point

@main
struct ImageAttachmentTests {
    static func main() {
        print("🧪 ImageAttachment Model Tests")
        print("==================================================")

        testImageFormatEnum()
        testImageSourceTypeEnum()
        testImageAttachmentCodable()
        testImageAttachmentEquatable()
        testImageAttachmentNilFilename()
        testImageRefFromAttachment()
        testImageRefCodable()
        testImageRefNilOriginalFilename()
        testImageRefThumbnailData()
        testImageRefImageFormat()
        testImageFormatFileExtension()
        testImageRefFilenameFormat()
        testImageAttachmentBase64EncodedData()
        testImageAttachmentHashable()

        TestRunner.printSummary()
        if TestRunner.failedCount > 0 { exit(1) }
    }
}
