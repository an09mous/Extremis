// MARK: - ImagePersistence Tests
// Tests for save/load round-trip, restore from ImageRef, delete, file naming, missing file handling

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
            failedTests.append((testName, "Expected nil but got value"))
            print("  ✗ \(testName): Expected nil but got value")
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

struct ImageAttachment: Identifiable, Codable, Equatable {
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

    init(id: UUID = UUID(), imageData: Data, thumbnailData: Data, originalFilename: String? = nil,
         width: Int, height: Int, fileSize: Int, format: ImageFormat, mimeType: String,
         sourceType: ImageSourceType, createdAt: Date = Date()) {
        self.id = id; self.imageData = imageData; self.thumbnailData = thumbnailData
        self.originalFilename = originalFilename; self.width = width; self.height = height
        self.fileSize = fileSize; self.format = format; self.mimeType = mimeType
        self.sourceType = sourceType; self.createdAt = createdAt
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
        self.id = id; self.filename = filename; self.thumbnailBase64 = thumbnailBase64
        self.originalFilename = originalFilename; self.width = width; self.height = height; self.format = format
    }
}

// MARK: - Tests

func testFileNamingConvention() {
    TestRunner.suite("File Naming Convention")

    let id = UUID()
    let attachment = ImageAttachment(
        id: id, imageData: Data(repeating: 0xFF, count: 10), thumbnailData: Data(repeating: 0xAA, count: 5),
        width: 100, height: 100, fileSize: 10, format: .jpeg, mimeType: "image/jpeg", sourceType: .clipboard
    )
    let ref = ImageRef(from: attachment)

    TestRunner.assertEqual(ref.filename, "\(id.uuidString).jpeg", "JPEG filename follows {uuid}.jpeg convention")

    let pngAttachment = ImageAttachment(
        id: id, imageData: Data(repeating: 0xFF, count: 10), thumbnailData: Data(repeating: 0xAA, count: 5),
        width: 100, height: 100, fileSize: 10, format: .png, mimeType: "image/png", sourceType: .filePicker
    )
    let pngRef = ImageRef(from: pngAttachment)
    TestRunner.assertEqual(pngRef.filename, "\(id.uuidString).png", "PNG filename follows {uuid}.png convention")
}

func testImageRefPreservesMetadata() {
    TestRunner.suite("ImageRef Preserves Metadata")

    let id = UUID()
    let thumbData = Data(repeating: 0xBB, count: 30)
    let attachment = ImageAttachment(
        id: id, imageData: Data(repeating: 0xFF, count: 100), thumbnailData: thumbData,
        originalFilename: "photo.jpg", width: 1024, height: 768, fileSize: 100,
        format: .jpeg, mimeType: "image/jpeg", sourceType: .dragAndDrop
    )
    let ref = ImageRef(from: attachment)

    TestRunner.assertEqual(ref.id, id, "ID preserved")
    TestRunner.assertEqual(ref.originalFilename, "photo.jpg", "Original filename preserved")
    TestRunner.assertEqual(ref.width, 1024, "Width preserved")
    TestRunner.assertEqual(ref.height, 768, "Height preserved")
    TestRunner.assertEqual(ref.format, "jpeg", "Format preserved")
    TestRunner.assertEqual(ref.thumbnailBase64, thumbData.base64EncodedString(), "Thumbnail base64 correct")
}

func testSaveLoadRoundTrip() {
    TestRunner.suite("Save/Load Round Trip (simulated)")

    let id = UUID()
    let imageData = Data(repeating: 0xFF, count: 500)
    let thumbData = Data(repeating: 0xAA, count: 50)
    let attachment = ImageAttachment(
        id: id, imageData: imageData, thumbnailData: thumbData,
        originalFilename: "test.png", width: 640, height: 480, fileSize: 500,
        format: .png, mimeType: "image/png", sourceType: .filePicker
    )

    // Simulate save: write image data to temp file
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("extremis-test-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let ref = ImageRef(from: attachment)
    let filePath = tempDir.appendingPathComponent(ref.filename)

    do {
        try imageData.write(to: filePath, options: .atomic)
        TestRunner.assertTrue(FileManager.default.fileExists(atPath: filePath.path), "Image file written to disk")

        // Simulate load: read back
        let loadedData = try Data(contentsOf: filePath)
        TestRunner.assertEqual(loadedData, imageData, "Loaded data matches original")
        TestRunner.assertEqual(loadedData.count, 500, "Loaded data size correct")
    } catch {
        TestRunner.assertTrue(false, "Save/load round trip failed: \(error)")
    }

    // Cleanup
    try? FileManager.default.removeItem(at: tempDir)
}

func testDeleteImageFile() {
    TestRunner.suite("Delete Image File")

    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("extremis-test-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let filename = "\(UUID().uuidString).jpeg"
    let filePath = tempDir.appendingPathComponent(filename)

    // Write
    try? Data(repeating: 0xFF, count: 100).write(to: filePath)
    TestRunner.assertTrue(FileManager.default.fileExists(atPath: filePath.path), "File exists before delete")

    // Delete
    try? FileManager.default.removeItem(at: filePath)
    TestRunner.assertFalse(FileManager.default.fileExists(atPath: filePath.path), "File removed after delete")

    // Cleanup
    try? FileManager.default.removeItem(at: tempDir)
}

func testMissingFileHandling() {
    TestRunner.suite("Missing File Handling")

    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("extremis-test-\(UUID().uuidString)")
    let nonExistentFile = tempDir.appendingPathComponent("nonexistent.jpeg")

    let exists = FileManager.default.fileExists(atPath: nonExistentFile.path)
    TestRunner.assertFalse(exists, "Non-existent file correctly detected")

    // Attempting to load should fail gracefully
    do {
        _ = try Data(contentsOf: nonExistentFile)
        TestRunner.assertTrue(false, "Should have thrown for missing file")
    } catch {
        TestRunner.assertTrue(true, "Missing file throws error as expected")
    }
}

func testThumbnailBase64InRef() {
    TestRunner.suite("Thumbnail Base64 in ImageRef")

    let thumbData = Data([0x01, 0x02, 0x03, 0x04, 0x05])
    let attachment = ImageAttachment(
        id: UUID(), imageData: Data(repeating: 0xFF, count: 100), thumbnailData: thumbData,
        width: 200, height: 150, fileSize: 100,
        format: .jpeg, mimeType: "image/jpeg", sourceType: .clipboard
    )
    let ref = ImageRef(from: attachment)

    // Verify base64 can be decoded back
    if let decoded = Data(base64Encoded: ref.thumbnailBase64) {
        TestRunner.assertEqual(decoded, thumbData, "Thumbnail base64 decodes to original data")
    } else {
        TestRunner.assertTrue(false, "Thumbnail base64 decoding failed")
    }
}

func testMultipleImagesSaveLoad() {
    TestRunner.suite("Multiple Images Save/Load")

    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("extremis-test-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    var refs: [ImageRef] = []
    let imageCount = 5

    // Save multiple images
    for i in 0..<imageCount {
        let attachment = ImageAttachment(
            imageData: Data(repeating: UInt8(i), count: 100 + i * 10),
            thumbnailData: Data(repeating: UInt8(i), count: 20),
            width: 100, height: 100, fileSize: 100 + i * 10,
            format: i % 2 == 0 ? .jpeg : .png,
            mimeType: i % 2 == 0 ? "image/jpeg" : "image/png",
            sourceType: .clipboard
        )
        let ref = ImageRef(from: attachment)
        let filePath = tempDir.appendingPathComponent(ref.filename)
        try? attachment.imageData.write(to: filePath)
        refs.append(ref)
    }

    TestRunner.assertEqual(refs.count, imageCount, "Created \(imageCount) image refs")

    // Load all back
    var loadedCount = 0
    for ref in refs {
        let filePath = tempDir.appendingPathComponent(ref.filename)
        if FileManager.default.fileExists(atPath: filePath.path) {
            loadedCount += 1
        }
    }
    TestRunner.assertEqual(loadedCount, imageCount, "All \(imageCount) image files loadable")

    // Cleanup
    try? FileManager.default.removeItem(at: tempDir)
}

// MARK: - Entry Point

@main
struct ImagePersistenceTests {
    static func main() {
        print("🧪 ImagePersistence Tests")
        print("==================================================")

        testFileNamingConvention()
        testImageRefPreservesMetadata()
        testSaveLoadRoundTrip()
        testDeleteImageFile()
        testMissingFileHandling()
        testThumbnailBase64InRef()
        testMultipleImagesSaveLoad()

        TestRunner.printSummary()
        if TestRunner.failedCount > 0 { exit(1) }
    }
}
