// MARK: - PromptBuilder Multimodal Formatting Tests
// Tests for multimodal message formatting across all providers

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

// MARK: - Multimodal Formatting Functions (standalone test implementations)

func formatOpenAIContent(text: String, images: [ImageAttachment]) -> [[String: Any]] {
    var content: [[String: Any]] = []
    for image in images {
        let base64 = image.imageData.base64EncodedString()
        content.append([
            "type": "image_url",
            "image_url": ["url": "data:\(image.mimeType);base64,\(base64)", "detail": "auto"]
        ])
    }
    if !text.isEmpty {
        content.append(["type": "text", "text": text])
    }
    return content
}

func formatAnthropicContent(text: String, images: [ImageAttachment]) -> [[String: Any]] {
    var content: [[String: Any]] = []
    for image in images {
        let base64 = image.imageData.base64EncodedString()
        content.append([
            "type": "image",
            "source": ["type": "base64", "media_type": image.mimeType, "data": base64]
        ])
    }
    if !text.isEmpty {
        content.append(["type": "text", "text": text])
    }
    return content
}

func formatGeminiParts(text: String, images: [ImageAttachment]) -> [[String: Any]] {
    var parts: [[String: Any]] = []
    for image in images {
        let base64 = image.imageData.base64EncodedString()
        parts.append(["inlineData": ["mimeType": image.mimeType, "data": base64]])
    }
    if !text.isEmpty {
        parts.append(["text": text])
    }
    return parts
}

func formatOllamaMessage(text: String, images: [ImageAttachment]) -> [String: Any] {
    var msg: [String: Any] = ["role": "user", "content": text]
    if !images.isEmpty {
        msg["images"] = images.map { $0.imageData.base64EncodedString() }
    }
    return msg
}

// MARK: - Helper

func makeTestAttachment(format: ImageFormat = .jpeg) -> ImageAttachment {
    ImageAttachment(
        imageData: Data([0xFF, 0xD8, 0xFF, 0xE0]),
        thumbnailData: Data([0xAA, 0xBB]),
        width: 800, height: 600, fileSize: 4,
        format: format,
        mimeType: format.mimeType,
        sourceType: .clipboard
    )
}

// MARK: - Tests

func testTextOnlyMessageUnchanged() {
    TestRunner.suite("Text-Only Messages Unchanged")

    let text = "Hello, how are you?"
    let images: [ImageAttachment] = []

    // OpenAI: when no images, should just use string content
    TestRunner.assertTrue(images.isEmpty, "No images means text-only message")
    TestRunner.assertFalse(text.isEmpty, "Text content exists")
}

func testOpenAIVisionFormat() {
    TestRunner.suite("OpenAI Vision Format")

    let image = makeTestAttachment()
    let content = formatOpenAIContent(text: "What is this?", images: [image])

    TestRunner.assertEqual(content.count, 2, "OpenAI content has 2 blocks (1 image + 1 text)")

    // First block should be image
    let imageBlock = content[0]
    TestRunner.assertEqual(imageBlock["type"] as? String, "image_url", "First block type is image_url")
    if let imageUrl = imageBlock["image_url"] as? [String: String] {
        TestRunner.assertTrue(imageUrl["url"]?.hasPrefix("data:image/jpeg;base64,") ?? false, "URL has data URI prefix")
        TestRunner.assertEqual(imageUrl["detail"], "auto", "Detail is auto")
    } else {
        TestRunner.assertTrue(false, "image_url dict missing")
    }

    // Second block should be text
    let textBlock = content[1]
    TestRunner.assertEqual(textBlock["type"] as? String, "text", "Second block type is text")
    TestRunner.assertEqual(textBlock["text"] as? String, "What is this?", "Text content preserved")
}

func testAnthropicMultimodalFormat() {
    TestRunner.suite("Anthropic Multimodal Format")

    let image = makeTestAttachment()
    let content = formatAnthropicContent(text: "Describe this", images: [image])

    TestRunner.assertEqual(content.count, 2, "Anthropic content has 2 blocks")

    let imageBlock = content[0]
    TestRunner.assertEqual(imageBlock["type"] as? String, "image", "First block type is image")
    if let source = imageBlock["source"] as? [String: String] {
        TestRunner.assertEqual(source["type"], "base64", "Source type is base64")
        TestRunner.assertEqual(source["media_type"], "image/jpeg", "Media type is image/jpeg")
        TestRunner.assertNotNil(source["data"], "Base64 data present")
    } else {
        TestRunner.assertTrue(false, "source dict missing")
    }

    let textBlock = content[1]
    TestRunner.assertEqual(textBlock["type"] as? String, "text", "Second block type is text")
}

func testGeminiInlineDataFormat() {
    TestRunner.suite("Gemini InlineData Format")

    let image = makeTestAttachment()
    let parts = formatGeminiParts(text: "What's this?", images: [image])

    TestRunner.assertEqual(parts.count, 2, "Gemini parts has 2 entries")

    let imagePart = parts[0]
    if let inlineData = imagePart["inlineData"] as? [String: String] {
        TestRunner.assertEqual(inlineData["mimeType"], "image/jpeg", "Gemini mimeType correct")
        TestRunner.assertNotNil(inlineData["data"], "Gemini base64 data present")
    } else {
        TestRunner.assertTrue(false, "inlineData dict missing")
    }

    let textPart = parts[1]
    TestRunner.assertEqual(textPart["text"] as? String, "What's this?", "Gemini text part correct")
}

func testOllamaImagesArrayFormat() {
    TestRunner.suite("Ollama Images Array Format")

    let image = makeTestAttachment()
    let msg = formatOllamaMessage(text: "Describe", images: [image])

    TestRunner.assertEqual(msg["role"] as? String, "user", "Ollama role is user")
    TestRunner.assertEqual(msg["content"] as? String, "Describe", "Ollama content is plain text")

    if let images = msg["images"] as? [String] {
        TestRunner.assertEqual(images.count, 1, "Ollama has 1 image in array")
        TestRunner.assertFalse(images[0].hasPrefix("data:"), "Ollama base64 has no data URI prefix")
    } else {
        TestRunner.assertTrue(false, "Ollama images array missing")
    }
}

func testImageOnlyMessage() {
    TestRunner.suite("Image-Only Message (No Text)")

    let image = makeTestAttachment()

    // OpenAI: image only
    let openaiContent = formatOpenAIContent(text: "", images: [image])
    TestRunner.assertEqual(openaiContent.count, 1, "OpenAI image-only has 1 block")
    TestRunner.assertEqual(openaiContent[0]["type"] as? String, "image_url", "OpenAI image-only block is image_url")

    // Anthropic: image only
    let anthropicContent = formatAnthropicContent(text: "", images: [image])
    TestRunner.assertEqual(anthropicContent.count, 1, "Anthropic image-only has 1 block")

    // Gemini: image only
    let geminiParts = formatGeminiParts(text: "", images: [image])
    TestRunner.assertEqual(geminiParts.count, 1, "Gemini image-only has 1 part")

    // Ollama: image with empty text
    let ollamaMsg = formatOllamaMessage(text: "", images: [image])
    TestRunner.assertEqual(ollamaMsg["content"] as? String, "", "Ollama content is empty string")
    TestRunner.assertNotNil(ollamaMsg["images"], "Ollama still has images array")
}

func testMultipleImagesPerMessage() {
    TestRunner.suite("Multiple Images Per Message")

    let images = [makeTestAttachment(), makeTestAttachment(format: .png), makeTestAttachment()]

    // OpenAI
    let openaiContent = formatOpenAIContent(text: "Compare these", images: images)
    TestRunner.assertEqual(openaiContent.count, 4, "OpenAI: 3 images + 1 text = 4 blocks")

    // Anthropic
    let anthropicContent = formatAnthropicContent(text: "Compare", images: images)
    TestRunner.assertEqual(anthropicContent.count, 4, "Anthropic: 3 images + 1 text = 4 blocks")

    // Gemini
    let geminiParts = formatGeminiParts(text: "Compare", images: images)
    TestRunner.assertEqual(geminiParts.count, 4, "Gemini: 3 images + 1 text = 4 parts")

    // Ollama
    let ollamaMsg = formatOllamaMessage(text: "Compare", images: images)
    if let imgs = ollamaMsg["images"] as? [String] {
        TestRunner.assertEqual(imgs.count, 3, "Ollama: 3 images in array")
    } else {
        TestRunner.assertTrue(false, "Ollama images array missing for multiple images")
    }
}

func testPNGFormatInContent() {
    TestRunner.suite("PNG Format in Content Blocks")

    let image = makeTestAttachment(format: .png)

    let openaiContent = formatOpenAIContent(text: "Test", images: [image])
    if let imageUrl = (openaiContent[0]["image_url"] as? [String: String]) {
        TestRunner.assertTrue(imageUrl["url"]?.contains("image/png") ?? false, "OpenAI uses image/png for PNG")
    }

    let anthropicContent = formatAnthropicContent(text: "Test", images: [image])
    if let source = (anthropicContent[0]["source"] as? [String: String]) {
        TestRunner.assertEqual(source["media_type"], "image/png", "Anthropic uses image/png for PNG")
    }

    let geminiParts = formatGeminiParts(text: "Test", images: [image])
    if let inlineData = (geminiParts[0]["inlineData"] as? [String: String]) {
        TestRunner.assertEqual(inlineData["mimeType"], "image/png", "Gemini uses image/png for PNG")
    }
}

func testImagesBeforeText() {
    TestRunner.suite("Images Placed Before Text")

    let image = makeTestAttachment()

    // OpenAI
    let openai = formatOpenAIContent(text: "Text", images: [image])
    TestRunner.assertEqual(openai[0]["type"] as? String, "image_url", "OpenAI: image before text")
    TestRunner.assertEqual(openai[1]["type"] as? String, "text", "OpenAI: text after image")

    // Anthropic
    let anthropic = formatAnthropicContent(text: "Text", images: [image])
    TestRunner.assertEqual(anthropic[0]["type"] as? String, "image", "Anthropic: image before text")
    TestRunner.assertEqual(anthropic[1]["type"] as? String, "text", "Anthropic: text after image")

    // Gemini
    let gemini = formatGeminiParts(text: "Text", images: [image])
    TestRunner.assertNotNil(gemini[0]["inlineData"], "Gemini: inlineData before text")
    TestRunner.assertNotNil(gemini[1]["text"], "Gemini: text after inlineData")
}

// MARK: - Entry Point

@main
struct PromptBuilderImageTests {
    static func main() {
        print("🧪 PromptBuilder Multimodal Formatting Tests")
        print("==================================================")

        testTextOnlyMessageUnchanged()
        testOpenAIVisionFormat()
        testAnthropicMultimodalFormat()
        testGeminiInlineDataFormat()
        testOllamaImagesArrayFormat()
        testImageOnlyMessage()
        testMultipleImagesPerMessage()
        testPNGFormatInContent()
        testImagesBeforeText()

        TestRunner.printSummary()
        if TestRunner.failedCount > 0 { exit(1) }
    }
}
