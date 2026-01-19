# Tasks: Multi-Model Selection for Cloud Providers

**Status**: ✅ FEATURE COMPLETE
**Completed**: 2026-01-19

**Note**: Multi-model selection has been fully implemented. Users can select different models for each cloud provider (OpenAI, Anthropic, Gemini) via the Preferences UI. Ollama continues to use server-discovered models.

## Pre-Implementation Checklist ✅

- [x] Review existing LLMProviderTests to understand test patterns
- [x] Review PromptTemplateLoader for JSON loading pattern
- [x] Verify all existing tests pass before starting

---

## Phase 1: Create JSON Model Configuration ✅

### Task 1.1: Create models.json
- [x] Create `Extremis/Resources/models.json`
- [x] Add OpenAI models (gpt-4o, gpt-4o-mini, gpt-4-turbo, gpt-4, gpt-3.5-turbo)
- [x] Add Anthropic models (claude-sonnet-4, claude-3.5-sonnet, claude-3.5-haiku, claude-3-opus)
- [x] Add Gemini models (gemini-2.5-flash, gemini-1.5-pro, gemini-1.5-flash)
- [x] Set default model for each provider
- [x] Validate JSON syntax

### Task 1.2: Update Package.swift
- [x] Add `models.json` to resources in Package.swift
- [x] Verify resource is copied to bundle

---

## Phase 2: Create ModelConfigLoader ✅

### Task 2.1: Create ModelConfigLoader.swift
- [x] Create `Extremis/LLMProviders/ModelConfigLoader.swift`
- [x] Define `ModelConfigError` enum with cases: configNotFound, loadingFailed, invalidFormat
- [x] Create `ModelConfigLoader` class with singleton pattern
- [x] Add `bundle: Bundle` property with `.module` default
- [x] Add `config: ModelConfig?` cache property
- [x] Add `cacheLock: NSLock` for thread safety

### Task 2.2: Implement Configuration Models
- [x] Create `ModelConfig` struct (Codable): version, providers dict
- [x] Create `ProviderConfig` struct (Codable): models array, default model id
- [x] Ensure `LLMModel` is already Codable (verify existing)

### Task 2.3: Implement Loading Methods
- [x] Implement `loadFromBundle()` - try subdirectory first, then root (like PromptTemplateLoader)
- [x] Implement `loadConfig()` with caching
- [x] Implement `models(for:)` - return empty for .ollama, load from config for others
- [x] Implement `defaultModel(for:)` - find model matching default id
- [x] Implement `preload()` for startup optimization
- [x] Implement `clearCache()` for testing

---

## Phase 3: Update LLMProviderType ✅

### Task 3.1: Modify availableModels Property
- [x] In `Generation.swift`, update `availableModels` computed property
- [x] For `.ollama`: keep existing hardcoded fallback models
- [x] For cloud providers: call `ModelConfigLoader.shared.models(for: self)`
- [x] Add fallback to hardcoded models if JSON loading fails (defensive)

### Task 3.2: Keep Hardcoded Fallback
- [x] Create private `hardcodedModels` property with existing model definitions
- [x] Only used if JSON loading fails (shouldn't happen in production)

---

## Phase 4: Update ProvidersTab UI ✅

### Task 4.1: Add State Variables
- [x] Add `@State private var openaiSelectedModelId: String = ""`
- [x] Add `@State private var anthropicSelectedModelId: String = ""`
- [x] Add `@State private var geminiSelectedModelId: String = ""`

### Task 4.2: Update ProviderKeyRow
- [x] Add parameter: `@Binding var selectedModelId: String`
- [x] Add parameter: `let availableModels: [LLMModel]`
- [x] Add parameter: `let onSelectModel: (LLMModel) -> Void`
- [x] Add model picker UI after API key section (only if isConfigured)
- [x] Add `.onChange(of: selectedModelId)` handler

### Task 4.3: Update ProvidersTab
- [x] Create `modelIdBinding(for:)` helper returning Binding<String>
- [x] Create `selectModel(_:for:)` helper calling Registry + refreshMenuBar
- [x] Update `loadCurrentSettings()` to load model IDs from Registry
- [x] Update `ProviderKeyRow` instantiation with new parameters

---

## Phase 5: Add Unit Tests ✅

### Task 5.1: Create ModelConfigLoaderTests.swift
- [x] Create `Extremis/Tests/LLMProviders/ModelConfigLoaderTests.swift`
- [x] Follow existing test pattern (TestRunner, static methods)

### Task 5.2: Implement Core Tests
- [x] `testLoadOpenAIModels()` - verify non-empty, contains gpt-4o
- [x] `testLoadAnthropicModels()` - verify non-empty
- [x] `testLoadGeminiModels()` - verify non-empty
- [x] `testOllamaReturnsEmpty()` - verify returns [] for Ollama

### Task 5.3: Implement Default Model Tests
- [x] `testDefaultModelExists()` - verify each provider has default
- [x] `testDefaultModelInList()` - verify default is in models list

### Task 5.4: Implement Edge Case Tests
- [x] `testModelHasRequiredFields()` - verify id, name, description
- [x] `testCaching()` - verify same results on repeated calls
- [x] `testClearCache()` - verify cache can be cleared

### Task 5.5: Update Test Runner
- [x] Update `scripts/run-tests.sh` to include ModelConfigLoaderTests
- [x] Verify all tests pass

---

## Phase 6: Integration Testing ✅

### Task 6.1: Build Verification
- [x] Run `swift build` - no compiler errors
- [x] Run `./scripts/run-tests.sh` - all tests pass

### Task 6.2: Manual Testing - Model Selection
- [x] Configure OpenAI with API key
- [x] Verify model picker appears with correct models
- [x] Select different model, verify UI updates
- [x] Configure Anthropic, test model picker
- [x] Configure Gemini, test model picker

### Task 6.3: Manual Testing - Ollama Unchanged
- [x] Connect to Ollama server
- [x] Verify model picker shows server-discovered models
- [x] Verify no JSON-based models appear for Ollama

### Task 6.4: Manual Testing - Persistence
- [x] Select non-default models for each provider
- [x] Restart app
- [x] Verify selections persist

### Task 6.5: Manual Testing - Header Display
- [x] Switch active providers
- [x] Verify header shows correct model name each time

### Task 6.6: Test Adding Model to JSON
- [x] Add a test model to models.json
- [x] Rebuild app
- [x] Verify new model appears in picker

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

## Acceptance Criteria ✅

- [x] All unit tests pass (existing + new)
- [x] Model dropdown visible for configured OpenAI/Anthropic/Gemini
- [x] Model dropdown hidden when provider not configured
- [x] Ollama unchanged - uses API discovery, not JSON
- [x] Selected model persists after app restart
- [x] Header shows correct model name for active provider
- [x] Adding model to JSON and rebuilding shows new model
- [x] No regressions to any existing functionality

