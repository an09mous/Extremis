# Feature Specification: Multi-Model Selection for Cloud Providers

## Overview

Add model selection dropdown for Anthropic, Gemini, and OpenAI providers. Model definitions will be stored in a **JSON configuration file** for easy maintenance. Ollama remains unchanged (uses dynamic API discovery).

## Problem Statement

Currently, cloud providers have hardcoded model lists but no UI for users to select between them. Users are stuck with the default model. Ollama already has model selection via a dropdown picker. We need:
1. Feature parity with Ollama
2. Easy model list maintenance without code changes

## Goals

1. **Model Selection UI** - Add model picker dropdown to cloud provider rows
2. **JSON Configuration** - Single JSON file for all cloud provider models
3. **Persistent Selection** - Remember user's model choice per provider
4. **Menu Bar Display** - Show selected model name in header
5. **Unit Tests** - Comprehensive tests for new code

## Non-Goals

- Dynamic model fetching from cloud provider APIs
- Model-specific configuration (temperature, max tokens)
- Per-conversation model switching
- Changing Ollama implementation (already works)

## Architecture

```
ProvidersTab (UI)
  │
  ▼
LLMProviderRegistry.availableModels()
  │
  ▼
ModelConfigLoader.models(for:)  ← NEW
  │
  ▼
Resources/models.json           ← NEW
```

## JSON Configuration Format

**File:** `Extremis/Resources/models.json`

```json
{
  "version": 1,
  "providers": {
    "openai": {
      "models": [
        {"id": "gpt-4o", "name": "GPT-4o", "description": "Most capable"},
        {"id": "gpt-4o-mini", "name": "GPT-4o Mini", "description": "Fast"}
      ],
      "default": "gpt-4o"
    },
    "anthropic": {
      "models": [
        {"id": "claude-sonnet-4-20250514", "name": "Claude Sonnet 4", "description": "Best balance"}
      ],
      "default": "claude-sonnet-4-20250514"
    },
    "gemini": {
      "models": [
        {"id": "gemini-2.5-flash", "name": "Gemini 2.0 Flash", "description": "Latest"}
      ],
      "default": "gemini-2.5-flash"
    }
  }
}
```

## Key Components

### 1. ModelConfigLoader (New)

```swift
final class ModelConfigLoader {
    static let shared = ModelConfigLoader()

    func models(for provider: LLMProviderType) -> [LLMModel]
    func defaultModel(for provider: LLMProviderType) -> LLMModel?
    func preload()
}
```

### 2. Updated LLMProviderType.availableModels

```swift
var availableModels: [LLMModel] {
    switch self {
    case .ollama:
        return [/* hardcoded fallback */]
    default:
        return ModelConfigLoader.shared.models(for: self)
    }
}
```

## Adding/Removing Models

**To add a model:** Edit `models.json` and rebuild
**To remove a model:** Delete from `models.json` and rebuild
**No code changes required**

## File Changes

| File | Action |
|------|--------|
| `Extremis/Resources/models.json` | CREATE |
| `Extremis/LLMProviders/ModelConfigLoader.swift` | CREATE |
| `Extremis/Core/Models/Generation.swift` | MODIFY |
| `Extremis/UI/Preferences/ProvidersTab.swift` | MODIFY |
| `Extremis/Tests/LLMProviders/ModelConfigLoaderTests.swift` | CREATE |
| `Package.swift` | MODIFY |

## Success Criteria

- [ ] All unit tests pass (existing + new)
- [ ] Model dropdown appears for configured cloud providers
- [ ] Ollama unchanged (uses API discovery)
- [ ] Selection persists across app restart
- [ ] Adding model to JSON + rebuild shows new model
