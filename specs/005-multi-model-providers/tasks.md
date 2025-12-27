# Tasks: Multi-Model Selection for Cloud Providers

## Pre-Implementation Checklist

- [ ] Review existing LLMProviderTests to understand test patterns
- [ ] Review PromptTemplateLoader for JSON loading pattern
- [ ] Verify all existing tests pass before starting

---

## Phase 1: Create JSON Model Configuration

### Task 1.1: Create models.json
- [ ] Create `Extremis/Resources/models.json`
- [ ] Add OpenAI models (gpt-4o, gpt-4o-mini, gpt-4-turbo, gpt-4, gpt-3.5-turbo)
- [ ] Add Anthropic models (claude-sonnet-4, claude-3.5-sonnet, claude-3.5-haiku, claude-3-opus)
- [ ] Add Gemini models (gemini-2.5-flash, gemini-1.5-pro, gemini-1.5-flash)
- [ ] Set default model for each provider
- [ ] Validate JSON syntax

### Task 1.2: Update Package.swift
- [ ] Add `models.json` to resources in Package.swift
- [ ] Verify resource is copied to bundle

---

## Phase 2: Create ModelConfigLoader

### Task 2.1: Create ModelConfigLoader.swift
- [ ] Create `Extremis/LLMProviders/ModelConfigLoader.swift`
- [ ] Define `ModelConfigError` enum with cases: configNotFound, loadingFailed, invalidFormat
- [ ] Create `ModelConfigLoader` class with singleton pattern
- [ ] Add `bundle: Bundle` property with `.module` default
- [ ] Add `config: ModelConfig?` cache property
- [ ] Add `cacheLock: NSLock` for thread safety

### Task 2.2: Implement Configuration Models
- [ ] Create `ModelConfig` struct (Codable): version, providers dict
- [ ] Create `ProviderConfig` struct (Codable): models array, default model id
- [ ] Ensure `LLMModel` is already Codable (verify existing)

### Task 2.3: Implement Loading Methods
- [ ] Implement `loadFromBundle()` - try subdirectory first, then root (like PromptTemplateLoader)
- [ ] Implement `loadConfig()` with caching
- [ ] Implement `models(for:)` - return empty for .ollama, load from config for others
- [ ] Implement `defaultModel(for:)` - find model matching default id
- [ ] Implement `preload()` for startup optimization
- [ ] Implement `clearCache()` for testing

---

## Phase 3: Update LLMProviderType

### Task 3.1: Modify availableModels Property
- [ ] In `Generation.swift`, update `availableModels` computed property
- [ ] For `.ollama`: keep existing hardcoded fallback models
- [ ] For cloud providers: call `ModelConfigLoader.shared.models(for: self)`
- [ ] Add fallback to hardcoded models if JSON loading fails (defensive)

### Task 3.2: Keep Hardcoded Fallback
- [ ] Create private `hardcodedModels` property with existing model definitions
- [ ] Only used if JSON loading fails (shouldn't happen in production)

---

## Phase 4: Update ProvidersTab UI

### Task 4.1: Add State Variables
- [ ] Add `@State private var openaiSelectedModelId: String = ""`
- [ ] Add `@State private var anthropicSelectedModelId: String = ""`
- [ ] Add `@State private var geminiSelectedModelId: String = ""`

### Task 4.2: Update ProviderKeyRow
- [ ] Add parameter: `@Binding var selectedModelId: String`
- [ ] Add parameter: `let availableModels: [LLMModel]`
- [ ] Add parameter: `let onSelectModel: (LLMModel) -> Void`
- [ ] Add model picker UI after API key section (only if isConfigured)
- [ ] Add `.onChange(of: selectedModelId)` handler

### Task 4.3: Update ProvidersTab
- [ ] Create `modelIdBinding(for:)` helper returning Binding<String>
- [ ] Create `selectModel(_:for:)` helper calling Registry + refreshMenuBar
- [ ] Update `loadCurrentSettings()` to load model IDs from Registry
- [ ] Update `ProviderKeyRow` instantiation with new parameters

---

## Phase 5: Add Unit Tests

### Task 5.1: Create ModelConfigLoaderTests.swift
- [ ] Create `Extremis/Tests/LLMProviders/ModelConfigLoaderTests.swift`
- [ ] Follow existing test pattern (TestRunner, static methods)

### Task 5.2: Implement Core Tests
- [ ] `testLoadOpenAIModels()` - verify non-empty, contains gpt-4o
- [ ] `testLoadAnthropicModels()` - verify non-empty
- [ ] `testLoadGeminiModels()` - verify non-empty
- [ ] `testOllamaReturnsEmpty()` - verify returns [] for Ollama

### Task 5.3: Implement Default Model Tests
- [ ] `testDefaultModelExists()` - verify each provider has default
- [ ] `testDefaultModelInList()` - verify default is in models list

### Task 5.4: Implement Edge Case Tests
- [ ] `testModelHasRequiredFields()` - verify id, name, description
- [ ] `testCaching()` - verify same results on repeated calls
- [ ] `testClearCache()` - verify cache can be cleared

### Task 5.5: Update Test Runner
- [ ] Update `scripts/run-tests.sh` to include ModelConfigLoaderTests
- [ ] Verify all tests pass

---

## Phase 6: Integration Testing

### Task 6.1: Build Verification
- [ ] Run `swift build` - no compiler errors
- [ ] Run `./scripts/run-tests.sh` - all tests pass

### Task 6.2: Manual Testing - Model Selection
- [ ] Configure OpenAI with API key
- [ ] Verify model picker appears with correct models
- [ ] Select different model, verify UI updates
- [ ] Configure Anthropic, test model picker
- [ ] Configure Gemini, test model picker

### Task 6.3: Manual Testing - Ollama Unchanged
- [ ] Connect to Ollama server
- [ ] Verify model picker shows server-discovered models
- [ ] Verify no JSON-based models appear for Ollama

### Task 6.4: Manual Testing - Persistence
- [ ] Select non-default models for each provider
- [ ] Restart app
- [ ] Verify selections persist

### Task 6.5: Manual Testing - Header Display
- [ ] Switch active providers
- [ ] Verify header shows correct model name each time

### Task 6.6: Test Adding Model to JSON
- [ ] Add a test model to models.json
- [ ] Rebuild app
- [ ] Verify new model appears in picker

---

## Files Summary

| File | Action |
|------|--------|
| `Extremis/Resources/models.json` | CREATE |
| `Extremis/LLMProviders/ModelConfigLoader.swift` | CREATE |
| `Extremis/Core/Models/Generation.swift` | MODIFY |
| `Extremis/UI/Preferences/ProvidersTab.swift` | MODIFY |
| `Extremis/Tests/LLMProviders/ModelConfigLoaderTests.swift` | CREATE |
| `scripts/run-tests.sh` | MODIFY |
| `Package.swift` | MODIFY |

---

## Acceptance Criteria

- [ ] All unit tests pass (existing + new)
- [ ] Model dropdown visible for configured OpenAI/Anthropic/Gemini
- [ ] Model dropdown hidden when provider not configured
- [ ] Ollama unchanged - uses API discovery, not JSON
- [ ] Selected model persists after app restart
- [ ] Header shows correct model name for active provider
- [ ] Adding model to JSON and rebuilding shows new model
- [ ] No regressions to any existing functionality

