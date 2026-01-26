// MARK: - Model Capability Tests
// Tests for ModelCapabilities struct and LLMModel tool support detection

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

// MARK: - Model Types (Minimal definitions for testing)

/// Model capabilities - extensible for future features
struct ModelCapabilities: Codable, Equatable, Hashable {
    let supportsTools: Bool

    static let `default` = ModelCapabilities(supportsTools: true)
    static let none = ModelCapabilities(supportsTools: false)
}

/// LLM Model with capabilities
struct LLMModel: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let name: String
    let description: String
    let capabilities: ModelCapabilities?

    var supportsTools: Bool {
        capabilities?.supportsTools ?? true
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

func testModelCapabilitiesStruct() {
    TestRunner.setGroup("ModelCapabilities Struct")

    // Test default capabilities
    let defaultCaps = ModelCapabilities.default
    TestRunner.assertTrue(defaultCaps.supportsTools, "Default capabilities should support tools")

    // Test none capabilities
    let noneCaps = ModelCapabilities.none
    TestRunner.assertFalse(noneCaps.supportsTools, "None capabilities should not support tools")

    // Test custom capabilities
    let customCaps = ModelCapabilities(supportsTools: true)
    TestRunner.assertTrue(customCaps.supportsTools, "Custom capabilities with true should support tools")

    let customNoCaps = ModelCapabilities(supportsTools: false)
    TestRunner.assertFalse(customNoCaps.supportsTools, "Custom capabilities with false should not support tools")

    // Test equality
    TestRunner.assertTrue(defaultCaps == customCaps, "Capabilities with same values should be equal")
    TestRunner.assertFalse(defaultCaps == noneCaps, "Different capabilities should not be equal")
}

func testLLMModelWithCapabilities() {
    TestRunner.setGroup("LLMModel with Capabilities")

    // Test model with explicit tool support
    let toolModel = LLMModel(
        id: "gpt-4o",
        name: "GPT-4o",
        description: "Test model",
        capabilities: ModelCapabilities(supportsTools: true)
    )
    TestRunner.assertTrue(toolModel.supportsTools, "Model with tool capability should support tools")

    // Test model without tool support
    let noToolModel = LLMModel(
        id: "phi",
        name: "Phi",
        description: "Small model",
        capabilities: ModelCapabilities(supportsTools: false)
    )
    TestRunner.assertFalse(noToolModel.supportsTools, "Model without tool capability should not support tools")

    // Test model with nil capabilities (should default to true)
    let nilCapModel = LLMModel(
        id: "unknown",
        name: "Unknown Model",
        description: "Unknown"
    )
    TestRunner.assertTrue(nilCapModel.supportsTools, "Model with nil capabilities should default to supporting tools")
}

func testLLMModelCodable() {
    TestRunner.setGroup("LLMModel Codable")

    // Test encoding and decoding with capabilities
    let original = LLMModel(
        id: "test-model",
        name: "Test Model",
        description: "A test",
        capabilities: ModelCapabilities(supportsTools: true)
    )

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    do {
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(LLMModel.self, from: data)

        TestRunner.assertEqual(decoded.id, original.id, "Decoded model id should match")
        TestRunner.assertEqual(decoded.name, original.name, "Decoded model name should match")
        TestRunner.assertEqual(decoded.supportsTools, original.supportsTools, "Decoded model supportsTools should match")
        TestRunner.assertNotNil(decoded.capabilities, "Decoded model should have capabilities")
    } catch {
        TestRunner.assertTrue(false, "Encoding/decoding should not throw: \(error)")
    }

    // Test decoding without capabilities field (backward compatibility)
    let jsonWithoutCaps = """
    {"id": "old-model", "name": "Old Model", "description": "No caps"}
    """.data(using: .utf8)!

    do {
        let decoded = try decoder.decode(LLMModel.self, from: jsonWithoutCaps)
        TestRunner.assertEqual(decoded.id, "old-model", "Should decode model without capabilities")
        TestRunner.assertNil(decoded.capabilities, "Capabilities should be nil when not in JSON")
        TestRunner.assertTrue(decoded.supportsTools, "Model without capabilities should default to supporting tools")
    } catch {
        TestRunner.assertTrue(false, "Decoding model without capabilities should not throw: \(error)")
    }

    // Test decoding with capabilities
    let jsonWithCaps = """
    {"id": "new-model", "name": "New Model", "description": "With caps", "capabilities": {"supportsTools": false}}
    """.data(using: .utf8)!

    do {
        let decoded = try decoder.decode(LLMModel.self, from: jsonWithCaps)
        TestRunner.assertEqual(decoded.id, "new-model", "Should decode model with capabilities")
        TestRunner.assertNotNil(decoded.capabilities, "Capabilities should be present")
        TestRunner.assertFalse(decoded.supportsTools, "Model with supportsTools=false should not support tools")
    } catch {
        TestRunner.assertTrue(false, "Decoding model with capabilities should not throw: \(error)")
    }
}

func testModelsJsonFormat() {
    TestRunner.setGroup("models.json Format Validation")

    // Simulate parsing models from JSON (like ModelConfigLoader does)
    let sampleJson = """
    {
        "version": 2,
        "providers": {
            "openai": {
                "models": [
                    {"id": "gpt-4o", "name": "GPT-4o", "description": "Most capable", "capabilities": {"supportsTools": true}},
                    {"id": "gpt-4o-mini", "name": "GPT-4o Mini", "description": "Fast", "capabilities": {"supportsTools": true}}
                ],
                "default": "gpt-4o"
            },
            "anthropic": {
                "models": [
                    {"id": "claude-3-opus", "name": "Claude 3 Opus", "description": "Premium", "capabilities": {"supportsTools": true}}
                ],
                "default": "claude-3-opus"
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
        let config = try JSONDecoder().decode(ModelsConfig.self, from: sampleJson)

        TestRunner.assertEqual(config.version, 2, "Config version should be 2")

        // Check OpenAI models
        let openai = config.providers["openai"]!
        TestRunner.assertEqual(openai.models.count, 2, "OpenAI should have 2 models")
        TestRunner.assertTrue(openai.models[0].supportsTools, "GPT-4o should support tools")
        TestRunner.assertTrue(openai.models[1].supportsTools, "GPT-4o-mini should support tools")

        // Check Anthropic models
        let anthropic = config.providers["anthropic"]!
        TestRunner.assertEqual(anthropic.models.count, 1, "Anthropic should have 1 model")
        TestRunner.assertTrue(anthropic.models[0].supportsTools, "Claude should support tools")

    } catch {
        TestRunner.assertTrue(false, "Parsing models.json format should not throw: \(error)")
    }
}

func testToolCapabilityErrorDetection() {
    TestRunner.setGroup("Tool Capability Error Detection")

    // Test patterns that indicate tool capability issues
    let toolErrorPatterns = [
        "tools are not supported",
        "function calling not available",
        "unsupported parameter: tools",
        "This model does not support tool use"
    ]

    for pattern in toolErrorPatterns {
        let lowercased = pattern.lowercased()
        let isToolError = lowercased.contains("tool") ||
                          lowercased.contains("function") ||
                          lowercased.contains("unsupported") ||
                          lowercased.contains("not support")
        TestRunner.assertTrue(isToolError, "Should detect tool error in: '\(pattern)'")
    }

    // Test patterns that should NOT be detected as tool errors
    let nonToolErrors = [
        "rate limit exceeded",
        "invalid api key",
        "server error 500"
    ]

    for pattern in nonToolErrors {
        let lowercased = pattern.lowercased()
        let isToolError = lowercased.contains("tool") ||
                          lowercased.contains("function") ||
                          lowercased.contains("not support")
        TestRunner.assertFalse(isToolError, "Should NOT detect tool error in: '\(pattern)'")
    }
}

// MARK: - Main Entry Point

@main
struct ModelCapabilityTests {
    static func main() {
        print("")
        print("==================================================")
        print("MODEL CAPABILITY TESTS")
        print("==================================================")

        testModelCapabilitiesStruct()
        testLLMModelWithCapabilities()
        testLLMModelCodable()
        testModelsJsonFormat()
        testToolCapabilityErrorDetection()

        TestRunner.printSummary()

        if TestRunner.failedCount > 0 {
            exit(1)
        }
    }
}
