# Implementation Plan: Image Attachments

**Branch**: `012-image-attachments` | **Date**: 2026-05-19 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/012-image-attachments/spec.md`

## Summary

Add image attachment support to Extremis Chat Mode, allowing users to paste, drag-and-drop, or pick image files and send them to vision-capable LLMs. The feature includes vision capability detection per model, a thumbnail preview strip in the input area, provider-specific multimodal message formatting, and file-based image persistence for session restoration. All changes are additive — existing text-only flows remain untouched.

## Technical Context

**Language/Version**: Swift 5.9+
**Primary Dependencies**: AppKit (NSPasteboard, NSDragging), ImageIO (CGImageSource for efficient resizing/thumbnailing), SwiftUI
**Storage**: File-based image storage in `~/Library/Application Support/Extremis/images/`, JSON session persistence with file references and inline thumbnails
**Testing**: Standalone Swift test files using `TestRunner` pattern (per project conventions), added to `scripts/run-tests.sh`
**Target Platform**: macOS 13.0+ (Ventura)
**Project Type**: Single macOS app (Swift Package Manager)
**Performance Goals**: Image thumbnail renders in <1s, image attachment + send in <5s, UI remains responsive (60fps) during image processing
**Constraints**: Images resized to max 1568px long edge, compressed to <1MB JPEG before sending; max 5 images per message; Chat Mode only
**Scale/Scope**: Single-user desktop app, ~5-10 images per conversation typical

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Modularity & Separation of Concerns | PASS | Image processing, persistence, and UI are separate modules. New `ImageAttachment` model, `ImageProcessor` service, and `ImageAttachmentView` are independent components. No circular dependencies. |
| II. Code Quality & Best Practices | PASS | Follows Swift API Design Guidelines. Uses ImageIO (industry best practice) for resizing. Named constants for size limits and dimensions. |
| III. Extensibility & Testability | PASS | `supportsVision` capability flag follows existing `supportsTools` pattern. Image processing is pure function (testable). Provider-specific formatting is per-provider (extensible). |
| IV. User Experience Excellence | PASS | Instant thumbnail feedback (<1s). Clear vision capability indicators. Drop zone visual feedback. Non-intrusive error messages. |
| V. Documentation Synchronization | PASS | README and docs will be updated when feature ships. |
| VI. Testing Discipline | PASS | Unit tests for image processing, model capability detection, persistence, and message formatting. Edge case tests for format conversion, size limits. |
| VII. Regression Prevention | PASS | All changes additive. Existing text-only flows untouched. `ChatMessage` extended (not modified). Provider message formatting adds image branch without changing text path. |

**Quality Standards Gate**:
- Build: Compiles without warnings (verified per phase)
- Tests: All existing + new tests pass
- Manual QA: Text-only hotkey flows verified after each phase
- Performance: UI responsive during image processing

## Project Structure

### Documentation (this feature)

```text
specs/012-image-attachments/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output (internal contracts)
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
Extremis/
├── Core/
│   ├── Models/
│   │   ├── ChatMessage.swift        # MODIFY: Add imageAttachments property
│   │   ├── ImageAttachment.swift    # NEW: ImageAttachment model
│   │   └── Persistence/
│   │       └── PersistedMessage.swift  # MODIFY: Add image references
│   ├── Services/
│   │   └── ImageProcessor.swift     # NEW: Resize, compress, thumbnail, format conversion
│   └── Protocols/
│       └── LLMProvider.swift        # NO CHANGE (messages still [ChatMessage])
├── LLMProviders/
│   ├── PromptBuilder.swift          # MODIFY: Format multimodal content blocks
│   ├── OpenAIProvider.swift         # MODIFY: Add vision message format
│   ├── AnthropicProvider.swift      # MODIFY: Add multimodal message format
│   ├── GeminiProvider.swift         # MODIFY: Add inlineData parts
│   └── OllamaProvider.swift         # MODIFY: Add images array support
├── UI/
│   ├── PromptWindow/
│   │   ├── ChatInputView.swift      # MODIFY: Add attachment strip, drop zone, paste handling
│   │   ├── ImageAttachmentView.swift    # NEW: Thumbnail preview strip component
│   │   ├── ImageDropZoneView.swift      # NEW: Drop zone overlay
│   │   └── PromptWindowController.swift # MODIFY: Wire image state to chat flow
│   └── Components/
│       └── DesignSystem.swift       # MINOR: Add image-related tokens if needed
├── Utilities/
│   └── ImagePersistence.swift       # NEW: Save/load images to Application Support
├── Resources/
│   └── models.json                  # MODIFY: Add supportsVision capability
└── Tests/
    ├── Core/
    │   ├── ImageAttachmentTests.swift   # NEW
    │   └── ImageProcessorTests.swift    # NEW
    ├── LLMProviders/
    │   └── PromptBuilderImageTests.swift # NEW
    └── Utilities/
        └── ImagePersistenceTests.swift  # NEW
```

**Structure Decision**: Follows existing Extremis directory conventions. New files are placed in their natural module locations. All changes are additive — no files are deleted or renamed.

## Complexity Tracking

No constitution violations. All changes follow existing patterns.

## Implementation Phases

### Phase 1: Core Image Model & Processing (Foundation)

**Goal**: Establish the image data model, processing pipeline, and persistence layer without touching any UI or LLM provider code.

**Changes**:
1. `ImageAttachment` model — ID, imageData, thumbnailData, filename, dimensions, fileSize, format, mimeType
2. `ImageProcessor` service — resize (max 1568px), compress (JPEG 0.85), thumbnail (200px), HEIC→JPEG conversion, format validation
3. `ImagePersistence` utility — save images to `~/Library/Application Support/Extremis/images/{uuid}.jpg`, load by ID, cleanup orphaned images
4. `models.json` — add `"supportsVision": true/false` to model capabilities
5. `LLMModel` — read and expose `supportsVision` capability
6. Unit tests for all of the above

**Regression check**: Zero UI or provider changes. Existing flows unaffected.

### Phase 2: Provider Multimodal Message Formatting

**Goal**: Enable each LLM provider to format and send image content blocks alongside text, without changing the LLM provider protocol.

**Changes**:
1. `ChatMessage` — add optional `imageAttachments: [ImageAttachment]?` property (additive, nil by default)
2. `PersistedMessage` — add `imageRefs: [ImageRef]?` for file-based persistence with inline thumbnail data
3. `PromptBuilder` — new `formatMultimodalContent()` method that returns `[[String: Any]]` when images present, `[[String: String]]` when not
4. Per-provider formatting:
   - OpenAI: content array with `image_url` type (base64 data URI)
   - Anthropic: content array with `image` type and base64 source
   - Gemini: parts array with `inlineData`
   - Ollama: separate `images` array field (raw base64, no prefix)
5. Unit tests for each provider's multimodal message formatting

**Regression check**: Text-only messages continue using existing `[[String: String]]` path. Provider changes are in new code branches (if images present).

### Phase 3: UI — Image Attachment Input

**Goal**: Add the visual components for attaching, previewing, and removing images in Chat Mode's input area.

**Changes**:
1. `ImageAttachmentView` — horizontal thumbnail strip (80-120px thumbnails, X button to remove, "Pasted image" or filename label)
2. `ImageDropZoneView` — semi-transparent overlay with dashed border on drag enter
3. `ChatInputView` modifications:
   - Cmd+V paste handler: detect image on NSPasteboard, create ImageAttachment
   - `.onDrop` handler: accept image UTTypes, create ImageAttachments
   - Attachment button (paperclip icon): open NSOpenPanel filtered to image UTTypes
   - Show/hide attachment controls based on `supportsVision` capability
   - Allow send with images-only (no text required per FR-018)
4. `PromptWindowController` — wire pending image attachments into ChatMessage creation
5. Vision capability feedback: hide attach button for non-vision models, show brief toast if user attempts paste

**Regression check**: Quick Mode and Magic Mode untouched (FR-019). Text-only Chat Mode flow preserved. Attachment strip only appears when images are attached.

### Phase 4: Conversation History & Persistence

**Goal**: Display images in chat history and persist them across sessions.

**Changes**:
1. Chat bubble image rendering — inline thumbnails (max 300px wide), click to view full-size via macOS Quick Look or popover
2. Multiple images in a bubble — grid layout (2 columns for 2-4 images)
3. Session persistence — on save: write image files via `ImagePersistence`, store `ImageRef` (UUID + thumbnail base64) in `PersistedMessage`; on load: restore `ImageAttachment` from file refs
4. Failed send preservation — keep pending attachments on error (FR-016)
5. Integration tests for full flow: attach → send → display → save → reload → display

**Regression check**: Text-only conversations persist and load identically. Image files are additive storage.
