# Implementation Plan: Multi-Model Selection for Cloud Providers

## Overview

Add model selection dropdown to Anthropic, Gemini, and OpenAI providers with model definitions loaded from a JSON configuration file. This makes adding/removing models trivial - just edit the JSON file.

**Key Principles:**
1. JSON-based model configuration (single source of truth)
2. Don't touch Ollama (already uses dynamic API discovery)
3. Unit tests for all new code
4. No regressions to existing functionality

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    ProvidersTab (UI)                        │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐           │
│  │   OpenAI    │ │  Anthropic  │ │   Gemini    │  Ollama   │
│  │   [Model▼]  │ │   [Model▼]  │ │   [Model▼]  │  (no chg) │
│  └──────┬──────┘ └──────┬──────┘ └──────┬──────┘           │
└─────────┼───────────────┼───────────────┼──────────────────┘
          │               │               │
          ▼               ▼               ▼
┌─────────────────────────────────────────────────────────────┐
│              LLMProviderRegistry.availableModels()          │
│                           │                                 │
│                           ▼                                 │
│              ModelConfigLoader.models(for:)                 │
│                           │                                 │
│                           ▼                                 │
│              Resources/models.json                          │
└─────────────────────────────────────────────────────────────┘
```

## Phases

### Phase 1: Create JSON Model Configuration (15 min)

**New File:** `Extremis/Resources/models.json`

```json
{
  "version": 1,
  "providers": {
    "openai": {
      "models": [
        {"id": "gpt-4o", "name": "GPT-4o", "description": "Most capable, multimodal"},
        {"id": "gpt-4o-mini", "name": "GPT-4o Mini", "description": "Fast and affordable"},
        {"id": "gpt-4-turbo", "name": "GPT-4 Turbo", "description": "Powerful with vision"},
        {"id": "gpt-4", "name": "GPT-4", "description": "Original GPT-4"},
        {"id": "gpt-3.5-turbo", "name": "GPT-3.5 Turbo", "description": "Fast and cheap"}
      ],
      "default": "gpt-4o"
    },
    "anthropic": {
      "models": [
        {"id": "claude-sonnet-4-20250514", "name": "Claude Sonnet 4", "description": "Best balance"},
        {"id": "claude-3-5-sonnet-20241022", "name": "Claude 3.5 Sonnet", "description": "Fast and intelligent"},
        {"id": "claude-3-5-haiku-20241022", "name": "Claude 3.5 Haiku", "description": "Fastest"},
        {"id": "claude-3-opus-20240229", "name": "Claude 3 Opus", "description": "Most capable"}
      ],
      "default": "claude-sonnet-4-20250514"
    },
    "gemini": {
      "models": [
        {"id": "gemini-2.5-flash", "name": "Gemini 2.0 Flash", "description": "Latest, fastest"},
        {"id": "gemini-1.5-pro", "name": "Gemini 1.5 Pro", "description": "Best for complex tasks"},
        {"id": "gemini-1.5-flash", "name": "Gemini 1.5 Flash", "description": "Fast and versatile"}
      ],
      "default": "gemini-2.5-flash"
    }
  }
}
```

### Phase 2: Create ModelConfigLoader (30 min)

**New File:** `Extremis/LLMProviders/ModelConfigLoader.swift`

Following the same pattern as `PromptTemplateLoader`:

```swift
// MARK: - Model Configuration Loader
// Loads LLM model definitions from JSON configuration

import Foundation

/// Error types for model config loading
enum ModelConfigError: Error, LocalizedError {
    case configNotFound
    case loadingFailed(underlying: Error)
    case invalidFormat
    case providerNotFound(LLMProviderType)

    var errorDescription: String? {
        switch self {
        case .configNotFound:
            return "Model configuration file 'models.json' not found"
        case .loadingFailed(let error):
            return "Failed to load model config: \(error.localizedDescription)"
        case .invalidFormat:
            return "Invalid model configuration format"
        case .providerNotFound(let provider):
            return "Provider '\(provider.rawValue)' not found in config"
        }
    }
}

/// Loads and caches model configuration from JSON
final class ModelConfigLoader {

    // MARK: - Singleton
    static let shared = ModelConfigLoader()

    // MARK: - Properties
    private var config: ModelConfig?
    private let cacheLock = NSLock()
    private let bundle: Bundle

    // MARK: - Initialization
    init(bundle: Bundle = .module) {
        self.bundle = bundle
    }

    // MARK: - Public Methods

    /// Get models for a provider (excludes Ollama - uses API discovery)
    func models(for provider: LLMProviderType) -> [LLMModel] {
        guard provider != .ollama else { return [] }

        do {
            let config = try loadConfig()
            return config.providers[provider.rawValue]?.models ?? []
        } catch {
            print("⚠️ ModelConfigLoader: \(error.localizedDescription)")
            return []
        }
    }

    /// Get default model for a provider
    func defaultModel(for provider: LLMProviderType) -> LLMModel? {
        guard provider != .ollama else { return nil }

        do {
            let config = try loadConfig()
            guard let providerConfig = config.providers[provider.rawValue] else { return nil }
            return providerConfig.models.first { $0.id == providerConfig.defaultModelId }
                ?? providerConfig.models.first
        } catch {
            return nil
        }
    }

    /// Preload configuration at startup
    func preload() {
        _ = try? loadConfig()
    }

    /// Clear cache (for testing)
    func clearCache() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        config = nil
    }

    // MARK: - Private Methods

    private func loadConfig() throws -> ModelConfig {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        if let cached = config {
            return cached
        }

        let loaded = try loadFromBundle()
        config = loaded
        return loaded
    }

    private func loadFromBundle() throws -> ModelConfig {
        // Try with subdirectory first, then without (SPM flattens resources)
        let url = bundle.url(forResource: "models", withExtension: "json", subdirectory: nil)
            ?? bundle.url(forResource: "models", withExtension: "json")

        guard let configURL = url else {
            throw ModelConfigError.configNotFound
        }

        do {
            let data = try Data(contentsOf: configURL)
            let decoder = JSONDecoder()
            return try decoder.decode(ModelConfig.self, from: data)
        } catch {
            throw ModelConfigError.loadingFailed(underlying: error)
        }
    }
}

// MARK: - Configuration Models

struct ModelConfig: Codable {
    let version: Int
    let providers: [String: ProviderConfig]
}

struct ProviderConfig: Codable {
    let models: [LLMModel]
    let defaultModelId: String

    enum CodingKeys: String, CodingKey {
        case models
        case defaultModelId = "default"
    }
}
```

### Phase 3: Update LLMProviderType (20 min)

**File:** `Extremis/Core/Models/Generation.swift`

Modify `availableModels` to use `ModelConfigLoader` for cloud providers:

```swift
/// Available models for this provider
var availableModels: [LLMModel] {
    switch self {
    case .ollama:
        // Ollama uses dynamic discovery - these are fallback defaults
        return [
            LLMModel(id: "llama3.2", name: "Llama 3.2", description: "Meta's latest"),
            LLMModel(id: "mistral", name: "Mistral", description: "Fast and capable"),
        ]
    default:
        // Cloud providers: load from JSON config
        let models = ModelConfigLoader.shared.models(for: self)
        // Fallback to hardcoded if config fails (shouldn't happen)
        return models.isEmpty ? hardcodedModels : models
    }
}

/// Hardcoded fallback (only used if JSON loading fails)
private var hardcodedModels: [LLMModel] {
    // Keep existing hardcoded models as emergency fallback
    ...
}
```

### Phase 4: Update ProvidersTab UI (30 min)

**File:** `Extremis/UI/Preferences/ProvidersTab.swift`

1. Add state for model selection per provider
2. Add model picker to `ProviderKeyRow`
3. Wire up callbacks

### Phase 5: Add Unit Tests (45 min)

**New File:** `Extremis/Tests/LLMProviders/ModelConfigLoaderTests.swift`

```swift
// MARK: - ModelConfigLoader Unit Tests

import Foundation

struct ModelConfigLoaderTests {

    static func runAll() {
        print("\n📦 ModelConfigLoader Tests")
        print(String(repeating: "-", count: 40))

        testLoadOpenAIModels()
        testLoadAnthropicModels()
        testLoadGeminiModels()
        testOllamaReturnsEmpty()
        testDefaultModelExists()
        testModelHasRequiredFields()
        testCaching()
        testInvalidProviderHandled()
    }

    static func testLoadOpenAIModels() {
        let models = ModelConfigLoader.shared.models(for: .openai)
        TestRunner.assertTrue(!models.isEmpty, "OpenAI: Has models")
        TestRunner.assertTrue(models.contains { $0.id == "gpt-4o" }, "OpenAI: Contains gpt-4o")
    }

    static func testLoadAnthropicModels() {
        let models = ModelConfigLoader.shared.models(for: .anthropic)
        TestRunner.assertTrue(!models.isEmpty, "Anthropic: Has models")
    }

    static func testLoadGeminiModels() {
        let models = ModelConfigLoader.shared.models(for: .gemini)
        TestRunner.assertTrue(!models.isEmpty, "Gemini: Has models")
    }

    static func testOllamaReturnsEmpty() {
        let models = ModelConfigLoader.shared.models(for: .ollama)
        TestRunner.assertTrue(models.isEmpty, "Ollama: Returns empty (uses API)")
    }

    static func testDefaultModelExists() {
        for provider in [LLMProviderType.openai, .anthropic, .gemini] {
            let defaultModel = ModelConfigLoader.shared.defaultModel(for: provider)
            TestRunner.assertTrue(defaultModel != nil, "\(provider.rawValue): Has default model")
        }
    }

    static func testModelHasRequiredFields() {
        let models = ModelConfigLoader.shared.models(for: .openai)
        if let model = models.first {
            TestRunner.assertTrue(!model.id.isEmpty, "Model: Has id")
            TestRunner.assertTrue(!model.name.isEmpty, "Model: Has name")
        }
    }

    static func testCaching() {
        // Load twice, should use cache
        let models1 = ModelConfigLoader.shared.models(for: .openai)
        let models2 = ModelConfigLoader.shared.models(for: .openai)
        TestRunner.assertEqual(models1.count, models2.count, "Caching: Same results")
    }

    static func testInvalidProviderHandled() {
        // Should not crash, return empty
        let models = ModelConfigLoader.shared.models(for: .ollama)
        TestRunner.assertTrue(models.isEmpty, "Invalid: Handled gracefully")
    }
}
```

### Phase 6: Integration Testing (20 min)

1. Build and run app
2. Verify model picker appears for OpenAI/Anthropic/Gemini
3. Verify Ollama unchanged (still uses API discovery)
4. Verify model selection persists
5. Verify header shows correct model
6. Test adding a model to JSON (rebuild, verify appears)

## File Summary

| File | Action | Description |
|------|--------|-------------|
| `Extremis/Resources/models.json` | CREATE | Model definitions for cloud providers |
| `Extremis/LLMProviders/ModelConfigLoader.swift` | CREATE | JSON loader with caching |
| `Extremis/Core/Models/Generation.swift` | MODIFY | Use ModelConfigLoader for cloud providers |
| `Extremis/UI/Preferences/ProvidersTab.swift` | MODIFY | Add model picker UI |
| `Extremis/Tests/LLMProviders/ModelConfigLoaderTests.swift` | CREATE | Unit tests |
| `scripts/run-tests.sh` | MODIFY | Add new test suite |
| `Package.swift` | MODIFY | Add models.json to resources |

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| JSON loading fails | Keep hardcoded fallback in `LLMProviderType` |
| Breaking Ollama | Explicit check: `guard provider != .ollama` |
| Model persistence breaks | No changes to `setModel()` / UserDefaults logic |
| Missing tests | Comprehensive unit tests in Phase 5 |
| Bundle resource issues | Follow PromptTemplateLoader pattern exactly |

## Rollback Plan

If issues arise:
1. Revert `Generation.swift` to use hardcoded models
2. Keep JSON and loader for future use
3. UI changes are additive, easy to revert

## Testing Checklist

- [ ] Unit tests pass for ModelConfigLoader
- [ ] All existing LLM provider tests pass
- [ ] OpenAI model picker works
- [ ] Anthropic model picker works
- [ ] Gemini model picker works
- [ ] Ollama unchanged (API discovery works)
- [ ] Model selection persists after restart
- [ ] Adding model to JSON works after rebuild
- [ ] Header shows correct model name

## Estimated Time

| Phase | Time |
|-------|------|
| Phase 1: JSON config | 15 min |
| Phase 2: ModelConfigLoader | 30 min |
| Phase 3: Update LLMProviderType | 20 min |
| Phase 4: UI changes | 30 min |
| Phase 5: Unit tests | 45 min |
| Phase 6: Integration testing | 20 min |
| **Total** | **~2.5 hours** |

