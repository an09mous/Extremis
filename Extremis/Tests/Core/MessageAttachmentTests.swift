// MARK: - Message Attachment Tests
// Tests for ImageAttachment, MessageAttachment, and ChatMessage attachment support

import Foundation

// MARK: - Test Runner Framework

struct TestRunner {
    static var passedCount = 0
    static var failedCount = 0
    static var failedTests: [(name: String, message: String)] = []
    static var currentGroup = ""

    static func reset() {
        passedCount = 0
        failedCount = 0
        failedTests = []
        currentGroup = ""
    }

    static func setGroup(_ name: String) {
        currentGroup = name
        print("")
        print("📦 \(name)")
        print("----------------------------------------")
    }

    static func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ testName: String) {
        if actual == expected {
            passedCount += 1
            print("  ✓ \(testName)")
        } else {
            failedCount += 1
            let message = "Expected '\(expected)' but got '\(actual)'"
            failedTests.append((testName, message))
            print("  ✗ \(testName): \(message)")
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

    static func assertNil<T>(_ value: T?, _ testName: String) {
        if value == nil {
            passedCount += 1
            print("  ✓ \(testName)")
        } else {
            failedCount += 1
            let message = "Expected nil but got value"
            failedTests.append((testName, message))
            print("  ✗ \(testName): \(message)")
        }
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

    static func printSummary() {
        print("")
        print("==================================================")
        print("TEST SUMMARY")
        print("==================================================")
        print("Passed: \(passedCount)")
        print("Failed: \(failedCount)")
        print("Total:  \(passedCount + failedCount)")
        if !failedTests.isEmpty {
            print("")
            print("Failed tests:")
            for (name, message) in failedTests {
                print("  - \(name): \(message)")
            }
        }
        print("==================================================")
    }
}

// MARK: - Minimal Type Definitions for Standalone Compilation

enum ImageMediaType: String, Codable, Equatable, Hashable {
    case jpeg = "image/jpeg"
    case png = "image/png"
    case gif = "image/gif"
    case webp = "image/webp"

    var fileExtension: String {
        switch self {
        case .jpeg: return "jpeg"
        case .png: return "png"
        case .gif: return "gif"
        case .webp: return "webp"
        }
    }

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

enum MessageAttachment: Codable, Equatable, Identifiable {
    case image(ImageAttachment)

    var id: UUID {
        switch self {
        case .image(let img): return img.id
        }
    }

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

struct ImageAttachment: Codable, Equatable, Identifiable, Hashable {
    let id: UUID
    let mediaType: ImageMediaType
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

struct PersistedAttachmentRef: Codable, Equatable {
    let id: UUID
    let type: String
    let mediaType: String
    let width: Int?
    let height: Int?
    let fileSizeBytes: Int?
    let sourceFileName: String?

    init(from attachment: ImageAttachment) {
        self.id = attachment.id
        self.type = "image"
        self.mediaType = attachment.mediaType.rawValue
        self.width = attachment.width
        self.height = attachment.height
        self.fileSizeBytes = attachment.fileSizeBytes
        self.sourceFileName = attachment.sourceFileName
    }

    static func fromAttachment(_ attachment: MessageAttachment) -> PersistedAttachmentRef {
        switch attachment {
        case .image(let img):
            return PersistedAttachmentRef(from: img)
        }
    }
}

// Minimal ChatMessage for testing attachment support
enum ChatRole: String, Codable, Equatable {
    case system, user, assistant
}

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: ChatRole
    let content: String
    let attachments: [MessageAttachment]?

    init(id: UUID = UUID(), role: ChatRole, content: String, attachments: [MessageAttachment]? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.attachments = attachments
    }

    static func user(_ content: String, attachments: [MessageAttachment]? = nil) -> ChatMessage {
        ChatMessage(role: .user, content: content, attachments: attachments)
    }

    static func assistant(_ content: String) -> ChatMessage {
        ChatMessage(role: .assistant, content: content)
    }

    var hasAttachments: Bool {
        guard let attachments = attachments else { return false }
        return !attachments.isEmpty
    }

    var imageAttachments: [ImageAttachment] {
        attachments?.compactMap {
            if case .image(let img) = $0 { return img }
            return nil
        } ?? []
    }
}

// MARK: - Tests

func testImageMediaType() {
    TestRunner.setGroup("ImageMediaType")

    // Test raw values
    TestRunner.assertEqual(ImageMediaType.jpeg.rawValue, "image/jpeg", "JPEG raw value")
    TestRunner.assertEqual(ImageMediaType.png.rawValue, "image/png", "PNG raw value")
    TestRunner.assertEqual(ImageMediaType.gif.rawValue, "image/gif", "GIF raw value")
    TestRunner.assertEqual(ImageMediaType.webp.rawValue, "image/webp", "WebP raw value")

    // Test file extensions
    TestRunner.assertEqual(ImageMediaType.jpeg.fileExtension, "jpeg", "JPEG file extension")
    TestRunner.assertEqual(ImageMediaType.png.fileExtension, "png", "PNG file extension")
    TestRunner.assertEqual(ImageMediaType.gif.fileExtension, "gif", "GIF file extension")
    TestRunner.assertEqual(ImageMediaType.webp.fileExtension, "webp", "WebP file extension")

    // Test init from file extension
    TestRunner.assertEqual(ImageMediaType(fileExtension: "jpeg"), .jpeg, "Init from 'jpeg'")
    TestRunner.assertEqual(ImageMediaType(fileExtension: "jpg"), .jpeg, "Init from 'jpg'")
    TestRunner.assertEqual(ImageMediaType(fileExtension: "JPG"), .jpeg, "Init from 'JPG' (case insensitive)")
    TestRunner.assertEqual(ImageMediaType(fileExtension: "png"), .png, "Init from 'png'")
    TestRunner.assertEqual(ImageMediaType(fileExtension: "gif"), .gif, "Init from 'gif'")
    TestRunner.assertEqual(ImageMediaType(fileExtension: "webp"), .webp, "Init from 'webp'")
    TestRunner.assertNil(ImageMediaType(fileExtension: "bmp"), "Unknown extension returns nil")
    TestRunner.assertNil(ImageMediaType(fileExtension: "svg"), "SVG extension returns nil")

    // Test Codable roundtrip
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    for mediaType in [ImageMediaType.jpeg, .png, .gif, .webp] {
        do {
            let data = try encoder.encode(mediaType)
            let decoded = try decoder.decode(ImageMediaType.self, from: data)
            TestRunner.assertEqual(decoded, mediaType, "Codable roundtrip for \(mediaType)")
        } catch {
            TestRunner.assertTrue(false, "Codable roundtrip should not throw for \(mediaType): \(error)")
        }
    }
}

func testImageAttachment() {
    TestRunner.setGroup("ImageAttachment")

    let id = UUID()
    let attachment = ImageAttachment(
        id: id,
        mediaType: .jpeg,
        base64Data: "dGVzdA==",
        width: 800,
        height: 600,
        fileSizeBytes: 245760,
        sourceFileName: "photo.jpg"
    )

    TestRunner.assertEqual(attachment.id, id, "ID matches")
    TestRunner.assertEqual(attachment.mediaType, .jpeg, "Media type matches")
    TestRunner.assertEqual(attachment.base64Data, "dGVzdA==", "Base64 data matches")
    TestRunner.assertEqual(attachment.width, 800, "Width matches")
    TestRunner.assertEqual(attachment.height, 600, "Height matches")
    TestRunner.assertEqual(attachment.fileSizeBytes, 245760, "File size matches")
    TestRunner.assertEqual(attachment.sourceFileName, "photo.jpg", "Source file name matches")

    // Test formatted file size
    TestRunner.assertEqual(attachment.formattedFileSize, "240 KB", "Formatted file size for 245760 bytes")

    let smallAttachment = ImageAttachment(mediaType: .png, base64Data: "x", fileSizeBytes: 512)
    TestRunner.assertEqual(smallAttachment.formattedFileSize, "512 B", "Formatted file size for bytes")

    let largeAttachment = ImageAttachment(mediaType: .png, base64Data: "x", fileSizeBytes: 5_242_880)
    TestRunner.assertEqual(largeAttachment.formattedFileSize, "5.0 MB", "Formatted file size for MB")

    let noSizeAttachment = ImageAttachment(mediaType: .png, base64Data: "x")
    TestRunner.assertNil(noSizeAttachment.formattedFileSize, "Nil file size returns nil formatted")

    // Test default values
    let minimal = ImageAttachment(mediaType: .png, base64Data: "abc")
    TestRunner.assertNil(minimal.width, "Default width is nil")
    TestRunner.assertNil(minimal.height, "Default height is nil")
    TestRunner.assertNil(minimal.fileSizeBytes, "Default file size is nil")
    TestRunner.assertNil(minimal.sourceFileName, "Default source file name is nil")
}

func testImageAttachmentCodable() {
    TestRunner.setGroup("ImageAttachment Codable")

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    // Full attachment roundtrip
    let original = ImageAttachment(
        mediaType: .jpeg,
        base64Data: "aW1hZ2U=",
        width: 1024,
        height: 768,
        fileSizeBytes: 102400,
        sourceFileName: "test.jpg"
    )

    do {
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ImageAttachment.self, from: data)
        TestRunner.assertEqual(decoded.id, original.id, "Roundtrip preserves ID")
        TestRunner.assertEqual(decoded.mediaType, original.mediaType, "Roundtrip preserves media type")
        TestRunner.assertEqual(decoded.base64Data, original.base64Data, "Roundtrip preserves base64 data")
        TestRunner.assertEqual(decoded.width, original.width, "Roundtrip preserves width")
        TestRunner.assertEqual(decoded.height, original.height, "Roundtrip preserves height")
        TestRunner.assertEqual(decoded.fileSizeBytes, original.fileSizeBytes, "Roundtrip preserves file size")
        TestRunner.assertEqual(decoded.sourceFileName, original.sourceFileName, "Roundtrip preserves source file name")
    } catch {
        TestRunner.assertTrue(false, "Full attachment Codable roundtrip should not throw: \(error)")
    }

    // Minimal attachment roundtrip (nil optionals)
    let minimal = ImageAttachment(mediaType: .png, base64Data: "data")

    do {
        let data = try encoder.encode(minimal)
        let decoded = try decoder.decode(ImageAttachment.self, from: data)
        TestRunner.assertEqual(decoded.mediaType, .png, "Minimal roundtrip preserves media type")
        TestRunner.assertEqual(decoded.base64Data, "data", "Minimal roundtrip preserves base64 data")
        TestRunner.assertNil(decoded.width, "Minimal roundtrip has nil width")
        TestRunner.assertNil(decoded.height, "Minimal roundtrip has nil height")
        TestRunner.assertNil(decoded.fileSizeBytes, "Minimal roundtrip has nil file size")
        TestRunner.assertNil(decoded.sourceFileName, "Minimal roundtrip has nil source file name")
    } catch {
        TestRunner.assertTrue(false, "Minimal attachment Codable roundtrip should not throw: \(error)")
    }
}

func testMessageAttachmentEnum() {
    TestRunner.setGroup("MessageAttachment Enum")

    let img = ImageAttachment(mediaType: .jpeg, base64Data: "abc")
    let attachment = MessageAttachment.image(img)

    // Test ID forwarding
    TestRunner.assertEqual(attachment.id, img.id, "MessageAttachment.id forwards to ImageAttachment.id")

    // Test Codable roundtrip
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    do {
        let data = try encoder.encode(attachment)
        let decoded = try decoder.decode(MessageAttachment.self, from: data)
        TestRunner.assertEqual(decoded.id, attachment.id, "Codable roundtrip preserves ID")

        if case .image(let decodedImg) = decoded {
            TestRunner.assertEqual(decodedImg.mediaType, .jpeg, "Decoded image has correct media type")
            TestRunner.assertEqual(decodedImg.base64Data, "abc", "Decoded image has correct base64 data")
        } else {
            TestRunner.assertTrue(false, "Decoded attachment should be .image case")
        }
    } catch {
        TestRunner.assertTrue(false, "MessageAttachment Codable roundtrip should not throw: \(error)")
    }

    // Test array of attachments Codable
    let attachments = [
        MessageAttachment.image(ImageAttachment(mediaType: .jpeg, base64Data: "a")),
        MessageAttachment.image(ImageAttachment(mediaType: .png, base64Data: "b")),
    ]

    do {
        let data = try encoder.encode(attachments)
        let decoded = try decoder.decode([MessageAttachment].self, from: data)
        TestRunner.assertEqual(decoded.count, 2, "Array roundtrip preserves count")
        TestRunner.assertEqual(decoded[0].id, attachments[0].id, "Array roundtrip preserves first ID")
        TestRunner.assertEqual(decoded[1].id, attachments[1].id, "Array roundtrip preserves second ID")
    } catch {
        TestRunner.assertTrue(false, "MessageAttachment array Codable roundtrip should not throw: \(error)")
    }
}

func testChatMessageWithAttachments() {
    TestRunner.setGroup("ChatMessage with Attachments")

    // Message without attachments (backward compat)
    let textOnly = ChatMessage(role: .user, content: "Hello")
    TestRunner.assertFalse(textOnly.hasAttachments, "Text-only message has no attachments")
    TestRunner.assertTrue(textOnly.imageAttachments.isEmpty, "Text-only message has empty imageAttachments")

    // Message with nil attachments
    let nilAttachments = ChatMessage(role: .user, content: "Hi", attachments: nil)
    TestRunner.assertFalse(nilAttachments.hasAttachments, "Nil attachments message has no attachments")

    // Message with empty attachments
    let emptyAttachments = ChatMessage(role: .user, content: "Hi", attachments: [])
    TestRunner.assertFalse(emptyAttachments.hasAttachments, "Empty attachments message has no attachments")

    // Message with images
    let img1 = ImageAttachment(mediaType: .jpeg, base64Data: "a")
    let img2 = ImageAttachment(mediaType: .png, base64Data: "b")
    let withImages = ChatMessage.user("Check these", attachments: [.image(img1), .image(img2)])
    TestRunner.assertTrue(withImages.hasAttachments, "Message with images has attachments")
    TestRunner.assertEqual(withImages.imageAttachments.count, 2, "Message has 2 image attachments")
    TestRunner.assertEqual(withImages.imageAttachments[0].id, img1.id, "First image ID matches")
    TestRunner.assertEqual(withImages.imageAttachments[1].id, img2.id, "Second image ID matches")

    // Image-only message (no text)
    let imageOnly = ChatMessage.user("", attachments: [.image(img1)])
    TestRunner.assertTrue(imageOnly.hasAttachments, "Image-only message has attachments")
    TestRunner.assertEqual(imageOnly.content, "", "Image-only message has empty content")

    // Assistant message (no attachments)
    let assistant = ChatMessage.assistant("Response text")
    TestRunner.assertFalse(assistant.hasAttachments, "Assistant message has no attachments")
}

func testChatMessageCodableWithAttachments() {
    TestRunner.setGroup("ChatMessage Codable with Attachments")

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    // Roundtrip with attachments
    let img = ImageAttachment(mediaType: .jpeg, base64Data: "test123", width: 640, height: 480)
    let original = ChatMessage.user("Look at this", attachments: [.image(img)])

    do {
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ChatMessage.self, from: data)
        TestRunner.assertEqual(decoded.id, original.id, "Codable preserves message ID")
        TestRunner.assertEqual(decoded.content, "Look at this", "Codable preserves content")
        TestRunner.assertTrue(decoded.hasAttachments, "Codable preserves hasAttachments")
        TestRunner.assertEqual(decoded.imageAttachments.count, 1, "Codable preserves image count")
        TestRunner.assertEqual(decoded.imageAttachments[0].mediaType, .jpeg, "Codable preserves image media type")
        TestRunner.assertEqual(decoded.imageAttachments[0].base64Data, "test123", "Codable preserves image data")
    } catch {
        TestRunner.assertTrue(false, "ChatMessage with attachments Codable should not throw: \(error)")
    }

    // Roundtrip without attachments (backward compatibility)
    let textOnly = ChatMessage(role: .user, content: "No images")

    do {
        let data = try encoder.encode(textOnly)
        let decoded = try decoder.decode(ChatMessage.self, from: data)
        TestRunner.assertEqual(decoded.content, "No images", "Text-only Codable preserves content")
        TestRunner.assertFalse(decoded.hasAttachments, "Text-only Codable has no attachments")
    } catch {
        TestRunner.assertTrue(false, "Text-only ChatMessage Codable should not throw: \(error)")
    }
}

func testPersistedAttachmentRef() {
    TestRunner.setGroup("PersistedAttachmentRef")

    let img = ImageAttachment(
        mediaType: .png,
        base64Data: "imagedata",
        width: 1920,
        height: 1080,
        fileSizeBytes: 500000,
        sourceFileName: "screenshot.png"
    )

    // Create from ImageAttachment
    let ref = PersistedAttachmentRef(from: img)
    TestRunner.assertEqual(ref.id, img.id, "Ref ID matches image ID")
    TestRunner.assertEqual(ref.type, "image", "Ref type is 'image'")
    TestRunner.assertEqual(ref.mediaType, "image/png", "Ref media type is raw value")
    TestRunner.assertEqual(ref.width, 1920, "Ref width matches")
    TestRunner.assertEqual(ref.height, 1080, "Ref height matches")
    TestRunner.assertEqual(ref.fileSizeBytes, 500000, "Ref file size matches")
    TestRunner.assertEqual(ref.sourceFileName, "screenshot.png", "Ref source file name matches")

    // Create from MessageAttachment
    let attachment = MessageAttachment.image(img)
    let ref2 = PersistedAttachmentRef.fromAttachment(attachment)
    TestRunner.assertEqual(ref2.id, img.id, "fromAttachment ref ID matches")
    TestRunner.assertEqual(ref2.type, "image", "fromAttachment ref type is 'image'")

    // Codable roundtrip
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    do {
        let data = try encoder.encode(ref)
        let decoded = try decoder.decode(PersistedAttachmentRef.self, from: data)
        TestRunner.assertEqual(decoded, ref, "PersistedAttachmentRef Codable roundtrip")
    } catch {
        TestRunner.assertTrue(false, "PersistedAttachmentRef Codable should not throw: \(error)")
    }
}

// MARK: - Main Entry Point

@main
struct MessageAttachmentTests {
    static func main() {
        print("")
        print("==================================================")
        print("MESSAGE ATTACHMENT TESTS")
        print("==================================================")

        testImageMediaType()
        testImageAttachment()
        testImageAttachmentCodable()
        testMessageAttachmentEnum()
        testChatMessageWithAttachments()
        testChatMessageCodableWithAttachments()
        testPersistedAttachmentRef()

        TestRunner.printSummary()

        if TestRunner.failedCount > 0 {
            exit(1)
        }
    }
}
