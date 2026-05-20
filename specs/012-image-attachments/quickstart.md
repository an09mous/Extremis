# Quickstart: Image Attachments

**Feature**: 012-image-attachments
**Branch**: `012-image-attachments`

## Prerequisites

- macOS 13.0+ (Ventura)
- Swift 5.9+
- Existing Extremis build environment (`swift build` succeeds on `main`)

## Implementation Order

Work through these phases sequentially. Each phase is independently buildable and testable. Run `./scripts/run-tests.sh` after each phase to verify no regressions.

### Phase 1: Core Image Model & Processing

1. Create `Extremis/Core/Models/ImageAttachment.swift`
   - `ImageAttachment` struct (Codable, Identifiable, Equatable)
   - `ImageFormat` enum
   - `ImageSourceType` enum
   - `ImageRef` struct for persistence

2. Create `Extremis/Core/Services/ImageProcessor.swift`
   - Singleton service with processing pipeline
   - Uses `ImageIO` framework (import `ImageIO`, `UniformTypeIdentifiers`)
   - Key function: `process(data:sourceType:originalFilename:) throws -> ImageAttachment`
   - Resize via `CGImageSourceCreateThumbnailAtIndex`
   - HEIC/WebP/GIF → JPEG conversion via `CGImageDestination`
   - Thumbnail generation

3. Create `Extremis/Utilities/ImagePersistence.swift`
   - Actor for thread-safe file I/O
   - Save/load/delete images in `~/Library/Application Support/Extremis/images/`

4. Update `Extremis/Resources/models.json`
   - Add `"supportsVision": true/false` to each model's capabilities
   - Update `LLMModel` to read the new field

5. Write tests:
   - `Tests/Core/ImageAttachmentTests.swift`
   - `Tests/Core/ImageProcessorTests.swift`
   - `Tests/Utilities/ImagePersistenceTests.swift`
   - Add all to `scripts/run-tests.sh`

**Verify**: `swift build` succeeds, all tests pass, no existing tests broken.

### Phase 2: Provider Multimodal Formatting

1. Extend `ChatMessage` — add `imageAttachments: [ImageAttachment]?`
2. Extend `PersistedMessage` — add `imageRefs: [ImageRef]?`
3. Extend `PromptBuilder` — add `formatChatMessagesMultimodal()` method
4. Update each provider's request builder:
   - `OpenAIProvider` — content array with `image_url` type
   - `AnthropicProvider` — content array with `image` + base64 source
   - `GeminiProvider` — parts array with `inlineData`
   - `OllamaProvider` — separate `images` field
5. Write tests:
   - `Tests/LLMProviders/PromptBuilderImageTests.swift`
   - Add to `scripts/run-tests.sh`

**Verify**: `swift build` succeeds, text-only message formatting unchanged, all tests pass.

### Phase 3: UI — Image Input

1. Create `Extremis/UI/PromptWindow/ImageAttachmentView.swift` — thumbnail strip
2. Create `Extremis/UI/PromptWindow/ImageDropZoneView.swift` — drop zone overlay
3. Modify `ChatInputView.swift`:
   - Add pending attachments state
   - Clipboard paste interception (NSPasteboard image detection)
   - `.onDrop` modifier for drag-and-drop
   - Attachment button (paperclip icon) → NSOpenPanel
   - Vision capability gating
4. Modify `PromptWindowController.swift`:
   - Wire pending attachments into message creation
   - Pass `supportsVision` from current model to ChatInputView

**Verify**: Build succeeds, paste/drop/pick all create thumbnails, text-only flow unchanged.

### Phase 4: History Display & Persistence

1. Update chat bubble view — inline image thumbnails, click-to-expand
2. Update session save — `ImagePersistence.save()` + `ImageRef` in `PersistedMessage`
3. Update session load — `ImagePersistence.restore()` from `ImageRef`
4. Error handling — preserve attachments on send failure, placeholder on missing image file

**Verify**: Full flow works: attach → send → display → save → quit → relaunch → display.

## Key Files Reference

| File | Action | Phase |
|------|--------|-------|
| `Core/Models/ImageAttachment.swift` | NEW | 1 |
| `Core/Services/ImageProcessor.swift` | NEW | 1 |
| `Utilities/ImagePersistence.swift` | NEW | 1 |
| `Resources/models.json` | MODIFY | 1 |
| `Core/Models/ChatMessage.swift` | MODIFY | 2 |
| `Core/Models/Persistence/PersistedMessage.swift` | MODIFY | 2 |
| `LLMProviders/PromptBuilder.swift` | MODIFY | 2 |
| `LLMProviders/OpenAIProvider.swift` | MODIFY | 2 |
| `LLMProviders/AnthropicProvider.swift` | MODIFY | 2 |
| `LLMProviders/GeminiProvider.swift` | MODIFY | 2 |
| `LLMProviders/OllamaProvider.swift` | MODIFY | 2 |
| `UI/PromptWindow/ImageAttachmentView.swift` | NEW | 3 |
| `UI/PromptWindow/ImageDropZoneView.swift` | NEW | 3 |
| `UI/PromptWindow/ChatInputView.swift` | MODIFY | 3 |
| `UI/PromptWindow/PromptWindowController.swift` | MODIFY | 3 |
| Chat bubble view | MODIFY | 4 |
| `Core/Services/JSONSessionStorage.swift` | MODIFY | 4 |

## Running Tests

```bash
# All tests
cd Extremis && ./scripts/run-tests.sh

# Single test file
swiftc -parse-as-library Tests/Core/ImageProcessorTests.swift -o /tmp/test && /tmp/test
```
