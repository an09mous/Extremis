// MARK: - ModelConfigLoader Unit Tests
// Tests for JSON-based model configuration loading
// This is a standalone test file that can be compiled and run independently

import Foundation

// MARK: - Test Infrastructure (Self-contained)

/// Lightweight test runner for standalone tests
struct TestRunner {
    static var passedCount = 0
    static var failedCount = 0
    static var failedTests: [(String, String)] = []

    static func assertTrue(_ condition: Bool, _ name: String) {
        if condition {
            passedCount += 1
            print("  ✓ \(name)")
        } else {
            failedCount += 1
            failedTests.append((name, "Expected true, got false"))
            print("  ✗ \(name)")
        }
    }

    static func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ name: String) {
        if actual == expected {
            passedCount += 1
            print("  ✓ \(name)")
        } else {
            failedCount += 1
            failedTests.append((name, "Expected \(expected), got \(actual)"))
            print("  ✗ \(name) - Expected \(expected), got \(actual)")
        }
    }

    static func printSummary() {
        print("\n" + String(repeating: "=", count: 50))
        print("TEST SUMMARY")
        print(String(repeating: "=", count: 50))
        print("Passed: \(passedCount)")
        print("Failed: \(failedCount)")
        print("Total:  \(passedCount + failedCount)")

        if !failedTests.isEmpty {
            print("\nFailed Tests:")
            for (name, message) in failedTests {
                print("  • \(name): \(message)")
            }
        }
        print(String(repeating: "=", count: 50))
    }

    static func reset() {
        passedCount = 0
        failedCount = 0
        failedTests = []
    }
}

// MARK: - Types (Copied for standalone compilation)

/// LLM Model representation
struct LLMModel: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let description: String
}

/// Provider types - uses capitalized rawValue (like production code)
/// ModelConfigLoader does case-insensitive lookup so JSON can use lowercase
enum LLMProviderType: String, CaseIterable {
    case openai = "OpenAI"
    case anthropic = "Anthropic"
    case gemini = "Gemini"
    case ollama = "Ollama"
}

/// Configuration models
struct ModelConfig: Codable {
    let version: Int
    let providers: [String: ProviderModelConfig]
}

struct ProviderModelConfig: Codable {
    let models: [LLMModel]
    let defaultModelId: String

    enum CodingKeys: String, CodingKey {
        case models
        case defaultModelId = "default"
    }
}

/// Error types
enum ModelConfigError: Error {
    case configNotFound
    case loadingFailed(underlying: Error)
    case decodingFailed(underlying: Error)
}

/// ModelConfigLoader (copied for standalone testing)
final class ModelConfigLoader {
    static let shared = ModelConfigLoader()

    private var config: ModelConfig?
    private let cacheLock = NSLock()

    func models(for provider: LLMProviderType) -> [LLMModel] {
        guard provider != .ollama else { return [] }
        do {
            let config = try loadConfig()
            // Case-insensitive lookup
            let providerKey = provider.rawValue
            let providerConfig = config.providers[providerKey]
                ?? config.providers[providerKey.lowercased()]
                ?? config.providers.first { $0.key.lowercased() == providerKey.lowercased() }?.value
            return providerConfig?.models ?? []
        } catch {
            return []
        }
    }

    func defaultModel(for provider: LLMProviderType) -> LLMModel? {
        guard provider != .ollama else { return nil }
        do {
            let config = try loadConfig()
            // Case-insensitive lookup
            let providerKey = provider.rawValue
            let providerConfig = config.providers[providerKey]
                ?? config.providers[providerKey.lowercased()]
                ?? config.providers.first { $0.key.lowercased() == providerKey.lowercased() }?.value
            guard let pConfig = providerConfig else { return nil }
            return pConfig.models.first { $0.id == pConfig.defaultModelId }
                ?? pConfig.models.first
        } catch {
            return nil
        }
    }

    func clearCache() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        config = nil
    }

    private func loadConfig() throws -> ModelConfig {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        if let cached = config {
            return cached
        }

        let loaded = try loadFromFile()
        config = loaded
        return loaded
    }

    private func loadFromFile() throws -> ModelConfig {
        // For testing, look for models.json relative to current directory
        let possiblePaths = [
            "Resources/models.json",
            "../Resources/models.json",
            "../../Resources/models.json",
            "./models.json"
        ]

        var configURL: URL? = nil
        let fileManager = FileManager.default
        let currentDir = fileManager.currentDirectoryPath

        for path in possiblePaths {
            let fullPath = (currentDir as NSString).appendingPathComponent(path)
            if fileManager.fileExists(atPath: fullPath) {
                configURL = URL(fileURLWithPath: fullPath)
                break
            }
        }

        guard let url = configURL else {
            throw ModelConfigError.configNotFound
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ModelConfig.self, from: data)
    }
}

// MARK: - Test Suite

struct ModelConfigLoaderTests {

    static func runAll() {
        print("\n📦 ModelConfigLoader Tests")
        print(String(repeating: "-", count: 40))

        testLoadOpenAIModels()
        testLoadAnthropicModels()
        testLoadGeminiModels()
        testOllamaReturnsEmpty()
        testDefaultModelExistsForOpenAI()
        testDefaultModelExistsForAnthropic()
        testDefaultModelExistsForGemini()
        testDefaultModelInModelsList()
        testModelHasRequiredFields()
        testCachingReturnsSameResults()
        testClearCacheWorks()
        testMultipleModelsPerProvider()

        print("\n📦 JSON Loading Validation Tests")
        print(String(repeating: "-", count: 40))

        testOpenAIExactModels()
        testAnthropicExactModels()
        testGeminiExactModels()
        testOpenAIDefaultModel()
        testAnthropicDefaultModel()
        testGeminiDefaultModel()
        testAllModelsHaveValidIds()
        testAllModelsHaveValidNames()
        testAllModelsHaveValidDescriptions()
        testNoEmptyModelLists()
        testModelIdUniquenessPerProvider()
    }

    static func testLoadOpenAIModels() {
        let models = ModelConfigLoader.shared.models(for: .openai)
        TestRunner.assertTrue(!models.isEmpty, "OpenAI: Has models")
        TestRunner.assertTrue(models.contains { $0.id == "gpt-4o" }, "OpenAI: Contains gpt-4o")
    }

    static func testLoadAnthropicModels() {
        let models = ModelConfigLoader.shared.models(for: .anthropic)
        TestRunner.assertTrue(!models.isEmpty, "Anthropic: Has models")
        TestRunner.assertTrue(models.contains { $0.id.contains("claude") }, "Anthropic: Contains claude")
    }

    static func testLoadGeminiModels() {
        let models = ModelConfigLoader.shared.models(for: .gemini)
        TestRunner.assertTrue(!models.isEmpty, "Gemini: Has models")
        TestRunner.assertTrue(models.contains { $0.id.contains("gemini") }, "Gemini: Contains gemini")
    }

    static func testOllamaReturnsEmpty() {
        let models = ModelConfigLoader.shared.models(for: .ollama)
        TestRunner.assertTrue(models.isEmpty, "Ollama: Returns empty (uses API)")
    }

    static func testDefaultModelExistsForOpenAI() {
        let defaultModel = ModelConfigLoader.shared.defaultModel(for: .openai)
        TestRunner.assertTrue(defaultModel != nil, "OpenAI: Has default model")
        if let model = defaultModel {
            TestRunner.assertEqual(model.id, "gpt-4o", "OpenAI: Default is gpt-4o")
        }
    }

    static func testDefaultModelExistsForAnthropic() {
        let defaultModel = ModelConfigLoader.shared.defaultModel(for: .anthropic)
        TestRunner.assertTrue(defaultModel != nil, "Anthropic: Has default model")
    }

    static func testDefaultModelExistsForGemini() {
        let defaultModel = ModelConfigLoader.shared.defaultModel(for: .gemini)
        TestRunner.assertTrue(defaultModel != nil, "Gemini: Has default model")
    }

    static func testDefaultModelInModelsList() {
        for provider in [LLMProviderType.openai, .anthropic, .gemini] {
            let models = ModelConfigLoader.shared.models(for: provider)
            let defaultModel = ModelConfigLoader.shared.defaultModel(for: provider)
            if let def = defaultModel {
                let found = models.contains { $0.id == def.id }
                TestRunner.assertTrue(found, "\(provider.rawValue): Default in list")
            }
        }
    }

    static func testModelHasRequiredFields() {
        let models = ModelConfigLoader.shared.models(for: .openai)
        if let model = models.first {
            TestRunner.assertTrue(!model.id.isEmpty, "Model: Has id")
            TestRunner.assertTrue(!model.name.isEmpty, "Model: Has name")
            TestRunner.assertTrue(!model.description.isEmpty, "Model: Has description")
        }
    }

    static func testCachingReturnsSameResults() {
        let models1 = ModelConfigLoader.shared.models(for: .openai)
        let models2 = ModelConfigLoader.shared.models(for: .openai)
        TestRunner.assertEqual(models1.count, models2.count, "Caching: Same count")
    }

    static func testClearCacheWorks() {
        _ = ModelConfigLoader.shared.models(for: .openai)
        ModelConfigLoader.shared.clearCache()
        let modelsAfterClear = ModelConfigLoader.shared.models(for: .openai)
        TestRunner.assertTrue(!modelsAfterClear.isEmpty, "ClearCache: Can reload")
    }

    static func testMultipleModelsPerProvider() {
        for provider in [LLMProviderType.openai, .anthropic, .gemini] {
            let models = ModelConfigLoader.shared.models(for: provider)
            TestRunner.assertTrue(models.count >= 2, "\(provider.rawValue): Multiple models")
        }
    }

    // MARK: - JSON Loading Validation Tests

    static func testOpenAIExactModels() {
        let models = ModelConfigLoader.shared.models(for: .openai)
        let expectedIds = ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "gpt-4"]
        TestRunner.assertEqual(models.count, expectedIds.count, "OpenAI: Exact model count")
        for id in expectedIds {
            TestRunner.assertTrue(models.contains { $0.id == id }, "OpenAI: Contains \(id)")
        }
    }

    static func testAnthropicExactModels() {
        let models = ModelConfigLoader.shared.models(for: .anthropic)
        let expectedIds = ["claude-sonnet-4-5-20250929", "claude-haiku-4-5-20251001", "claude-opus-4-5-20251101"]
        TestRunner.assertEqual(models.count, expectedIds.count, "Anthropic: Exact model count")
        for id in expectedIds {
            TestRunner.assertTrue(models.contains { $0.id == id }, "Anthropic: Contains \(id)")
        }
    }

    static func testGeminiExactModels() {
        let models = ModelConfigLoader.shared.models(for: .gemini)
        let expectedIds = ["gemini-2.5-flash", "gemini-2.5-pro", "gemini-2.0-flash"]
        TestRunner.assertEqual(models.count, expectedIds.count, "Gemini: Exact model count")
        for id in expectedIds {
            TestRunner.assertTrue(models.contains { $0.id == id }, "Gemini: Contains \(id)")
        }
    }

    static func testOpenAIDefaultModel() {
        let defaultModel = ModelConfigLoader.shared.defaultModel(for: .openai)
        TestRunner.assertTrue(defaultModel != nil, "OpenAI: Default model exists")
        TestRunner.assertEqual(defaultModel?.id, "gpt-4o", "OpenAI: Default is gpt-4o")
    }

    static func testAnthropicDefaultModel() {
        let defaultModel = ModelConfigLoader.shared.defaultModel(for: .anthropic)
        TestRunner.assertTrue(defaultModel != nil, "Anthropic: Default model exists")
        TestRunner.assertEqual(defaultModel?.id, "claude-sonnet-4-5-20250929", "Anthropic: Default is claude-sonnet-4-5")
    }

    static func testGeminiDefaultModel() {
        let defaultModel = ModelConfigLoader.shared.defaultModel(for: .gemini)
        TestRunner.assertTrue(defaultModel != nil, "Gemini: Default model exists")
        TestRunner.assertEqual(defaultModel?.id, "gemini-2.5-flash", "Gemini: Default is gemini-2.5-flash")
    }

    static func testAllModelsHaveValidIds() {
        for provider in [LLMProviderType.openai, .anthropic, .gemini] {
            let models = ModelConfigLoader.shared.models(for: provider)
            for model in models {
                TestRunner.assertTrue(!model.id.isEmpty, "\(provider.rawValue): \(model.name) has valid id")
                TestRunner.assertTrue(!model.id.contains(" "), "\(provider.rawValue): \(model.id) has no spaces")
            }
        }
    }

    static func testAllModelsHaveValidNames() {
        for provider in [LLMProviderType.openai, .anthropic, .gemini] {
            let models = ModelConfigLoader.shared.models(for: provider)
            for model in models {
                TestRunner.assertTrue(!model.name.isEmpty, "\(provider.rawValue): Model \(model.id) has name")
                TestRunner.assertTrue(model.name.count >= 3, "\(provider.rawValue): \(model.id) name is readable")
            }
        }
    }

    static func testAllModelsHaveValidDescriptions() {
        for provider in [LLMProviderType.openai, .anthropic, .gemini] {
            let models = ModelConfigLoader.shared.models(for: provider)
            for model in models {
                TestRunner.assertTrue(!model.description.isEmpty, "\(provider.rawValue): \(model.id) has description")
            }
        }
    }

    static func testNoEmptyModelLists() {
        for provider in [LLMProviderType.openai, .anthropic, .gemini] {
            let models = ModelConfigLoader.shared.models(for: provider)
            TestRunner.assertTrue(!models.isEmpty, "\(provider.rawValue): Model list not empty (JSON loaded)")
        }
    }

    static func testModelIdUniquenessPerProvider() {
        for provider in [LLMProviderType.openai, .anthropic, .gemini] {
            let models = ModelConfigLoader.shared.models(for: provider)
            let ids = models.map { $0.id }
            let uniqueIds = Set(ids)
            TestRunner.assertEqual(ids.count, uniqueIds.count, "\(provider.rawValue): All model IDs unique")
        }
    }
}

// MARK: - Main Entry Point

@main
struct ModelConfigLoaderTestsMain {
    static func main() {
        print("🧪 ModelConfigLoader Unit Tests")
        print(String(repeating: "=", count: 50))

        TestRunner.reset()
        ModelConfigLoaderTests.runAll()
        TestRunner.printSummary()

        if TestRunner.failedCount > 0 {
            exit(1)
        }
    }
}

