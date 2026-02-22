// MARK: - Model Capability Image Tests
// Tests for supportsImages in ModelCapabilities and LLMModel

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

// MARK: - Minimal Types (matching real definitions)

struct ModelCapabilities: Codable, Equatable, Hashable {
    let supportsTools: Bool
    let supportsImages: Bool

    init(supportsTools: Bool, supportsImages: Bool = false) {
        self.supportsTools = supportsTools
        self.supportsImages = supportsImages
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        supportsTools = try container.decode(Bool.self, forKey: .supportsTools)
        supportsImages = try container.decodeIfPresent(Bool.self, forKey: .supportsImages) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case supportsTools
        case supportsImages
    }

    static let `default` = ModelCapabilities(supportsTools: true, supportsImages: false)
    static let none = ModelCapabilities(supportsTools: false, supportsImages: false)
}

struct LLMModel: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let name: String
    let description: String
    let capabilities: ModelCapabilities?

    var supportsTools: Bool {
        capabilities?.supportsTools ?? true
    }

    var supportsImages: Bool {
        capabilities?.supportsImages ?? false
    }

    init(id: String, name: String, description: String, capabilities: ModelCapabilities? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.capabilities = capabilities
    }

    enum CodingKeys: String, CodingKey {
        case id, name, description, capabilities
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        capabilities = try container.decodeIfPresent(ModelCapabilities.self, forKey: .capabilities)
    }
}

// MARK: - Tests

func testModelCapabilitiesWithImages() {
    TestRunner.setGroup("ModelCapabilities with supportsImages")

    // Default capabilities (no images)
    let defaultCaps = ModelCapabilities.default
    TestRunner.assertTrue(defaultCaps.supportsTools, "Default supports tools")
    TestRunner.assertFalse(defaultCaps.supportsImages, "Default does not support images")

    // None capabilities
    let noneCaps = ModelCapabilities.none
    TestRunner.assertFalse(noneCaps.supportsTools, "None does not support tools")
    TestRunner.assertFalse(noneCaps.supportsImages, "None does not support images")

    // Explicit image support
    let visionCaps = ModelCapabilities(supportsTools: true, supportsImages: true)
    TestRunner.assertTrue(visionCaps.supportsTools, "Vision caps support tools")
    TestRunner.assertTrue(visionCaps.supportsImages, "Vision caps support images")

    // Tools only, no images
    let toolOnlyCaps = ModelCapabilities(supportsTools: true, supportsImages: false)
    TestRunner.assertTrue(toolOnlyCaps.supportsTools, "Tool-only caps support tools")
    TestRunner.assertFalse(toolOnlyCaps.supportsImages, "Tool-only caps do not support images")

    // Images only, no tools
    let imageOnlyCaps = ModelCapabilities(supportsTools: false, supportsImages: true)
    TestRunner.assertFalse(imageOnlyCaps.supportsTools, "Image-only caps do not support tools")
    TestRunner.assertTrue(imageOnlyCaps.supportsImages, "Image-only caps support images")

    // Equality
    TestRunner.assertTrue(visionCaps == ModelCapabilities(supportsTools: true, supportsImages: true), "Same values are equal")
    TestRunner.assertFalse(visionCaps == toolOnlyCaps, "Different supportsImages are not equal")
}

func testModelCapabilitiesCodableWithImages() {
    TestRunner.setGroup("ModelCapabilities Codable with supportsImages")

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    // Full roundtrip with both fields
    let original = ModelCapabilities(supportsTools: true, supportsImages: true)
    do {
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ModelCapabilities.self, from: data)
        TestRunner.assertTrue(decoded.supportsTools, "Roundtrip preserves supportsTools")
        TestRunner.assertTrue(decoded.supportsImages, "Roundtrip preserves supportsImages")
    } catch {
        TestRunner.assertTrue(false, "Full roundtrip should not throw: \(error)")
    }

    // Backward compat: decode JSON without supportsImages (defaults to false)
    let oldJson = """
    {"supportsTools": true}
    """.data(using: .utf8)!

    do {
        let decoded = try decoder.decode(ModelCapabilities.self, from: oldJson)
        TestRunner.assertTrue(decoded.supportsTools, "Old JSON: supportsTools is true")
        TestRunner.assertFalse(decoded.supportsImages, "Old JSON: supportsImages defaults to false")
    } catch {
        TestRunner.assertTrue(false, "Old JSON decoding should not throw: \(error)")
    }

    // JSON with supportsImages: true
    let newJson = """
    {"supportsTools": true, "supportsImages": true}
    """.data(using: .utf8)!

    do {
        let decoded = try decoder.decode(ModelCapabilities.self, from: newJson)
        TestRunner.assertTrue(decoded.supportsTools, "New JSON: supportsTools is true")
        TestRunner.assertTrue(decoded.supportsImages, "New JSON: supportsImages is true")
    } catch {
        TestRunner.assertTrue(false, "New JSON decoding should not throw: \(error)")
    }

    // JSON with supportsImages: false
    let noImagesJson = """
    {"supportsTools": false, "supportsImages": false}
    """.data(using: .utf8)!

    do {
        let decoded = try decoder.decode(ModelCapabilities.self, from: noImagesJson)
        TestRunner.assertFalse(decoded.supportsTools, "No-images JSON: supportsTools is false")
        TestRunner.assertFalse(decoded.supportsImages, "No-images JSON: supportsImages is false")
    } catch {
        TestRunner.assertTrue(false, "No-images JSON decoding should not throw: \(error)")
    }
}

func testLLMModelSupportsImages() {
    TestRunner.setGroup("LLMModel supportsImages Computed Property")

    // Model with image support
    let visionModel = LLMModel(
        id: "gpt-4o",
        name: "GPT-4o",
        description: "Vision model",
        capabilities: ModelCapabilities(supportsTools: true, supportsImages: true)
    )
    TestRunner.assertTrue(visionModel.supportsImages, "Vision model supports images")
    TestRunner.assertTrue(visionModel.supportsTools, "Vision model supports tools")

    // Model without image support
    let textModel = LLMModel(
        id: "gpt-4",
        name: "GPT-4",
        description: "Text-only model",
        capabilities: ModelCapabilities(supportsTools: true, supportsImages: false)
    )
    TestRunner.assertFalse(textModel.supportsImages, "Text model does not support images")
    TestRunner.assertTrue(textModel.supportsTools, "Text model supports tools")

    // Model with nil capabilities (defaults)
    let nilCapModel = LLMModel(
        id: "unknown",
        name: "Unknown",
        description: "No caps"
    )
    TestRunner.assertFalse(nilCapModel.supportsImages, "Nil-caps model defaults to no image support")
    TestRunner.assertTrue(nilCapModel.supportsTools, "Nil-caps model defaults to tool support")
}

func testLLMModelCodableWithImages() {
    TestRunner.setGroup("LLMModel Codable with Image Capabilities")

    let decoder = JSONDecoder()

    // Old format (no supportsImages in capabilities)
    let oldModelJson = """
    {"id": "old-model", "name": "Old Model", "description": "Legacy", "capabilities": {"supportsTools": true}}
    """.data(using: .utf8)!

    do {
        let decoded = try decoder.decode(LLMModel.self, from: oldModelJson)
        TestRunner.assertEqual(decoded.id, "old-model", "Old model ID decoded")
        TestRunner.assertTrue(decoded.supportsTools, "Old model supportsTools")
        TestRunner.assertFalse(decoded.supportsImages, "Old model supportsImages defaults to false")
    } catch {
        TestRunner.assertTrue(false, "Old model format should decode: \(error)")
    }

    // New format with supportsImages
    let newModelJson = """
    {"id": "gpt-4o", "name": "GPT-4o", "description": "Vision", "capabilities": {"supportsTools": true, "supportsImages": true}}
    """.data(using: .utf8)!

    do {
        let decoded = try decoder.decode(LLMModel.self, from: newModelJson)
        TestRunner.assertEqual(decoded.id, "gpt-4o", "New model ID decoded")
        TestRunner.assertTrue(decoded.supportsTools, "New model supportsTools")
        TestRunner.assertTrue(decoded.supportsImages, "New model supportsImages is true")
    } catch {
        TestRunner.assertTrue(false, "New model format should decode: \(error)")
    }

    // No capabilities at all
    let noCapsJson = """
    {"id": "bare", "name": "Bare Model", "description": "None"}
    """.data(using: .utf8)!

    do {
        let decoded = try decoder.decode(LLMModel.self, from: noCapsJson)
        TestRunner.assertNil(decoded.capabilities, "No-caps model has nil capabilities")
        TestRunner.assertFalse(decoded.supportsImages, "No-caps model defaults to no images")
        TestRunner.assertTrue(decoded.supportsTools, "No-caps model defaults to tools")
    } catch {
        TestRunner.assertTrue(false, "No-caps format should decode: \(error)")
    }
}

func testModelsJsonWithImageCapabilities() {
    TestRunner.setGroup("models.json v3 with Image Capabilities")

    let jsonV3 = """
    {
        "version": 3,
        "providers": {
            "openai": {
                "models": [
                    {"id": "gpt-4o", "name": "GPT-4o", "description": "Vision", "capabilities": {"supportsTools": true, "supportsImages": true}},
                    {"id": "gpt-4", "name": "GPT-4", "description": "Text only", "capabilities": {"supportsTools": true, "supportsImages": false}}
                ],
                "default": "gpt-4o"
            },
            "anthropic": {
                "models": [
                    {"id": "claude-3-5-sonnet", "name": "Claude 3.5 Sonnet", "description": "Fast", "capabilities": {"supportsTools": true, "supportsImages": true}}
                ],
                "default": "claude-3-5-sonnet"
            },
            "gemini": {
                "models": [
                    {"id": "gemini-2.0-flash", "name": "Gemini 2.0 Flash", "description": "Fast", "capabilities": {"supportsTools": true, "supportsImages": true}}
                ],
                "default": "gemini-2.0-flash"
            }
        }
    }
    """.data(using: .utf8)!

    struct ProviderConfig: Codable {
        let models: [LLMModel]
        let defaultModelId: String
        enum CodingKeys: String, CodingKey {
            case models
            case defaultModelId = "default"
        }
    }

    struct ModelsConfig: Codable {
        let version: Int
        let providers: [String: ProviderConfig]
    }

    do {
        let config = try JSONDecoder().decode(ModelsConfig.self, from: jsonV3)
        TestRunner.assertEqual(config.version, 3, "Config version is 3")

        // OpenAI
        let openai = config.providers["openai"]!
        TestRunner.assertTrue(openai.models[0].supportsImages, "GPT-4o supports images")
        TestRunner.assertFalse(openai.models[1].supportsImages, "GPT-4 does not support images")

        // Anthropic
        let anthropic = config.providers["anthropic"]!
        TestRunner.assertTrue(anthropic.models[0].supportsImages, "Claude supports images")

        // Gemini
        let gemini = config.providers["gemini"]!
        TestRunner.assertTrue(gemini.models[0].supportsImages, "Gemini supports images")

    } catch {
        TestRunner.assertTrue(false, "v3 models.json should parse: \(error)")
    }
}

// MARK: - Main Entry Point

@main
struct ModelCapabilityImageTests {
    static func main() {
        print("")
        print("==================================================")
        print("MODEL CAPABILITY IMAGE TESTS")
        print("==================================================")

        testModelCapabilitiesWithImages()
        testModelCapabilitiesCodableWithImages()
        testLLMModelSupportsImages()
        testLLMModelCodableWithImages()
        testModelsJsonWithImageCapabilities()

        TestRunner.printSummary()

        if TestRunner.failedCount > 0 {
            exit(1)
        }
    }
}
