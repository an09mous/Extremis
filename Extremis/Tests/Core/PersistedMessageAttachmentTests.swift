// MARK: - Persisted Message Attachment Tests
// Tests for PersistedAttachmentRef Codable and backward compatibility

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

// MARK: - Minimal Types for Standalone Compilation

enum ImageMediaType: String, Codable, Equatable, Hashable {
    case jpeg = "image/jpeg"
    case png = "image/png"
    case gif = "image/gif"
    case webp = "image/webp"
}

struct ImageAttachment: Codable, Equatable, Identifiable, Hashable {
    let id: UUID
    let mediaType: ImageMediaType
    let base64Data: String
    let width: Int?
    let height: Int?
    let fileSizeBytes: Int?
    let sourceFileName: String?

    init(id: UUID = UUID(), mediaType: ImageMediaType, base64Data: String,
         width: Int? = nil, height: Int? = nil, fileSizeBytes: Int? = nil, sourceFileName: String? = nil) {
        self.id = id; self.mediaType = mediaType; self.base64Data = base64Data
        self.width = width; self.height = height; self.fileSizeBytes = fileSizeBytes; self.sourceFileName = sourceFileName
    }
}

enum MessageAttachment: Codable, Equatable, Identifiable {
    case image(ImageAttachment)
    var id: UUID { switch self { case .image(let img): return img.id } }

    private enum CodingKeys: String, CodingKey { case type, payload }
    private enum AttachmentType: String, Codable { case image }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .image(let a):
            try container.encode(AttachmentType.image, forKey: .type)
            try container.encode(a, forKey: .payload)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(AttachmentType.self, forKey: .type)
        switch type {
        case .image: self = .image(try container.decode(ImageAttachment.self, forKey: .payload))
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
        case .image(let img): return PersistedAttachmentRef(from: img)
        }
    }
}

/// Simulated PersistedMessage with optional attachment refs (mirrors real structure)
struct PersistedMessage: Codable, Equatable {
    let id: UUID
    let role: String
    let content: String
    let timestamp: Date
    let attachmentRefsData: Data?

    init(id: UUID = UUID(), role: String, content: String, timestamp: Date = Date(),
         attachments: [MessageAttachment]? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp

        // Convert attachments to refs (lightweight persistence)
        if let attachments = attachments, !attachments.isEmpty {
            let refs = attachments.map { PersistedAttachmentRef.fromAttachment($0) }
            self.attachmentRefsData = try? JSONEncoder().encode(refs)
        } else {
            self.attachmentRefsData = nil
        }
    }

    /// Decode attachment refs from stored data
    func attachmentRefs() -> [PersistedAttachmentRef] {
        guard let data = attachmentRefsData else { return [] }
        return (try? JSONDecoder().decode([PersistedAttachmentRef].self, from: data)) ?? []
    }
}

// MARK: - Tests

func testPersistedAttachmentRefCodableRoundtrip() {
    TestRunner.setGroup("PersistedAttachmentRef Codable Roundtrip")

    let img = ImageAttachment(
        mediaType: .jpeg,
        base64Data: "imagedata",
        width: 1920,
        height: 1080,
        fileSizeBytes: 500000,
        sourceFileName: "photo.jpg"
    )

    let ref = PersistedAttachmentRef(from: img)
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    do {
        let data = try encoder.encode(ref)
        let decoded = try decoder.decode(PersistedAttachmentRef.self, from: data)
        TestRunner.assertEqual(decoded.id, ref.id, "ID roundtrip")
        TestRunner.assertEqual(decoded.type, "image", "Type roundtrip")
        TestRunner.assertEqual(decoded.mediaType, "image/jpeg", "Media type roundtrip")
        TestRunner.assertEqual(decoded.width, 1920, "Width roundtrip")
        TestRunner.assertEqual(decoded.height, 1080, "Height roundtrip")
        TestRunner.assertEqual(decoded.fileSizeBytes, 500000, "File size roundtrip")
        TestRunner.assertEqual(decoded.sourceFileName, "photo.jpg", "Source file name roundtrip")
    } catch {
        TestRunner.assertTrue(false, "Roundtrip should not throw: \(error)")
    }

    // Array roundtrip
    let ref2 = PersistedAttachmentRef(from: ImageAttachment(mediaType: .png, base64Data: "x", width: 100, height: 200))
    let refs = [ref, ref2]

    do {
        let data = try encoder.encode(refs)
        let decoded = try decoder.decode([PersistedAttachmentRef].self, from: data)
        TestRunner.assertEqual(decoded.count, 2, "Array roundtrip preserves count")
        TestRunner.assertEqual(decoded[0].id, ref.id, "Array roundtrip preserves first ref")
        TestRunner.assertEqual(decoded[1].id, ref2.id, "Array roundtrip preserves second ref")
    } catch {
        TestRunner.assertTrue(false, "Array roundtrip should not throw: \(error)")
    }
}

func testPersistedAttachmentRefMinimalFields() {
    TestRunner.setGroup("PersistedAttachmentRef Minimal Fields")

    // Image with no optional metadata
    let img = ImageAttachment(mediaType: .gif, base64Data: "data")
    let ref = PersistedAttachmentRef(from: img)

    TestRunner.assertEqual(ref.type, "image", "Type is image")
    TestRunner.assertEqual(ref.mediaType, "image/gif", "Media type is gif")
    TestRunner.assertNil(ref.width, "Width is nil")
    TestRunner.assertNil(ref.height, "Height is nil")
    TestRunner.assertNil(ref.fileSizeBytes, "File size is nil")
    TestRunner.assertNil(ref.sourceFileName, "Source file name is nil")

    // Codable roundtrip still works with nil fields
    do {
        let data = try JSONEncoder().encode(ref)
        let decoded = try JSONDecoder().decode(PersistedAttachmentRef.self, from: data)
        TestRunner.assertEqual(decoded, ref, "Minimal ref Codable roundtrip")
    } catch {
        TestRunner.assertTrue(false, "Minimal ref roundtrip should not throw: \(error)")
    }
}

func testPersistedMessageWithAttachments() {
    TestRunner.setGroup("PersistedMessage with Attachments")

    let img1 = ImageAttachment(mediaType: .jpeg, base64Data: "a", width: 640, height: 480)
    let img2 = ImageAttachment(mediaType: .png, base64Data: "b", width: 800, height: 600)
    let attachments: [MessageAttachment] = [.image(img1), .image(img2)]

    let message = PersistedMessage(role: "user", content: "Look at these", attachments: attachments)

    // Check refs are created
    let refs = message.attachmentRefs()
    TestRunner.assertEqual(refs.count, 2, "Message has 2 attachment refs")
    TestRunner.assertEqual(refs[0].id, img1.id, "First ref ID matches first image")
    TestRunner.assertEqual(refs[1].id, img2.id, "Second ref ID matches second image")
    TestRunner.assertEqual(refs[0].mediaType, "image/jpeg", "First ref media type is JPEG")
    TestRunner.assertEqual(refs[1].mediaType, "image/png", "Second ref media type is PNG")

    // Base64 data is NOT stored in refs (file-based storage)
    // Refs only store metadata
    TestRunner.assertNotNil(message.attachmentRefsData, "Attachment refs data is stored")
}

func testPersistedMessageWithoutAttachments() {
    TestRunner.setGroup("PersistedMessage without Attachments (Backward Compat)")

    // No attachments at all
    let message1 = PersistedMessage(role: "user", content: "Just text")
    TestRunner.assertNil(message1.attachmentRefsData, "No attachments -> nil refs data")
    TestRunner.assertTrue(message1.attachmentRefs().isEmpty, "No attachments -> empty refs")

    // Nil attachments
    let message2 = PersistedMessage(role: "assistant", content: "Reply", attachments: nil)
    TestRunner.assertNil(message2.attachmentRefsData, "Nil attachments -> nil refs data")
    TestRunner.assertTrue(message2.attachmentRefs().isEmpty, "Nil attachments -> empty refs")

    // Empty attachments array
    let message3 = PersistedMessage(role: "user", content: "Hi", attachments: [])
    TestRunner.assertNil(message3.attachmentRefsData, "Empty attachments -> nil refs data")
    TestRunner.assertTrue(message3.attachmentRefs().isEmpty, "Empty attachments -> empty refs")
}

func testPersistedMessageCodableRoundtrip() {
    TestRunner.setGroup("PersistedMessage Codable Roundtrip")

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    // With attachments
    let img = ImageAttachment(mediaType: .jpeg, base64Data: "test", width: 320, height: 240)
    let withAttachments = PersistedMessage(role: "user", content: "Image!", attachments: [.image(img)])

    do {
        let data = try encoder.encode(withAttachments)
        let decoded = try decoder.decode(PersistedMessage.self, from: data)
        TestRunner.assertEqual(decoded.id, withAttachments.id, "Roundtrip preserves message ID")
        TestRunner.assertEqual(decoded.role, "user", "Roundtrip preserves role")
        TestRunner.assertEqual(decoded.content, "Image!", "Roundtrip preserves content")

        let refs = decoded.attachmentRefs()
        TestRunner.assertEqual(refs.count, 1, "Roundtrip preserves attachment count")
        TestRunner.assertEqual(refs[0].id, img.id, "Roundtrip preserves attachment ref ID")
    } catch {
        TestRunner.assertTrue(false, "Roundtrip with attachments should not throw: \(error)")
    }

    // Without attachments
    let textOnly = PersistedMessage(role: "assistant", content: "Response")

    do {
        let data = try encoder.encode(textOnly)
        let decoded = try decoder.decode(PersistedMessage.self, from: data)
        TestRunner.assertEqual(decoded.content, "Response", "Text-only roundtrip preserves content")
        TestRunner.assertNil(decoded.attachmentRefsData, "Text-only roundtrip has nil refs")
    } catch {
        TestRunner.assertTrue(false, "Text-only roundtrip should not throw: \(error)")
    }
}

func testPersistedMessageBackwardCompatDecoding() {
    TestRunner.setGroup("PersistedMessage Backward Compat Decoding")

    // Simulate old JSON without attachmentRefsData field
    let oldJson = """
    {
        "id": "550E8400-E29B-41D4-A716-446655440000",
        "role": "user",
        "content": "Old message",
        "timestamp": 1000000
    }
    """.data(using: .utf8)!

    do {
        let decoded = try JSONDecoder().decode(PersistedMessage.self, from: oldJson)
        TestRunner.assertEqual(decoded.content, "Old message", "Old format decodes content")
        TestRunner.assertNil(decoded.attachmentRefsData, "Old format has nil attachment refs")
        TestRunner.assertTrue(decoded.attachmentRefs().isEmpty, "Old format has empty refs")
    } catch {
        TestRunner.assertTrue(false, "Decoding old format should not throw: \(error)")
    }
}

// MARK: - Main Entry Point

@main
struct PersistedMessageAttachmentTests {
    static func main() {
        print("")
        print("==================================================")
        print("PERSISTED MESSAGE ATTACHMENT TESTS")
        print("==================================================")

        testPersistedAttachmentRefCodableRoundtrip()
        testPersistedAttachmentRefMinimalFields()
        testPersistedMessageWithAttachments()
        testPersistedMessageWithoutAttachments()
        testPersistedMessageCodableRoundtrip()
        testPersistedMessageBackwardCompatDecoding()

        TestRunner.printSummary()

        if TestRunner.failedCount > 0 {
            exit(1)
        }
    }
}
